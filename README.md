# SecretHippoProject

Drafts. Not fully tested. Not audited.

2nd layer Stake RSUP

Can support multiple strategies, with initial two planned for compounding RSUP, and for sreusd (as opposed to current reUSD only)

Non-transferable / Not a token. Staker dictates balances of strategies.

### To do

- Peer review / Audit

- UI

### Protections in place:

Since voting power is not tracked 1:1 with Resupply, significantly increasing ones stake incurs a vote delay.

Requires a local quorum of 20% in order to commit vote to Resupply

Since there may be small rounding issues from staker dictating strategy balances, weights can only be changed once per epoch.