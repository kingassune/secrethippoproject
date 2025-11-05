// TO-DO: test excluded address cutoff

var { ethers } = require("hardhat");
var { expect } = require("chai");
var { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
var { setUpSmartContracts } = require("./fixtures");
const {
  impersonateAccount,
  setBalance,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Setup", function () {

    // contracts and address variables used in tests
    let MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings;
    let MagicPounderAddress, MagicVoterAddress, MagicStakerAddress, MagicHarvesterAddress, MagicSavingsAddress, manager, operator;
    let reUSD, RSUP, sreUSD, staker, voter;
    let reUSDAddress, RSUPAddress, sreUSDAddress, stakerAddress, voterAddress;
    let signers = {users:[]}
    let users = [
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0x0000000000000000000000000000000000000003",
        "0x0000000000000000000000000000000000000004",
        "0x0000000000000000000000000000000000000005",
        "0x0000000000000000000000000000000000000006",
        "0x0000000000000000000000000000000000000007",
        "0x0000000000000000000000000000000000000008",
        "0x0000000000000000000000000000000000000009",
    ];

    // Fund test accounts and get contract instances
    // setup signers for impersonated accounts
    before(async function () {
        // Load fixtures
        ({ MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings, manager, operator, reUSD, RSUP, sreUSD, staker, voter } = await loadFixture(setUpSmartContracts));
        
        // Get deployed contract addresses
        MagicPounderAddress = await MagicPounder.getAddress();
        MagicVoterAddress = await MagicVoter.getAddress();
        MagicStakerAddress = await MagicStaker.getAddress();
        MagicHarvesterAddress = await MagicHarvester.getAddress();
        MagicSavingsAddress = await MagicSavings.getAddress();
        reUSDAddress = await reUSD.getAddress();
        RSUPAddress = await RSUP.getAddress();
        sreUSDAddress = await sreUSD.getAddress();
        stakerAddress = await staker.getAddress();
        voterAddress = await voter.getAddress();

        // Impersonate and fund manager and operator accounts
        await impersonateAccount(manager);
        signers.manager = await ethers.getSigner(manager);
        await setBalance(manager, ethers.toBigInt("10000000000000000000"));

        await impersonateAccount(operator);
        signers.operator = await ethers.getSigner(operator);
        await setBalance(operator, ethers.toBigInt("10000000000000000000"));

        // Impersonate and fund reUSD and RSUP whales, distribute tokens to test users
        var reUSDwhale = "0xc522A6606BBA746d7960404F22a3DB936B6F4F50";
        await impersonateAccount(reUSDwhale);
        signers.reUSDwhale = await ethers.getSigner(reUSDwhale);
        await setBalance(reUSDwhale, ethers.toBigInt("10000000000000000000"));
        await reUSD.connect(signers.reUSDwhale).transfer(operator, 100000n*10n**18n);

        var RSUPwhale = "0x6666666677B06CB55EbF802BB12f8876360f919c";
        await impersonateAccount(RSUPwhale);
        signers.RSUPwhale = await ethers.getSigner(RSUPwhale);
        await setBalance(RSUPwhale, ethers.toBigInt("10000000000000000000"));

        for(var i in users) {
            await RSUP.connect(signers.RSUPwhale).transfer(users[i], 100000n*10n**18n);
            await impersonateAccount(users[i]);
            signers.users[i] = await ethers.getSigner(users[i]);
            await setBalance(users[i], ethers.toBigInt("10000000000000000000"));
        }
        await RSUP.connect(signers.RSUPwhale).transfer(users[8], 1000000n*10n**18n);

    });

    // hello world tests to verify deployments succeeded
    describe("Validate Deployment Values", () => {
        it("MagicPounder address check", async () => {
            expect(await MagicPounder.operator()).to.be.equal(operator);
            expect(await MagicPounder.manager()).to.be.equal(manager);
        });
        it("MagicVoter address check", async () => {
            expect(await MagicVoter.operator()).to.be.equal(operator);
            expect(await MagicVoter.manager()).to.be.equal(manager);
        });
        it("MagicStaker address check", async () => {
            expect(await MagicStaker.operator()).to.be.equal(operator);
            expect(await MagicStaker.manager()).to.be.equal(manager);
            expect(await MagicStaker.strategies(0)).to.be.equal(MagicPounderAddress);
            expect(await MagicStaker.magicVoter()).to.be.equal(MagicVoterAddress);
        });
        it("MagicSavings address check", async () => {
            expect(await MagicSavings.magicStaker()).to.be.equal(MagicStakerAddress);
        });
    });

    // Configuration of contracts
    describe("Initial Setup", () => {

        // Connecting staker and components
        it("Set MagicStaker in MagicPounder", async () => {
            await MagicPounder.connect(signers.operator).setMagicStaker(MagicStakerAddress);
            expect(await MagicPounder.magicStaker()).to.be.equal(MagicStakerAddress);
        });
        it("Set MagicStaker in MagicVoter", async () => {
            await MagicVoter.connect(signers.operator).setMagicStaker(MagicStakerAddress);
            expect(await MagicVoter.magicStaker()).to.be.equal(MagicStakerAddress);
        });
        it("Add MagicSavings strategy", async () => {
            expect(await MagicStaker.connect(signers.operator).addStrategy(MagicSavingsAddress)).to.be.not.reverted;
        });
        
        // Adding harvester
        it("Set MagicHarvester as Strategy 0 and Strategy 1 Harvester in MagicStaker", async () => {
            await MagicStaker.connect(signers.operator).setStrategyHarvester(MagicPounderAddress, MagicHarvesterAddress);
            expect(await MagicStaker.strategyHarvester(MagicPounderAddress)).to.be.equal(MagicHarvesterAddress);
            await MagicStaker.connect(signers.operator).setStrategyHarvester(MagicSavingsAddress, MagicHarvesterAddress);
            expect(await MagicStaker.strategyHarvester(MagicSavingsAddress)).to.be.equal(MagicHarvesterAddress);
        });

        it("Set magicStaker as rewardCaller on Harvester", async () => {
            expect(await MagicHarvester.connect(signers.operator).addRewardCaller(MagicStakerAddress)).to.be.not.reverted;
        });

        // Add harvester routes
        describe("Add reUSD->RSUP harvesting route", () => {
            it("Approve reUSD for MagicHarvester", async () => {
                await reUSD.connect(signers.operator).approve(MagicHarvesterAddress, 1000000n*10n**18n);
                expect(await reUSD.allowance(signers.operator.address, MagicHarvesterAddress)).to.be.equal(1000000n*10n**18n);
            });
            it("Set reUSD->RSUP route in MagicHarvester", async () => {
                let route = [
                    { 
                        pool: "0xc522A6606BBA746d7960404F22a3DB936B6F4F50", 
                        tokenIn: reUSDAddress, 
                        tokenOut: "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367", 
                        functionType: 0, 
                        indexIn: 0, 
                        indexOut: 1 
                    }, // curve reUSD->scrvUSD
                    { 
                        pool: "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367", 
                        tokenIn: "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367", 
                        tokenOut: "0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E", 
                        functionType: 1, 
                        indexIn: 1, 
                        indexOut: 0 
                    }, // scrvUSD redeem
                    { 
                        pool: "0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14", 
                        tokenIn: "0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E", 
                        tokenOut: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 
                        functionType: 2, 
                        indexIn: 0, 
                        indexOut: 1 
                    }, // curve exchange
                    { 
                        pool: "0xEe351f12EAE8C2B8B9d1B9BFd3c5dd565234578d", 
                        tokenIn: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 
                        tokenOut: RSUPAddress, 
                        functionType: 2, 
                        indexIn: 0, 
                        indexOut: 1 
                    } // curve exchange
                ];

                var RSUPbalBefore = await RSUP.balanceOf(operator);
                await MagicHarvester.connect(signers.operator).setRoute(reUSDAddress, route, RSUPAddress, 10n*10n**18n, false);
                // expect RSUP balance increase for operator after route set (due to initial harvest)
                var RSUPbalAfter = await RSUP.balanceOf(operator);
                expect(RSUPbalAfter).to.be.gt(RSUPbalBefore);
            });
        });
        describe("Add reUSD->sreUSD harvesting route", () => {
            it("Set reUSD->sreUSD route in MagicHarvester", async () => {
                let route = [
                    { 
                        pool: sreUSDAddress, 
                        tokenIn: reUSDAddress, 
                        tokenOut: sreUSDAddress, 
                        functionType: 3, 
                        indexIn: 0, 
                        indexOut: 1 
                    }
                ];

                var sreUSDBalBefore = await sreUSD.balanceOf(operator);
                await MagicHarvester.connect(signers.operator).setRoute(reUSDAddress, route, sreUSDAddress, 10n*10n**18n, false);
                // expect RSUP balance increase for operator after route set (due to initial harvest)
                var sreUSDBalAfter = await sreUSD.balanceOf(operator);
                expect(sreUSDBalAfter).to.be.gt(sreUSDBalBefore);
            });
        });

    });

    // Have test accounts create deposits
    describe("Users 0-4, 8 deposits", () => {
        
        // Set weights
        it("Should have users set weights", async () => {
            for(var i=0; i<5; i++) {
                var strat0w;
                var strat1w;
                if(i == 0) {
                    strat0w = 2500000;
                } else {
                    strat0w = 5000000;
                }
                strat1w = 10000000 - strat0w;
                expect(await MagicStaker.connect(signers.users[i]).setWeights([strat0w, strat1w])).to.be.not.reverted;
            }
            expect(await MagicStaker.connect(signers.users[8]).setWeights([strat0w, strat1w])).to.be.not.reverted;
        });

        // Token approval
        it("Should have users give token approval", async () => {
            for(var i=0; i<9; i++) {
                expect(await RSUP.connect(signers.users[i]).approve(MagicStakerAddress, 1000000000n*10n**18n)).to.be.not.reverted;
            }
        });

        // Deposit
        it("Should have users stake/deposit", async () => {
            for(var i=0; i<5; i++) {
                expect(await MagicStaker.connect(signers.users[i]).stake(100000n*10n**18n)).to.be.not.reverted;
            }
            expect(await MagicStaker.connect(signers.users[8]).stake(1000000n*10n**18n)).to.be.not.reverted;
        });

        // Verify weights cannot be changed in same epoch
        it("Should not allow users to change weights in same epoch", async () => {
            for(var i=0; i<5; i++) {
                var strat0w = Math.floor(Math.random()*10000000);
                var strat1w = 10000000 - strat0w;
                expect(MagicStaker.connect(signers.users[i]).setWeights([strat0w, strat1w])).to.be.revertedWith("!epoch");
            }
        });

    });

    // Cooldown and harvest/claim tests
    describe("Test cooldowns and claims", () => {

        // Advance time to next cooldown epoch. Skip current if already there.
        it("Should advance time until next cooldown epoch is reached", async () => {
            var isCooldown = false;
            var c = 0;
            while(!isCooldown) {
                await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
                await ethers.provider.send("evm_mine", []);
                isCooldown = await MagicStaker.isCooldownEpoch();
                c++;
            }
            console.log("     > advanced "+c+" weeks to reach cooldown epoch");
        });

        // Have some users enter cooldown before reward harvest
        it("Should have users 3 and 4 enter cooldown", async () => {
            for(var i=3; i<5; i++) {
                expect(await MagicStaker.connect(signers.users[i]).cooldown(100000n*10n**18n)).to.be.not.reverted;
            }
        });

        // Harvest rewards
        it("Should harvest rewards", async () => {
            var earned = await staker.earned(MagicStakerAddress, reUSDAddress);
            //console.log(`Claiming ${(earned/10n**18n)} reUSD from staker`);

            var opBalBefore = await reUSD.balanceOf(operator);
            var mPuSBefore = await MagicPounder.underlyingTotalSupply();
            var mPtSBefore = await MagicPounder.totalSupply();

            expect(await MagicStaker.connect(signers.operator).harvest()).to.be.not.reverted;

            var mPuSAfter = await MagicPounder.underlyingTotalSupply();
            var mPtSAfter = await MagicPounder.totalSupply();
            var opBalAfter = await reUSD.balanceOf(operator);

            // Should increase compounder underlyingTotalSupply
                await expect(mPuSBefore).to.be.lt(mPuSAfter);
            // Should not change the share supply of compounder
                await expect(mPtSBefore).to.be.equal(mPtSAfter);
            // Should increase harvest caller's reUSD balance
                await expect(opBalBefore).to.be.lt(opBalAfter);
        });

        // Verify remaining users received have pending claims
        describe("Should validate claim amounts", async () => {
            var umt = []; var w = []; var ust = []; var sw = [];
            before(async function () {
                // Prefetch values
                for(var i=0; i<9; i++) {
                    umt[i] = await MagicStaker.unclaimedMagicTokens(users[i]);
                    w[i] = await MagicStaker.accountStrategyWeight(users[i], 0);
                    ust[i] = await MagicSavings.claimable(users[i]);
                    sw[i] = await MagicStaker.accountStrategyWeight(users[i], 1);
                }
                console.log(umt);
                console.log(w);
                console.log(ust);
                console.log(sw);
            });

            // Validate amounts
            it("User 0 has half as much RSUP to claim", async () => {
                await expect(umt[0]).to.be.approximately(umt[1]/2n, 1n);
            });
            it("User 0 has 50% more reUSD to claim", async () => {
                await expect(ust[0]).to.be.approximately(ust[1]*15n/10n, 1n);
            });
            it("Users 1 and 2 have identical claims", async () => {
                await expect(umt[1]).to.be.equal(umt[2]);
                await expect(ust[1]).to.be.equal(ust[2]);
            });
            it("Cooldown users (3,4) have nothing to claim", async () => {
                await expect(umt[3]).to.be.equal(0);
                await expect(umt[4]).to.be.equal(0);
            });

        });
    });
    describe("Post-harvest tests", () => {
        // Verify compounding claim can be instantly entered into cooldown, but nothing more
        describe("Claim + cooldown in same step", async () => {
            it("Should allow user 0 to cooldown including unclaimed amount, but not more", async () => {
                var umt = await MagicStaker.unclaimedMagicTokens(users[0]);
                await expect(MagicStaker.connect(signers.users[0]).cooldown(100000n*10n**18n + umt + 1n)).to.be.revertedWith("!balance");
                expect(await MagicStaker.connect(signers.users[0]).cooldown(100000n*10n**18n + umt)).to.be.not.reverted;
            });
            it("User 0 should now have zero unclaimed RSUP", async () => {
                var umt = await MagicStaker.unclaimedMagicTokens(users[0]);
                await expect(umt).to.be.equal(0);
            });
            it("User 0 should have reduced stake by cooldown amount", async () => {
                var stake = await MagicStaker.balanceOf(users[0]);
                await expect(stake).to.be.equal(0);
            });
            it("User 0 should have 0 strategy balances", async () => {
                var strat0bal = await MagicPounder.balanceOf(users[0]);
                var strat1bal = await MagicSavings.balanceOf(users[0]);
                await expect(strat0bal).to.be.equal(0);
                await expect(strat1bal).to.be.equal(0);
            });
            it("User 0 should not be able to cooldown again", async () => {
                await expect(MagicStaker.connect(signers.users[0]).cooldown(1n)).to.be.revertedWith("!balance");
            });
            it("User 0 should still have sreUSD to claim", async () => {
                var claimable = await MagicSavings.claimable(users[0]);
                await expect(claimable).to.be.gt(0);
            });
            it("User 0 should claim sreUSD", async () => {
                var sreUSDbefore = await sreUSD.balanceOf(users[0]);
                expect(await MagicSavings.connect(signers.users[0]).claim()).to.be.not.reverted;
                var sreUSAfter = await sreUSD.balanceOf(users[0]);
                await expect(sreUSAfter).to.be.gt(sreUSDbefore);
            });
            it("User 0 should have 0 claimable sreUSD", async () => {
                var claimable = await MagicSavings.claimable(users[0]);
                await expect(claimable).to.be.equal(0);
            });
        });
        describe("User 1 claims", () => {
            it("User 1 should claim RSUP", async () => {
                var umt = await MagicStaker.unclaimedMagicTokens(users[1]);
                expect(await MagicStaker.connect(signers.users[1]).syncAccount()).to.be.not.reverted;
            });
            it("User 1 should have no unclaimed magic tokens", async () => {
                var umt = await MagicStaker.unclaimedMagicTokens(users[1]);
                await expect(umt).to.be.equal(0);
            });
            it("User 1 should have an increased stake", async () => {
                var stake = await MagicStaker.balanceOf(users[1]);
                await expect(stake).to.be.gt(100000n*10n**18n);
            });
            it("User 1 should claim sreUSD", async () => {
                var sreUSDbefore = await sreUSD.balanceOf(users[1]);
                expect(await MagicSavings.connect(signers.users[1]).claim()).to.be.not.reverted;
                var sreUSAfter = await sreUSD.balanceOf(users[1]);
                await expect(sreUSAfter).to.be.gt(sreUSDbefore);
            });
            it("User 1 should have 0 claimable sreUSD", async () => {
                var claimable = await MagicSavings.claimable(users[1]);
                await expect(claimable).to.be.equal(0);
            });
        });
        describe("User 2 changes weights", () => {
            let umt, msb, w, wb, wbs, ust, sw;
            before(async function () {
                umt = await MagicStaker.unclaimedMagicTokens(users[2]);
                msb = await MagicStaker.balanceOf(users[2]);
                w = await MagicStaker.accountStrategyWeight(users[2], 0);
                wb = await MagicPounder.balanceOf(users[2]);
                wbs = await MagicPounder.sharesOf(users[2]);
                ust = await MagicSavings.claimable(users[2]);
                sw = await MagicStaker.accountStrategyWeight(users[2], 1);
            });
            it("User 2 should be able to change weights", async () => {
                expect(await MagicStaker.connect(signers.users[2]).setWeights([1000000, 9000000])).to.be.not.reverted;
            });
            it("Unclaimed magic tokens should drop to 0", async () => {
                var umtn = await MagicStaker.unclaimedMagicTokens(users[2]);
                await expect(umtn).to.be.equal(0);
            });
            it("Staker balance should increase by original unclaimed magic tokens", async () => {
                var msbn = await MagicStaker.balanceOf(users[2]);
                await expect(msbn).to.be.approximately(msb+umt,1);
            });
            it("New pounder balance should be 10% of the staker balance", async () => {
                var wbn = await MagicPounder.balanceOf(users[2]);
                var msbn = await MagicStaker.balanceOf(users[2]);
                await expect(wbn).to.be.approximately(msbn*10n/100n,1);
            });
        });
    });
    describe("Voting", () => {
        let proposalCountBefore;
        before(async function () {
            proposalCountBefore = await voter.getProposalCount();
        });
        it("User 8 should be able to propose vote", async () => {
            // createProposal(Voter.Action[] calldata payload, string calldata description)
            expect(await MagicStaker.connect(signers.users[8]).createProposal([{target:MagicStakerAddress, data:"0x43676852"}], "test")).to.be.not.reverted;
        });
        it("Proposal count should increase by 1", async () => {
            let proposalCountAfter = await voter.getProposalCount();
            await expect(proposalCountAfter).to.be.equal(proposalCountBefore+1n);
        });
    });
});