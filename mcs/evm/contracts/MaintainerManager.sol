// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./utils/Role.sol";

contract MaintainerManager is Role {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many MAP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 lastRewardBlock;  // Last block number that MAP distribution occurs.
        uint256 accMapsPerShare; // Accumulated MAPs per share, times 1e23. See below.
        uint256 allStake;
    }


    // Info of each pool.
    PoolInfo public pool;
    // Info of each user that stakes Maps tokens.
    mapping (address => UserInfo) public userInfo;
    // The block number when MAP mining starts.
    uint256 public startBlock;
    // The block number when MAP mining ends.
    uint256 public bonusEndBlock;
    //while list
    mapping(address =>bool) public whiteList;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event WhiteList(address indexed user, uint256 tag);

    constructor(
        uint256 _startBlock,
        uint256 _bonusEndBlock) {

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // staking pool
        pool = PoolInfo({
        lastRewardBlock: startBlock,
        accMapsPerShare: 0,
        allStake:0
        });
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accCakePerShare = pool.accMapsPerShare;
        if (block.number > pool.lastRewardBlock && pool.allStake != 0) {
            uint256 cakeReward = address(this).balance.sub(pool.allStake);
            accCakePerShare = accCakePerShare.add(cakeReward.mul(1e12).div(pool.allStake));
        }
        return user.amount.mul(accCakePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.allStake == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 cakeReward = address(this).balance.sub(pool.allStake);
        pool.accMapsPerShare = pool.accMapsPerShare.add(cakeReward.mul(1e12).div(pool.allStake));
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        updatePool();
    }


    function deposit() public payable {
        require(whiteList[msg.sender],"only whitelist");
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accMapsPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                payable(msg.sender).transfer(pending);
            }
        }
        if(msg.value > 0) {
            user.amount = user.amount.add(msg.value);
        }
        user.rewardDebt = user.amount.mul(pool.accMapsPerShare).div(1e12);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = user.amount.mul(pool.accMapsPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            payable(msg.sender).transfer(pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            payable(msg.sender).transfer(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMapsPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        payable(msg.sender).transfer(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) public onlyManager {
        require(_amount < address(this).balance.sub(pool.allStake), 'not enough token');
        payable(msg.sender).transfer(_amount);
    }

    function setBonusEndBlock(uint _block) external onlyManager{
        bonusEndBlock = _block;
    }

    function addWhiteList(address _address) external onlyManager{
        whiteList[_address] = true;
        emit WhiteList(_address,1);
    }

    function removeWhiteList(address _address) external onlyManager{
        whiteList[_address] = false;
        emit WhiteList(_address,0);
    }

}