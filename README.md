# SecretHippoProject

Very early drafts. Probably full of mistakes and incomplete code.

2nd layer Stake RSUP

Can support multiple strategies, with initial two planned for compounding RSUP, and for sreusd (as opposed to current reUSD only)

Non-transferable / Not a token. Staker dictates balances of strategies.

### Protections in place:

Since voting power is not tracked 1:1 with Resupply, significantly increasing ones stake incurs a vote delay.

Since there may be small rounding issues from staker dictating strategy balances, weights can only be changed once per epoch.

Since compounder is more likely to incur rounding issues, a very small fee is applied to claimed yield.