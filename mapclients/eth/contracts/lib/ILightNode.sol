// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILightNode {
    struct blockHeader {
        bytes parentHash;
        address coinbase;
        bytes root;
        bytes txHash;
        bytes receipHash;
        bytes bloom;
        uint256 number;
        uint256 gasLimit;
        uint256 gasUsed;
        uint256 time;
        istanbulExtra extraData;
        bytes mixDigest;
        bytes nonce;
        uint256 baseFee;
    }

    struct txProve{
        bytes keyIndex;
        bytes[] prove;
        bytes expectedValue;
    }

    struct txLogs{
        bytes PostStateOrStatus;
        uint CumulativeGasUsed;
        bytes Bloom;
        Log[] logs;
    }

    struct Log {
        address addr;
        bytes[] topics;
        bytes data;
    }

    struct istanbulAggregatedSeal {
        uint256 round;
        bytes signature;
        uint256 bitmap;
    }

    struct istanbulExtra {
        address[] validators;
        bytes seal;
        istanbulAggregatedSeal aggregatedSeal;
        istanbulAggregatedSeal parentAggregatedSeal;
        uint256 removeList;
        bytes[] addedPubKey;
    }

    struct proveData {
        blockHeader header;
        txLogs logs;
        txProve prove;
    }

    function proveVerify(proveData memory _proveData) external view returns (bool success, string memory message);

    function save(blockHeader memory bh,bytes memory bits, G2 memory aggPk) external;

    function init(G1 memory sig, uint round) external;
}