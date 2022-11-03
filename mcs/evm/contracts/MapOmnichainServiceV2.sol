// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IWToken.sol";
import "./interface/IMAPToken.sol";
import "./utils/TransferHelper.sol";
import "./interface/IMCS.sol";
import "./interface/ILightNode.sol";
import "./utils/RLPReader.sol";
import "./utils/Utils.sol";
import "./utils/EventDecoder.sol";


contract MapOmnichainServiceV2 is ReentrancyGuard, Initializable, Pausable, IMCS, UUPSUpgradeable {
    using SafeMath for uint;
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    uint public nonce;
    ILightNode public lightNode;
    address public wToken;          // native wrapped token

    uint public immutable selfChainId = block.chainid;

    mapping(bytes32 => bool) public orderList;
    mapping(address => bool) public mintableTokens;

    address public relayContract;
    uint256 public relayChainId;

    mapping(uint256 => mapping(address => bool)) tokenMappingList;

    event mapTransferOut(bytes token, bytes from, bytes32 orderId,
        uint fromChain, uint toChain, bytes to, uint amount, bytes toChainToken);
    event mapTransferIn(address indexed token, bytes indexed from, bytes32 indexed orderId,
        uint fromChain, uint toChain, address to, uint amount);

    event mapDepositOut(address token, bytes from, bytes32 orderId, address to, uint256 amount);

    modifier checkAddress(address _address){
        require(_address != address(0), "address is zero");
        _;
    }

    function initialize(address _wToken, address _lightNode)
    public initializer checkAddress(_wToken) checkAddress(_lightNode) {
        wToken = _wToken;
        lightNode = ILightNode(_lightNode);
        _changeAdmin(msg.sender);
    }

    receive() external payable {
        require(msg.sender == wToken, "only wToken");
    }

    modifier checkOrder(bytes32 orderId) {
        require(!orderList[orderId], "order exist");
        orderList[orderId] = true;
        _;
    }

    modifier checkBridgeable(address token, uint chainId) {
        require(tokenMappingList[chainId][token], "token not registered");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _getAdmin(), "lightnode :: only admin");
        _;
    }

    function setPause() external onlyOwner {
        _pause();
    }

    function setUnpause() external onlyOwner {
        _unpause();
    }

    function getOrderID(address token, address from, bytes memory to, uint amount, uint toChainID) internal returns (bytes32){
        return keccak256(abi.encodePacked(nonce++, from, to, token, amount, selfChainId, toChainID));
    }

    function addMintableToken(address[] memory token) external onlyOwner {
        for (uint i = 0; i < token.length; i++) {
            mintableTokens[token[i]] = true;
        }
    }

    function removeMintableToken(address[] memory token) external onlyOwner {
        for (uint i = 0; i < token.length; i++) {
            mintableTokens[token[i]] = false;
        }
    }

    function setRelayContract(uint256 _chainId, address _relay) public onlyOwner checkAddress(_relay) {
        relayContract = _relay;
        relayChainId = _chainId;
    }

    function checkMintable(address _token) public view returns (bool) {
        return mintableTokens[_token];
    }

    function setBridgeToken(address _token, uint _toChain, bool _enable) public onlyOwner {
        tokenMappingList[_toChain][_token] = _enable;
    }

    function transferIn(uint _chainId, bytes memory _receiptProof) external override nonReentrant whenNotPaused {
        require(_chainId == relayChainId, "invalid chain id");
        (bool sucess, string memory message, bytes memory logArray) = lightNode.verifyProofData(_receiptProof);
        require(sucess, message);
        EventDecoder.txLog[] memory logs = EventDecoder.decodeTxLogs(logArray);

        for (uint i = 0; i < logs.length; i++) {
            EventDecoder.txLog memory log = logs[i];
            bytes32 topic = abi.decode(log.topics[0], (bytes32));
            if (topic == EventDecoder.MAP_TRANSFEROUT_TOPIC) {
                require(relayContract == log.addr, "invalid mos contract");
                (,bytes memory from,bytes32 orderId,uint fromChain, uint toChain, bytes memory to, uint amount, bytes memory toChainToken)
                = abi.decode(log.data, (bytes, bytes, bytes32, uint, uint, bytes, uint, bytes));
                address token = Utils.fromBytes(toChainToken);
                address payable toAddress = payable(Utils.fromBytes(to));
                _transferIn(token, from, toAddress, amount, orderId, fromChain, toChain);
            }
        }
    }


    function transferOut(address toContract, uint toChain, bytes memory data) external override whenNotPaused {

    }

    function transferOutToken(address _token, bytes memory _to, uint256 _amount, uint256 _toChain)
    external override
    whenNotPaused
    checkBridgeable(_token, _toChain) {
        require(_toChain != selfChainId, "only other chain");
        require(IERC20(_token).balanceOf(msg.sender) >= _amount, "balance too low");

        if (checkMintable(_token)) {
            IMAPToken(_token).burnFrom(msg.sender, _amount);
        } else {
            TransferHelper.safeTransferFrom(_token, msg.sender, address(this), _amount);
        }
        bytes32 orderId = getOrderID(_token, msg.sender, _to, _amount, _toChain);
        emit mapTransferOut(Utils.toBytes(_token), Utils.toBytes(msg.sender), orderId, selfChainId, _toChain, _to, _amount, Utils.toBytes(address(0)));
    }


    function transferOutNative(bytes memory _to, uint _toChain)
    external override payable
    whenNotPaused
    checkBridgeable(wToken, _toChain) {
        require(_toChain != selfChainId, "only other chain");
        uint amount = msg.value;
        require(amount > 0, "balance is zero");
        IWToken(wToken).deposit{value : amount}();

        bytes32 orderId = getOrderID(wToken, msg.sender, _to, amount, _toChain);

        emit mapTransferOut(Utils.toBytes(wToken), Utils.toBytes(msg.sender), orderId, selfChainId, _toChain, _to, amount, Utils.toBytes(address(0)));
    }


    function depositOutToken(address _token, address _from, address _to, uint _amount)
    external override payable
    whenNotPaused
    checkBridgeable(_token, relayChainId){
        require(msg.sender == _from, "only from sender");
        //require(IERC20(token).balanceOf(_from) >= _amount, "balance too low");

        TransferHelper.safeTransferFrom(_token, _from, address(this), _amount);
        bytes32 orderId = getOrderID(_token, _from, Utils.toBytes(_to), _amount, relayChainId);
        emit mapDepositOut(_token, Utils.toBytes(_from), orderId, _to, _amount);
    }

    function depositOutNative(address _from, address _to)
    external override payable
    whenNotPaused
    checkBridgeable(wToken, relayChainId) {
        require(msg.sender == _from, "only from sender");
        uint amount = msg.value;
        bytes32 orderId = getOrderID(wToken, _from, Utils.toBytes(_to), amount, relayChainId);

        IWToken(wToken).deposit{value : amount}();
        emit mapDepositOut(wToken, Utils.toBytes(_from), orderId, _to, amount);
    }

    function _transferIn(address _token, bytes memory _from, address payable _to, uint _amount, bytes32 _orderId, uint _fromChain, uint _toChain)
    internal checkOrder(_orderId) {
        if (_token == wToken) {
            TransferHelper.safeWithdraw(wToken, _amount);
            TransferHelper.safeTransferETH(_to, _amount);
        } else if (checkMintable(_token)) {
            IMAPToken(_token).mint(_to, _amount);
        } else {
            TransferHelper.safeTransfer(_token, _to, _amount);
        }
        emit mapTransferIn(_token, _from, _orderId, _fromChain, _toChain, _to, _amount);
    }


    function emergencyWithdraw(address _token, address payable _receiver, uint256 _amount) public onlyOwner {
        if (_token == wToken) {
            TransferHelper.safeWithdraw(wToken, _amount);
            TransferHelper.safeTransferETH(_receiver, _amount);
        } else {
            IERC20(_token).transfer(_receiver, _amount);
        }
    }


    /** UUPS *********************************************************/
    function _authorizeUpgrade(address)
    internal
    view
    override {
        require(msg.sender == _getAdmin(), "LightNode: only Admin can upgrade");
    }

    function changeAdmin(address _admin) public onlyOwner checkAddress(_admin){
        _changeAdmin(_admin);
    }

    function getAdmin() external view returns (address) {
        return _getAdmin();
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

}