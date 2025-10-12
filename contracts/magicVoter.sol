// SPDX-License-Identifier: Open Source

/*
    This is not audited. 
    This is not tested. 
    You should personally audit and test this code before using it.
*/

pragma solidity ^0.8.25;

import { OperatorManager } from "./operatorManager.sol";

interface Voter {
    struct Vote {
        uint40 weightYes;
        uint40 weightNo;
    }
    
    function proposalData(uint256 id) external returns (
        uint16 epoch,
        uint32 createdAt,
        uint40 quorumWeight,
        bool processed,
        Vote memory results
    );
    function votingPeriod() external returns(uint256);
}

interface MagicStaker {
    function getVotingPower(address _account) external view returns (uint256);
    function castVote(uint256 id, uint256 totalYes, uint256 totalNo) external;
}

contract magicVoter is OperatorManager {
    uint256 public constant MAX_PCT = 10000;
    uint256 public constant EXECUTE_AFTER = 4 days;

    Voter public voter = Voter(0x11111111063874cE8dC6232cb5C1C849359476E6);
    MagicStaker public magicStaker;

    struct VoteTotals {
        uint256 yes;
        uint256 no;
    }

    struct UserVote {
        uint256 yes;
        uint256 no;
    }

    mapping(address => mapping(uint256 => UserVote)) public votes; // user => proposalId => userVote
    mapping(uint256 => VoteTotals) public voteTotals; // proposalId => VoteTotals
    mapping(uint256 => bool) public executed; // proposalId => executed

    constructor(address _operator, address _manager) OperatorManager(_operator, _manager) {}


    function canVote(uint256 id) public returns(bool _canVote, uint32 _createdAt) {

        require(!executed[id], "Executed");

        (   uint16 epoch,
            uint32 createdAt,
            uint40 quorumWeight,
            bool processed,
            Voter.Vote memory results ) = voter.proposalData(id);

        epoch; quorumWeight; results; // IDE suppressor, should be removed from production

        uint256 period = voter.votingPeriod();
        _createdAt = createdAt;
        if(_createdAt + period > block.timestamp && !processed) {
            _canVote = true;
        } else {
            _canVote = false;
        }
    }

    function vote(uint256 id, uint256 pctYes, uint256 pctNo) external {
        require(pctYes + pctNo == MAX_PCT, "!total");
        (bool _canVote, uint32 _createdAt) = canVote(id);
        require(_canVote, "!ended");

        uint256 votingPower = magicStaker.getVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");

        UserVote memory userVote = votes[msg.sender][id];
        require(userVote.yes + userVote.no == 0, "Already voted");


        uint256 weightYes = (votingPower * pctYes) / MAX_PCT;
        uint256 weightNo = (votingPower * pctNo) / MAX_PCT;
        

        userVote.yes = weightYes;
        userVote.no = weightNo;
        votes[msg.sender][id] = userVote;

        VoteTotals memory totals = voteTotals[id];
        totals.yes += weightYes;
        totals.no += weightNo;

        // if voting delay period over, cast vote automatically
        if(_createdAt + EXECUTE_AFTER < block.timestamp) {
            try magicStaker.castVote(id, totals.yes, totals.no) {
                // Vote cast
                executed[id] = true;
            } catch {
                // May fail if quorum not met. This is okay. Leave open for other voters.
            }
        }
    }

    function commitVote(uint256 id) external {
        (bool _canVote, uint32 _createdAt) = canVote(id);
        require(!_canVote, "!ended");
        require(_createdAt + EXECUTE_AFTER < block.timestamp, "!time");
        VoteTotals storage totals = voteTotals[id];
        magicStaker.castVote(id, totals.yes, totals.no);
    }

    // doesn't need to be immutable since this contract does not handle balances
    function setMagicStaker(address _magicStaker) external onlyOperator {
        magicStaker = MagicStaker(_magicStaker);
    }

}
