// SPDX-License-Identifier: Open Source

pragma solidity ^0.8.25;

contract OperatorManager {
    address public operator;
    address public manager;

    constructor(address _operator, address _manager) {
        operator = _operator;
        manager = _manager;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "!auth");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager || msg.sender == operator, "!auth");
        _;
    }

    function changeOperator(address newOperator) external onlyOperator {
        operator = newOperator;
    }

    function changeManager(address newManager) external onlyOperator {
        manager = newManager;
    }

}
