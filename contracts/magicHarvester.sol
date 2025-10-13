// SPDX-License-Identifier: Open Source

/*
    This is not audited. 
    This is not tested. 
    You should personally audit and test this code before using it.

    Must incorporate

    process(rewards[r], desiredToken) external;

    practice route:
    tokenIn = reUSD
    tokenOut = RSUP
        route[0] = { pool: 0xc522A6606BBA746d7960404F22a3DB936B6F4F50, tokenIn: reUSD, tokenOut: scrvUSD, functionType: 0 } // curve exchange
        route[1] = { pool: 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367, tokenIn: scrvUSD, tokenOut: crvUSD, functionType: 1 } // scrvUSD redeem
        route[2] = { pool: 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, tokenIn: crvUSD, tokenOut: WETH, functionType: 0 } // curve exchange
        route[3] = { pool: 0xEe351f12EAE8C2B8B9d1B9BFd3c5dd565234578d, tokenIn: WETH, tokenOut: RSUP, functionType: 0 } // curve exchange
*/ 

pragma solidity ^0.8.30;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { OperatorManager } from "./operatorManager.sol";

interface CurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy
    ) external payable returns (uint256);
}

interface AltCurvePool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 _dx,
        uint256 _min_dy
    ) external payable returns (uint256);
}

interface ScrvUSD {
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

interface SreUSD {
    function deposit(uint256 _assets, address _receiver) external;
    function redeem(uint256 _shares, address _receiver, address _owner) external;
}

interface Strategy {
    function desiredToken() external view returns (address);
}

contract magicHarvester is OperatorManager {
    using SafeERC20 for IERC20;

    struct Route {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 functionType;
        uint256 indexIn;
        uint256 indexOut;
    }

    mapping(address => mapping(address => Route[])) public routes; // tokenIn => tokenOut => route[]
    mapping(address => bool) public rewardCaller;

    constructor(address _operator, address _manager) OperatorManager(_operator, _manager) {}

    function addRewardCaller(address _caller) external onlyManager {
        rewardCaller[_caller] = true;
    }
    function removeRewardCaller(address _caller) external onlyManager {
        rewardCaller[_caller] = false;
    }

    function getRoute(address _tokenIn,  address _tokenOut) external view returns (Route[] memory) {
        return routes[_tokenIn][_tokenOut];
    }

    function setRoute(
        address _tokenIn,
        Route[] memory _routes,
        address _tokenOut,
        uint256 _testAmount,
        bool _removeApprovals
    ) external  {
        // can pass 0 routes to delete existing route, otherwise needs validation and test
        if(_routes.length > 0) {
            require(_routes[0].tokenIn == _tokenIn, "!start");
            require(_routes[_routes.length - 1].tokenOut == _tokenOut, "!end");
            require(_testAmount > 0, "!test");
        }

        if(_removeApprovals) {
            // remove token approvals for each step
            for (uint256 i = 0; i < routes[_tokenIn][_tokenOut].length; i++) {
                IERC20(routes[_tokenIn][_tokenOut][i].tokenIn).approve(routes[_tokenIn][_tokenOut][i].pool, 0);
            }
        }
        for (uint256 i = 0; i < _routes.length; i++) {
            if(i > 0) {
                // validate route continuity
                require(_routes[i-1].tokenOut == _routes[i].tokenIn, "!chain");
            }
            // approve token for curve pools
            if(_routes[i].functionType == 0) {
                IERC20(_routes[i].tokenIn).approve(_routes[i].pool, type(uint256).max);
            }
        }
        // overwrite routes
        routes[_tokenIn][_tokenOut] = _routes;
        
        if(_routes.length == 0) {
            return;
        }

        // test route
        _process(_tokenIn, _tokenOut, _testAmount);
        IERC20(_tokenOut).safeTransfer(msg.sender, IERC20(_tokenOut).balanceOf(address(this)));
    }

    function process(address[10] memory _tokensIn, uint256[10] memory _amountsIn, address _strategy) external returns (uint256 tokenOutBal) {
        require(rewardCaller[msg.sender], "!auth");
        address strategyToken = Strategy(_strategy).desiredToken();
        require(strategyToken != address(0), "!tokenOut");
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            if(_tokensIn[i] == address(0)) {
                break;
            }
            require(routes[_tokensIn[i]][strategyToken].length > 0, "!route");
            _process(_tokensIn[i], strategyToken, _amountsIn[i]);
        }
        // notify strategy of reward
        tokenOutBal = IERC20(strategyToken).balanceOf(address(this));
        require(tokenOutBal > 0, "!reward");
        IERC20(strategyToken).safeTransfer(_strategy, tokenOutBal);
    }

    function _process(address _tokenIn, address _tokenOut, uint256 _amountIn) internal {
        require(_amountIn > 0, "!amount");
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        for (uint256 i = 0; i < routes[_tokenIn][_tokenOut].length; i++) {
            Route memory route = routes[_tokenIn][_tokenOut][i];
            uint256 bal = IERC20(route.tokenIn).balanceOf(address(this));
            require(bal > 0, "!balance");
            if (route.functionType == 0) {
                // curve exchange
                IERC20(route.tokenIn).approve(route.pool, bal);
                CurvePool(route.pool).exchange{value: 0}(int128(int256(route.indexIn)), int128(int256(route.indexOut)), bal, 0);
            } else if (route.functionType == 1) {
                // scrvUSD redeem
                IERC20(route.tokenIn).approve(route.pool, bal);
                ScrvUSD(route.pool).redeem(bal, address(this), address(this));
            } else if (route.functionType == 2) {
                // alt curve exchange
                IERC20(route.tokenIn).approve(route.pool, bal);
                AltCurvePool(route.pool).exchange{value: 0}(route.indexIn, route.indexOut, bal, 0);
            } else if (route.functionType == 3) {
                // sreUSD exchange
                IERC20(route.tokenIn).approve(route.pool, bal);
                SreUSD(route.pool).deposit(bal, address(this));
            } else {
                revert("!function");
            }
            require(IERC20(route.tokenIn).balanceOf(address(this)) == 0, "!spent");
        }
    }
}