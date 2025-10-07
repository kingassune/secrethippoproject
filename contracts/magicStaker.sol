// SPDX-License-Identifier: Open Source

/*
    This is not audited. 
    This is not tested very well.
    You should personally audit and test this code before using it.

    Voting power is not 1:1 with Resupply. 
    It can drop below if other users dilute with small amounts. 
    Or can rise above if other users are delayed after a large deposit.
    Will probably mostly be above 1:1 from non-voters contributing to overall score.

    Requires local quorum of 20% of total supply to forward vote to Resupply.

    significantly increasing your deposit incurs a 1 epoch delay before voting.
    This is to save on gas and not track account checkpoints, while maintaining a level 
    of safety and regard towards Resupply governance alignment
*/
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface Staker {
    function stake(uint _amount) external returns (uint);
    function cooldown(address _account, uint _amount) external returns (uint);
    function unstake(address _account, address _receiver) external returns (uint);
    function getReward(address _account) external;
    function cooldownEpochs() external returns (uint);
}

interface Strategy {
    function setUserBalance(address _account, uint256 _balance) external;
    function balanceOf(address _account) external returns (uint256);
    function totalSupply() external returns (uint256);
    function notifyReward(uint256 _amount) external;
}

interface Harvester {
    function process(address[] memory _tokenIn, uint256[] memory _amountsIn, address _strategy) external returns (uint256);
}

interface Voter {
    function voteForProposal(address account, uint256 id, uint256 pctYes, uint256 pctNo) external;
}

contract magicStaker {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------
    // CONSTANTS
    // ------------------------------------------------------------------------
    uint256 public constant DENOM = 10000000;
    uint256 public constant MAX_CALL_FEE = 50000;  // 0.5 %
    uint256 public constant MAX_MAGIC_FEE = 10000; // 0.1 %
    uint256 public constant MAX_PCT = 10000;

    // ------------------------------------------------------------------------
    // ROLES / MANAGEMENT
    // ------------------------------------------------------------------------
    address public emergencyOperator;
    address public manager;

    // ------------------------------------------------------------------------
    // FEES (mutable)
    // ------------------------------------------------------------------------
    uint256 public CALL_FEE = 5000;  // 0.05 %
    uint256 public MAGIC_FEE = 2500; // 0.025 %

    // ------------------------------------------------------------------------
    // EXTERNAL CONTRACTS / TOKENS
    // ------------------------------------------------------------------------
    Staker public immutable staker = Staker(0x22222222E9fE38F6f1FC8C61b25228adB4D8B953);
    IERC20 public immutable rsup = IERC20(0x419905009e4656fdC02418C7Df35B1E61Ed5F726);
    Voter public voter = Voter(0x11111111063874cE8dC6232cb5C1C849359476E6);

    // ------------------------------------------------------------------------
    // REWARD TOKEN MANAGEMENT
    // ------------------------------------------------------------------------
    IERC20[] public rewards;
    mapping(address => bool) public isRewardToken;

    function rewardsLength() public view returns (uint256) {
        return rewards.length;
    }

    // ------------------------------------------------------------------------
    // STAKING / ACCOUNT BALANCES
    // ------------------------------------------------------------------------
    // totalSupply should include magicSupply for correct strategy weighting
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    // cooldown tracking
    mapping(address => uint256) public cooldownOf;
    mapping(address => uint256) public accountCooldownEpoch;
    uint256 public pendingCooldownEpoch = type(uint256).max;

    // magic (strategy 0) tracking
    uint256 public magicSupply; // redeemable balance of magic pounder strategy
    mapping(address => uint256) public magicBalanceOf;

    // strategy indexing & account weights
    address[] public strategies;
    mapping(address => uint256[]) public accountStrategyWeight;
    mapping(address => uint256) public accountWeightEpoch;

    // helpers for strategies
    mapping(address => address) public strategyHarvester;

    // ------------------------------------------------------------------------
    // VOTING
    // ------------------------------------------------------------------------
    mapping(address => uint256) public accountVoteEpoch;
    address public magicVoter;

    // ------------------------------------------------------------------------
    // IMMUTABLE/UTILITY: epoch function
    // ------------------------------------------------------------------------
    /**
     * @notice Current Resupply epoch
     */
    function getEpoch() public view returns (uint256 epoch) {
        return (block.timestamp - 1741824000) / 604800;
    }

    // ------------------------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------------------------
    constructor(address _magicPounder, address _magicVoter) {
        // pre-approve staker
        rsup.approve(address(staker), type(uint256).max);

        // set initial manager/emergencyOperator
        emergencyOperator = msg.sender;
        manager = msg.sender;
        magicVoter = _magicVoter;

        // strategy 0 is immutable magic compounder
        strategies.push(_magicPounder);

        // add reusd to rewards
        rewards.push(IERC20(0x57aB1E0003F623289CD798B1824Be09a793e4Bec));
        isRewardToken[0x57aB1E0003F623289CD798B1824Be09a793e4Bec] = true;
    }

    // ------------------------------------------------------------------------
    // MODIFIERS
    // ------------------------------------------------------------------------
    modifier eOp() {
        require(msg.sender == emergencyOperator, "!Operator");
        _;
    }

    modifier managed() {
        require(msg.sender == manager, "!manager");
        _;
    }

    // ------------------------------------------------------------------------
    // STRATEGY / VIEW HELPERS
    // ------------------------------------------------------------------------
    /**
     * @notice Active strategies only. Possible for order to change after index 0
     */
    function strategiesLength() public view returns (uint256) {
        return strategies.length;
    }

    function strategySupply(address _strategy) public returns (uint256) {
        uint256 supply = Strategy(_strategy).totalSupply();
        // if magic strategy, include magic balance in supply
        if (_strategy == strategies[0]) {
            supply += magicSupply;
        }
        return supply;
    }

    function strategyBalanceOf(address _strategy, address _account) public returns (uint256) {
        return Strategy(_strategy).balanceOf(_account);
    }

    function unclaimedMagicTokens(address _account) public returns (uint256) {
        uint256 userMagic = magicBalanceOf[_account];
        if (userMagic > 0) {
            uint256 currentMagicBalance = Strategy(strategies[0]).balanceOf(_account);
            if (currentMagicBalance > userMagic) {
                uint256 diff = ((currentMagicBalance - userMagic) * MAGIC_FEE) / DENOM;
                return diff;
            }
        }
        return 0;
    }

    // ------------------------------------------------------------------------
    // VOTING POWER
    // ------------------------------------------------------------------------
    /**
     * @notice Meta voting power of user
     * @dev Will appear as 0 if user is delayed for safety
     */
    function getVotingPower(address _account) public view returns (uint256) {
        if (accountVoteEpoch[_account] > getEpoch()) {
            return 0;
        }
        return balanceOf[_account];
    }

    // ------------------------------------------------------------------------
    // USER WEIGHTING
    // ------------------------------------------------------------------------
    /**
     * @notice Claim any magic pounder share difference and sync strategy balances
     * @dev Unclaimed shares earn compounder yield and do not contribute to other strategies
     */
    function claimAndSync() external {
        require(magicBalanceOf[msg.sender] > 0, "0");
        // claim any magic pounder share difference
        _syncMagicBalance(msg.sender);
        // change user strategy balances to reflect any yield
        _syncAccount(msg.sender);
    }

    function setWeights(uint256[] memory _weights) public {
        // can only change weights once per epoch to avoid front-running harvests
        require(accountWeightEpoch[msg.sender] < getEpoch(), "!epoch");
        require(strategies.length == _weights.length, "!length");

        uint256 weightTotal;
        for (uint256 i = 0; i < strategies.length; ++i) {
            weightTotal += _weights[i];
            accountStrategyWeight[msg.sender][i] = _weights[i];
        }

        // Verify user has correct total weight
        require(weightTotal == DENOM, "!totalWeight");

        _syncMagicBalance(msg.sender);
        _syncAccount(msg.sender);

        accountWeightEpoch[msg.sender] = getEpoch();
    }

    // -------------------------
    // INTERNAL WEIGHTING HELPERS
    // -------------------------
    /* set all user strategy balances according to balance and weights
       balances are set on psuedo-staking contracts */
    function _syncAccount(address _account) internal {
        uint256 slen = strategies.length;
        uint256 assignedBalance;
        uint256 assignedWeight;

        for (uint256 i = 0; i < slen; ++i) {
            uint256 weight = accountStrategyWeight[_account][i];

            if (assignedWeight + weight == DENOM) {
                // last strategy, assign all remaining balance to avoid rounding issues
                uint256 amount = balanceOf[_account] - assignedBalance;
                _setUserStrategyBalance(strategies[i], _account, amount);
                /* if this return is removed in order to run additional logic,
                   you must add assigned balance and weight to avoid 0 weight
                   strategies being assigned a balance (DENOM+0==DENOM) */
                return;
            } else {
                uint256 amount = (balanceOf[_account] * weight) / DENOM;
                _setUserStrategyBalance(strategies[i], _account, amount);
                assignedBalance += amount;
                assignedWeight += weight;
            }
        }

        // fail if reaching this point (unexpected behavior)
        require(false, "!weight");
    }

    // checks starting balance first to avoid unneeded write calls
    function _setUserStrategyBalance(address _strategy, address _account, uint256 _amount) internal {
        Strategy strategy = Strategy(_strategy);
        if (strategy.balanceOf(_account) == _amount) {
            return;
        } else {
            strategy.setUserBalance(_account, _amount);
            if (_strategy == strategies[0]) {
                magicBalanceOf[_account] = Strategy(_strategy).balanceOf(msg.sender);
            }
        }
    }

    function _syncMagicBalance(address _account) internal {
        // if user has unclaimed magic balance, adjust
        uint256 userMagic = magicBalanceOf[_account];
        if (userMagic > 0) {
            uint256 currentMagicBalance = Strategy(strategies[0]).balanceOf(_account);
            if (currentMagicBalance > userMagic) {
                uint256 diff = ((currentMagicBalance - userMagic) * MAGIC_FEE) / DENOM;
                if (diff > 0) {
                    balanceOf[_account] += diff;
                    magicSupply -= diff;
                    magicBalanceOf[_account] = currentMagicBalance;
                }
            }
        }
    }

    // ------------------------------------------------------------------------
    // USER STAKE FUNCTIONS
    // ------------------------------------------------------------------------
    /**
     * @notice Stake RSUP
     * @dev Voting ability may be delayed by 1 epoch if significantly increasing stake
     * @param _amount Amount of RSUP to stake
     */
    function stake(uint256 _amount) external {
        require(_amount > 0, "0");
        // Make sure weights are set first, for account syncing
        require(accountWeightEpoch[msg.sender] != 0, "!weights");

        /* If user significantly increases stake, delay voting power by 1 epoch
           1. if user is increasing personal stake by more than 50%
           2. if user is increasing total supply by more than 5% */
        if (_amount * 2 > balanceOf[msg.sender] || (totalSupply * 500000) / DENOM < _amount) {
            accountVoteEpoch[msg.sender] = getEpoch() + 1;
        }

        rsup.safeTransferFrom(msg.sender, address(this), _amount);
        staker.stake(_amount); // only stake the requested amount, since contract may contain cooldown RSUP
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
        _syncMagicBalance(msg.sender);
        // change user strategy balances to reflect additional stake
        _syncAccount(msg.sender);
    }

    /**
     * @notice Enter cooldown for RSUP unstake
     * @dev Can only be performed every (cooldownEpochs + 1) epochs
     * @param _amount Amount of RSUP to cooldown
     */
    function cooldown(uint256 _amount) external {
        uint256 cde = staker.cooldownEpochs();
        uint256 epoch = getEpoch();

        /* verify it is an eligible cooldown epoch
           this can change if staker changes cooldownEpochs
           will always be set to 1 epoch greater than staker cooldownEpochs
           Example: cooldown is 2 weeks, can only initiate cooldowns during every 3rd week */
        require(epoch % (cde + 1) == 0, "!epoch");

        require(_amount > 0, "0");
        // psuedo-claim any magic pounder share difference
        _syncMagicBalance(msg.sender);
        require(_amount <= balanceOf[msg.sender], "!balance");

        /* check if user has previous matured cooldowns
           there is a rare edge case where if underyling staker increases cooldownEpochs,
           and new cooldowns are inititated by other users before the first cooldown period is reached,
           a user's cooldown may be locked until the new cooldown epoch is reached
           theoretical total cooldown length: original cooldownEpoch + new cooldownEpoch - 1 */
        if (cooldownOf[msg.sender] > 0 && accountCooldownEpoch[msg.sender] <= epoch) {
            _unstake(msg.sender);
        }

        // check if existing matured community cooldowns need unstaked first
        if (pendingCooldownEpoch <= epoch) {
            _rsupUnstake();
            pendingCooldownEpoch = epoch + cde + 1;
        } else if (pendingCooldownEpoch != epoch + cde + 1) {
            // If pendingCooldownEpoch is out of sync with cooldownEpochs, correct
            pendingCooldownEpoch = epoch + cde + 1;
        }

        // Remove from balances, supply
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;

        // Add to user cooldown balance
        cooldownOf[msg.sender] += _amount;

        // Set user cooldown maturity epoch
        accountCooldownEpoch[msg.sender] = pendingCooldownEpoch;

        // change user strategy balances to reflect decreased balance
        _syncAccount(msg.sender);
    }

    /**
     * @notice Unstake matured cooldown RSUP
     * @dev Must wait for full cooldownEpochs to pass before unstaking
     */
    function unstake() public {
        require(cooldownOf[msg.sender] > 0, "0");
        require(accountCooldownEpoch[msg.sender] <= getEpoch(), "!epoch");
        _unstake(msg.sender);
    }

    // ------------------------------------------------------------------------
    // INTERNAL STAKE HELPERS
    // ------------------------------------------------------------------------
    function _unstake(address _account) internal {
        if (pendingCooldownEpoch <= getEpoch()) {
            _rsupUnstake();
            pendingCooldownEpoch = type(uint256).max;
        }
        uint256 amount = cooldownOf[_account];
        cooldownOf[_account] = 0;
        rsup.safeTransfer(_account, amount);
    }

    function _rsupUnstake() internal {
        uint256 amount = staker.unstake(address(this), address(this));
        require(amount > 0, "0");
    }

    // ------------------------------------------------------------------------
    // REWARDS HARVESTING
    // ------------------------------------------------------------------------
    /**
     * @notice Harvest rewards
     * @dev Rewards are divided among strategies.
     */
    function harvest() external {
        // before claiming, check if RSUP is a reward token
        // It's not likely to ever become a reward token, but if it were to be added, it could interfere
        // with cooldown balances sitting in this contract.
        uint256 rsupBal;
        if (isRewardToken[address(rsup)]) {
            rsupBal = rsup.balanceOf(address(this));
        }

        // claim all rewards from staker
        staker.getReward(address(this));

        address[] memory positiveRewards;
        uint256[] memory rewardBals;

        // give caller their cut of all rewards
        for (uint256 r = 0; r < rewards.length; ++r) {
            uint256 rewardBal = rewards[r].balanceOf(address(this));
            // if RSUP token, subtract any balance that was already here
            if (address(rewards[r]) == address(rsup)) {
                rewardBal -= rsupBal;
            }
            // if no rewards, skip
            if (rewardBal == 0) {
                continue;
            }
            // give caller their cut
            uint256 callerFee = (rewardBal * CALL_FEE) / DENOM;
            rewards[r].safeTransfer(msg.sender, callerFee);
            positiveRewards[positiveRewards.length] = address(rewards[r]);
            rewardBals[rewardBals.length] = rewardBal - callerFee;
        }

        // distribute rewards to strategies based on their assigned balance
        for (uint256 i = 0; i < strategies.length; ++i) {
            address strategy = strategies[i];
            uint256 stratSupply = strategySupply(strategy);
            if (stratSupply == 0) {
                continue;
            }
            require(strategyHarvester[strategy] != address(0), "!harvester");
            uint256[] memory stratShares = new uint256[](rewardBals.length);
            for (uint256 r = 0; r < rewardBals.length; ++r) {
                stratShares[r] = (rewardBals[r] * stratSupply) / totalSupply;
            }
            // process rewards for strategy
            uint256 tokenOutBal = Harvester(strategyHarvester[strategy]).process(positiveRewards, stratShares, strategy);
            // notify strategy of reward
            Strategy(strategy).notifyReward(tokenOutBal);
        }
    }

    // ------------------------------------------------------------------------
    // MAGIC FUNCTIONS
    // ------------------------------------------------------------------------
    function magicStake(uint256 _amount) external {
        require(msg.sender == strategies[0], "!magic");
        rsup.safeTransferFrom(strategies[0], address(this), _amount);
        staker.stake(_amount);
        magicSupply += _amount;
    }

    function castVote(uint256 id, uint256 totalYes, uint256 totalNo) external {
        require(msg.sender == magicVoter, "!voter");
        uint256 total = totalYes + totalNo;
        require((totalSupply * 2000) / MAX_PCT < total, "!quorum"); // at least 20% of total supply must vote
        uint256 weightYes = (totalYes * MAX_PCT) / total;
        uint256 weightNo = (totalNo * MAX_PCT) / total;
        // in case rounding issue. Rounding should favor being below MAX_PCT if possible
        if (weightYes + weightNo == MAX_PCT - 1) {
            ++weightYes;
        }
        require(weightYes + weightNo == MAX_PCT, "!total");
        voter.voteForProposal(address(this), id, weightYes, weightNo);
    }

    // ------------------------------------------------------------------------
    // MANAGER FUNCTIONS
    // ------------------------------------------------------------------------
    // Add strategy
    function addStrategy(address _strategy) external {
        // Strategy must allow this contract to set user balances
        // Ensuring functionality/safety of strategy is outside of this scope
        // But this function is essential to THIS contract not breaking

        Strategy strategy = Strategy(_strategy);

        // Verify adding balance
        strategy.setUserBalance(address(1234), DENOM);
        require(strategy.balanceOf(address(1234)) == DENOM, "!balance1");
        require(strategy.totalSupply() == DENOM, "!supply1");

        // Verify removing balance
        strategy.setUserBalance(address(1234), 0);
        require(strategy.balanceOf(address(1234)) == 0, "!balance0");
        require(strategy.totalSupply() == 0, "!supply0");

        strategies.push(_strategy);
    }

    // Add reward token
    function addRewardToken(address _rewardToken) external managed {
        require(!isRewardToken[_rewardToken], "!exists");
        isRewardToken[_rewardToken] = true;
        rewards.push(IERC20(_rewardToken));
    }

    // Remove reward token
    function removeRewardToken(uint256 _rewardIndex, address _rewardToken) external managed {
        require(address(rewards[_rewardIndex]) == _rewardToken, "!mismatchId");
        isRewardToken[_rewardToken] = false;
        // replace index with last index
        rewards[_rewardIndex] = rewards[rewards.length - 1];
        rewards.pop();
    }

    // Set strategy harvester
    function setStrategyHarvester(address _strategy, address _harvester) external managed {
        strategyHarvester[_strategy] = _harvester;
    }

    // set call fee
    function setCallFee(uint256 _fee) external managed {
        require(_fee <= MAX_CALL_FEE, "!max");
        CALL_FEE = _fee;
    }

    // set magic fee
    function setMagicFee(uint256 _fee) external managed {
        require(_fee <= MAX_MAGIC_FEE, "!max");
        MAGIC_FEE = _fee;
    }

    // ------------------------------------------------------------------------
    // EMERGENCY FUNCTIONS
    // ------------------------------------------------------------------------
    // Transfer manager
    function setManager(address _newManager) external eOp {
        manager = _newManager;
    }

    // Transfer emergency powers
    function setEmergencyOperator(address _newOperator) external eOp {
        emergencyOperator = _newOperator;
    }

    // Emergency executable function
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external eOp returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        return (success, result);
    }
}