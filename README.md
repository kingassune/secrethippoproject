# SecretHippoProject

Drafts. Not fully tested. Not audited.

2nd layer Stake RSUP

Can support multiple strategies, with initial two planned for compounding RSUP, and for sreusd (as opposed to current reUSD only)

Non-transferable / Not a token. Staker dictates balances of strategies.

### To do

- Create tests for multiple harvests, claims, weight adjustments, etc., to confirm continuity

- Create tests for voting:
    - Creating proposal
    - Voting in proposal
    - Voting after castable time, without meeting quorum
    - Voting after castable time, with meeting quorum
    - Not being able to vote after significant weight increase

- Peer review / Audit

- UI

### Protections in place:

Since voting power is not tracked 1:1 with Resupply, significantly increasing ones stake incurs a vote delay.

Requires a local quorum of 20% in order to commit vote to Resupply

Since there may be small rounding issues from staker dictating strategy balances, weights can only be changed once per epoch.

Since compounder is capable of creating rounding errors on staker's side, a very small fee is applied when yield is synced with balance.