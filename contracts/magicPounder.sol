// SPDX-License-Identifier: Open Source

/*
    This is not audited. 
    This is not tested. 
    You should personally audit and test this code before using it.

    Must incorporate

    function processRewards() external;
*/ 

pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface Harvester {
    function process(address _tokenIn, address _tokenOut) external returns (uint256);
}

interface MagicStaker {
    function magicStake(uint256 _amount) external;
}

contract magicPounder {
    using SafeERC20 for IERC20;
    address public manager;
    address public immutable magicStaker;
    address public constant desiredToken = 0x419905009e4656fdC02418C7Df35B1E61Ed5F726;
    uint256 public totalSupply;
    uint256 public underlyingTotalSupply;
    // user shares - balanceOf is reserved for underlying balance for magicStaker interoperability
    mapping(address account => uint256) public sharesOf;

    constructor (address _magicStaker) {
        magicStaker = _magicStaker;
        IERC20(desiredToken).approve(magicStaker, type(uint256).max);
        manager = msg.sender;
    }

    modifier onlyMagicStaker {
        require(msg.sender == magicStaker, "!auth");
        _;
    }
    modifier managed() {
        require(msg.sender == manager, "!manager");
        _;
    }

    function balanceOf(address user) public view returns (uint256 amount) {
        require(totalSupply > 0, "No users");
        return ((sharesOf[user] * underlyingTotalSupply) / totalSupply);
    }
    
    function underlyingToShares(uint256 _amount) public view returns (uint256) {
        if(totalSupply == 0) {
            return _amount;
        }
        require(_amount * totalSupply >= underlyingTotalSupply, "!small");
        return (_amount * totalSupply) / underlyingTotalSupply;
    }

    function setUserBalance(address _account, uint256 _balance) external onlyMagicStaker {
        uint256 userBalance = balanceOf(_account);
        if(_balance == 0) {
            underlyingTotalSupply -= userBalance;
            totalSupply -= sharesOf[_account];
            sharesOf[_account] = 0;
            return;
        }
        if(_balance < userBalance) {
            uint256 diff = userBalance - _balance;
            uint256 removeShares = underlyingToShares(diff);
            sharesOf[_account] -= removeShares;
            totalSupply -= removeShares;
            underlyingTotalSupply -= diff;
            return;
        }
        if(_balance > userBalance) {
            uint256 diff = _balance - userBalance;
            uint256 addShares = underlyingToShares(diff);
            sharesOf[_account] += addShares;
            totalSupply += addShares;
            underlyingTotalSupply += diff;
            return;
        }
    }

    function notifyReward(uint256 _amount) external onlyMagicStaker {
        // magic stake RSUP
        MagicStaker(magicStaker).magicStake(_amount);
        underlyingTotalSupply += _amount;
    }

    // Transfer manager
    function setManager(address _newManager) external managed {
        manager = _newManager;
    }
}