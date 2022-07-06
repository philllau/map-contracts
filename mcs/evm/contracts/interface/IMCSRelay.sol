// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMCSRelay {
    function transferIn(uint fromChain, bytes memory receiptProof) external;
    function transferOut(address toContract, uint toChain, bytes memory data) external;
    function transferOutToken(address token, bytes memory to, uint amount, uint toChain) external;
    function transferOutNative(bytes memory to, uint toChain) external payable;
    function depositIn(address token, address from, address payable to, uint amount, bytes32 orderId, uint fromChain) external payable;
}