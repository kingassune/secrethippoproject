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

pragma solidity ^0.8.30;

import { IERC20, SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { OperatorManager } from "./operatorManager.sol";

interface Registry {
    function getAddress(string memory key) external view returns (address);
}

interface Staker {
    function stake(uint _amount) external returns (uint);
    function cooldown(address _account, uint _amount) external returns (uint);
    function unstake(address _account, address _receiver) external returns (uint);
    function getReward(address _account) external;
    function cooldownEpochs() external view returns (uint);
}

interface Strategy {
    function setUserBalance(address _account, uint256 _balance) external;
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function notifyReward(uint256 _amount) external;
    function desiredToken() external view returns(address);
    function subtractFee(address _account, uint256 _fee) external;
}

interface Harvester {
    struct Route {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 functionType;
        uint256 indexIn;
        uint256 indexOut;
    }
    function process(address[10] memory _tokenIn, uint256[10] memory _amountsIn, address _strategy) external returns (uint256);
    function getRoute(address _tokenIn, address _tokenOut) external view returns (Route[] memory);
}

interface Voter {
    struct Action {
        address target;
        bytes data;
    }
    function voteForProposal(address account, uint256 id, uint256 pctYes, uint256 pctNo) external;
    function createNewProposal(address account, Action[] calldata payload, string calldata description) external returns (uint256);
    function setDelegateApproval(address _delegate, bool _isApproved) external;
    function minCreateProposalWeight() external view returns (uint256);
}

interface MagicVoter {
    function setResupplyVoter(address _voter) external;
}

contract magicStakerOld is OperatorManager {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------
    // CONSTANTS
    // ------------------------------------------------------------------------
    uint256 public constant DENOM = 10000000;
    uint256 public constant MAX_CALL_FEE = 50000;  // 0.5 %
    uint256 public constant MAX_PCT = 10000;
    Registry public constant registry = Registry(0x10101010E0C3171D894B71B3400668aF311e7D94);
    Staker public constant staker = Staker(0x22222222E9fE38F6f1FC8C61b25228adB4D8B953);
    IERC20 public constant rsup = IERC20(0x419905009e4656fdC02418C7Df35B1E61Ed5F726);

    // ------------------------------------------------------------------------
    // VARIABLES
    // ------------------------------------------------------------------------

    // Fees
    uint256 public CALL_FEE = 5000;  // 0.05 %

    // RSUP voting contract
    Voter public voter;

    // Rewards (only reUSD as of writing)
    IERC20[] public rewards;
    mapping(address => bool) public isRewardToken;

    // totalSupply
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    // cooldown tracking
    mapping(address => uint256) public cooldownOf;
    mapping(address => uint256) public accountCooldownEpoch;
    uint256 public pendingCooldownEpoch = type(uint256).max;

    // magic pounder (strategy 0) tracking
    mapping(address => uint256) public magicBalanceOf; // user's claimed pounder balance
        // use unclaimedMagicTokens(address _account) for unclaimed user balance

    // strategy indexing & account weights
    address[] public strategies;
    mapping(address => mapping(uint256 => uint256)) public accountStrategyWeight;
    mapping(address => uint256) public accountWeightEpoch;

    // Harvester to handle token swaps
    mapping(address strategy => address harvester) public strategyHarvester;

    // ------------------------------------------------------------------------
    // VOTING
    // ------------------------------------------------------------------------
    mapping(address => uint256) public accountVoteEpoch;
    address public magicVoter;


    // ------------------------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------------------------
    constructor(address _magicPounder, address _magicVoter, address _operator, address _manager) OperatorManager(_operator, _manager) {
        // pre-approve staker
        rsup.approve(address(staker), type(uint256).max);

        magicVoter = _magicVoter;

        // strategy 0 is immutable magic compounder
        strategies.push(_magicPounder);

        // add reusd to rewards
        rewards.push(IERC20(0x57aB1E0003F623289CD798B1824Be09a793e4Bec));
        isRewardToken[0x57aB1E0003F623289CD798B1824Be09a793e4Bec] = true;
        voter = Voter(registry.getAddress("VOTER"));
    }

    // ------------------------------------------------------------------------
    // EVENTS
    // ------------------------------------------------------------------------
    event Stake(address indexed user, uint256 amount);
    event Cooldown(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event Harvest(address indexed reward, uint256 amount);
    event SetWeights(address indexed user, uint256[] weights);
    event MagicClaim(address indexed user, uint256 amount);
    event VoteCast(uint256 proposalId, uint256 weightYes, uint256 weightNo);
    event MagicStake(uint256 amount);
    event NewRewardToken(address rewardToken);
    event RemoveRewardToken(address rewardToken);
    event StrategyHarvesterSet(address strategy, address harvester);
    event CallFeeSet(uint256 newFee);
    event MagicFeeSet(uint256 newFee);
    event StrategyAdded(address strategy);
    event MagicVoterSet(address voter);
    event ResupplyVoterSet(address voter);
    event DelegateApprovalSet(address delegate, bool isApproved);
    event Executed(address to, uint256 value, bytes data, bool success);

    // ------------------------------------------------------------------------
    // VIEWs
    // ------------------------------------------------------------------------
    
    function rewardsLength() public view returns (uint256) {
        return rewards.length;
    }

    /**
     * @notice Current Resupply epoch
     */
    function getEpoch() public view returns (uint256 epoch) {
        return (block.timestamp - 1741824000) / 604800;
    }

    function isCooldownEpoch() public view returns (bool) {
        uint256 cde = staker.cooldownEpochs();
        uint256 epoch = getEpoch();
        if(epoch % (cde + 1) == 0) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Active strategies only. Possible for order to change after index 0
     */
    function strategiesLength() public view returns (uint256) {
        return strategies.length;
    }

    function strategyBalanceOf(address _strategy, address _account) public view returns (uint256) {
        return Strategy(_strategy).balanceOf(_account);
    }

    function unclaimedMagicTokens(address _account) public view returns (uint256) {
        uint256 userMagic = magicBalanceOf[_account];
        uint256 currentMagicBalance = Strategy(strategies[0]).balanceOf(_account);
        if (currentMagicBalance > userMagic) {
            uint256 diff = currentMagicBalance - userMagic;
            return diff;
        }
        return 0;
    }

    // ------------------------------------------------------------------------
    // VOTING
    // ------------------------------------------------------------------------
    /**
     * @notice Meta voting power of user
     * @dev Will appear as 0 if user is delayed for safety
     */
    function getVotingPower(address _account) public view returns (uint256) {
        if (accountVoteEpoch[_account] > getEpoch()) {
            return 0;
        }
        return balanceOf[_account]+unclaimedMagicTokens(_account);
    }

    function createProposal(Voter.Action[] calldata payload, string calldata description) external returns (uint256) {
        // verify this contract has enough voting power to create proposal
        require(getVotingPower(msg.sender) >= voter.minCreateProposalWeight(), "!weight");
        return voter.createNewProposal(address(this), payload, description);
    }

    function castVote(uint256 id, uint256 totalYes, uint256 totalNo) external {
        require(msg.sender == magicVoter, "!voter");
        uint256 total = totalYes + totalNo;
        require((totalSupply * 2000) / MAX_PCT < total, "!quorum"); // at least 20% of total supply must vote
        uint256 weightYes = (totalYes * MAX_PCT) / total;
        uint256 weightNo = MAX_PCT - weightYes;
        voter.voteForProposal(address(this), id, weightYes, weightNo);
        emit VoteCast(id, weightYes, weightNo);
    }

    // ------------------------------------------------------------------------
    // USER WEIGHTING
    // ------------------------------------------------------------------------
    /**
     * @notice Claim any magic pounder share difference and sync strategy balances
     * @dev Unclaimed shares earn compounder yield and do not contribute to other strategies
     */
    function syncAccount() external {
        require(unclaimedMagicTokens(msg.sender) > 0, "0");
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
        emit SetWeights(msg.sender, _weights);
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
        uint256 accountBalance = balanceOf[_account];

        for (uint256 i = 0; i < slen; ++i) {
            uint256 weight = accountStrategyWeight[_account][i];
            if(weight == 0) {
                _setUserStrategyBalance(strategies[i], _account, 0);
            } else if(accountBalance == 0) {
                assignedWeight+=weight;
                _setUserStrategyBalance(strategies[i], _account, 0);
            } else if (assignedWeight + weight == DENOM) {
                // last strategy, assign all remaining balance to avoid rounding issues
                uint256 amount = accountBalance - assignedBalance;
                _setUserStrategyBalance(strategies[i], _account, amount);
                assignedBalance += amount;
                assignedWeight += weight;
            } else {
                uint256 amount = (accountBalance * weight) / DENOM;
                _setUserStrategyBalance(strategies[i], _account, amount);
                assignedBalance += amount;
                assignedWeight += weight;
            }
        }
        require(assignedBalance <= accountBalance, "!bal");
        require(assignedWeight == DENOM, "!weight");
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
        uint256 currentMagicBalance = Strategy(strategies[0]).balanceOf(_account);
        if (currentMagicBalance > userMagic) {
            uint256 diff = (currentMagicBalance - userMagic);
            if (diff > 0) {
                balanceOf[_account] += diff;
                magicBalanceOf[_account] = currentMagicBalance;
                emit MagicClaim(_account, diff);
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
        emit Stake(msg.sender, _amount);
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
        emit Cooldown(msg.sender, _amount);
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
        emit Unstake(_account, amount);
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

        address[10] memory positiveRewards;
        uint256[10] memory rewardBals;

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
            positiveRewards[r] = address(rewards[r]);
            rewardBals[r] = rewardBal - callerFee;
            emit Harvest(address(rewards[r]), rewardBals[r]);
        }

        // distribute rewards to strategies based on their assigned balance
        for (uint256 i = 0; i < strategies.length; ++i) {
            address strategy = strategies[i];
            uint256 stratSupply = Strategy(strategy).totalSupply();
            if (stratSupply == 0) {
                continue;
            }
            require(strategyHarvester[strategy] != address(0), "!harvester");
            uint256[10] memory stratShares;
            for (uint256 r = 0; r < rewards.length; ++r) {
                if(positiveRewards[r] == address(0)) {
                    continue;
                }
                if(i == strategies.length - 1) {
                    // last strategy, assign all remaining shares to avoid rounding issues
                    uint256 lastRewardBal = rewards[r].balanceOf(address(this));
                    if(positiveRewards[r] == address(rsup)) {
                        lastRewardBal -= rsupBal;
                    }
                    stratShares[r] = lastRewardBal;
                    continue;
                }
                stratShares[r] = (rewardBals[r] * stratSupply) / totalSupply;
            }
            // process rewards for strategy
            Harvester(strategyHarvester[strategy]).process(positiveRewards, stratShares, strategy);
        }
    }

    // ------------------------------------------------------------------------
    // MAGIC FUNCTIONS
    // ------------------------------------------------------------------------
    function magicStake(uint256 _amount) external {
        require(msg.sender == strategies[0], "!magic");
        rsup.safeTransferFrom(strategies[0], address(this), _amount);
        staker.stake(_amount);
        totalSupply += _amount;
        emit MagicStake(_amount);
    }

    // ------------------------------------------------------------------------
    // MANAGER FUNCTIONS
    // ------------------------------------------------------------------------

    // Add reward token
    function addRewardToken(address _rewardToken) external onlyManager {
        require(_rewardToken != address(0), "!zeroAddress");
        require(rewards.length < 10, "!maxRewards");
        require(!isRewardToken[_rewardToken], "!exists");
        isRewardToken[_rewardToken] = true;
        rewards.push(IERC20(_rewardToken));
        emit NewRewardToken(_rewardToken);
    }

    // Remove reward token
    function removeRewardToken(uint256 _rewardIndex, address _rewardToken) external onlyManager {
        require(address(rewards[_rewardIndex]) == _rewardToken, "!mismatchId");
        isRewardToken[_rewardToken] = false;
        // replace index with last index
        rewards[_rewardIndex] = rewards[rewards.length - 1];
        rewards.pop();
        emit RemoveRewardToken(_rewardToken);
    }

    // set call fee
    function setCallFee(uint256 _fee) external onlyManager {
        require(_fee <= MAX_CALL_FEE, "!max");
        CALL_FEE = _fee;
        emit CallFeeSet(_fee);
    }

    // ------------------------------------------------------------------------
    // Operator FUNCTIONS
    // ------------------------------------------------------------------------

    // Set strategy harvester
    function setStrategyHarvester(address _strategy, address _harvester, bool _keepOldApproval) external onlyOperator {
        // validate harvester has route for strategy desired token
        Harvester.Route[] memory routes = Harvester(_harvester).getRoute(address(rewards[0]), Strategy(_strategy).desiredToken());
        require(routes.length > 0, "!route");
        // since strategies can share harvester, make it a choice to revoke old permissions or not
        // this way, changing harvester for 1 strategy doesn't break another
        if(!_keepOldApproval) {
            address oldHarvester = strategyHarvester[_strategy];
            if(oldHarvester != address(0)) {
                for(uint256 i = 0; i<rewards.length; ++i) {
                    rewards[i].approve(oldHarvester, 0);
                }
            }
        }
        strategyHarvester[_strategy] = _harvester;
        for(uint256 i = 0; i<rewards.length; ++i) {
            rewards[i].approve(_harvester, type(uint256).max);
        }
        emit StrategyHarvesterSet(_strategy, _harvester);
    }

    // Add strategy
    function addStrategy(address _strategy) external onlyOperator {
        // Strategy must allow this contract to set user balances
        // Ensuring functionality/safety of strategy is outside of this scope
        // But this function is essential to THIS contract not breaking

        Strategy strategy = Strategy(_strategy);

        // Verify strategy has a desiredToken and that it is not RSUP
        address dt = strategy.desiredToken();
        require(dt != address(0) && dt != address(rsup), "!desiredToken");

        // Verify adding balance
        strategy.setUserBalance(address(1234), DENOM);
        require(strategy.balanceOf(address(1234)) == DENOM, "!balance1");
        require(strategy.totalSupply() == DENOM, "!supply1");

        // Verify removing balance
        strategy.setUserBalance(address(1234), 0);
        require(strategy.balanceOf(address(1234)) == 0, "!balance0");
        require(strategy.totalSupply() == 0, "!supply0");

        strategies.push(_strategy);
        emit StrategyAdded(_strategy);
    }

    // Set magic voter
    function setMagicVoter(address _magicVoter) external onlyOperator {
        magicVoter = _magicVoter;
        emit MagicVoterSet(_magicVoter);
    }

    // Set Resupply voter contract
    function setResupplyVoter() external onlyOperator {
        address _voter = registry.getAddress("VOTER");
        voter = Voter(_voter);
        MagicVoter(magicVoter).setResupplyVoter(_voter);
        emit ResupplyVoterSet(_voter);
    }

    // Set delegate approval for voter contract
    function setDelegateApproval(address _delegate, bool _isApproved) external onlyOperator {
        voter.setDelegateApproval(_delegate, _isApproved);
        emit DelegateApprovalSet(_delegate, _isApproved);
    }   

    // Fallback executable function
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool, bytes memory) {
        require(msg.sender == RESUPPLY_CORE, "!auth");
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        emit Executed(_to, _value, _data, success);
        return (success, result);
    }
}