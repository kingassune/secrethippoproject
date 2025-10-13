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

    // contracts and addresses
    let MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings;
    let MagicPounderAddress, MagicVoterAddress, MagicStakerAddress, MagicHarvesterAddress, MagicSavingsAddress, manager, operator;
    let reUSD, RSUP, sreUSD, staker;
    let reUSDAddress, RSUPAddress, sreUSDAddress, stakerAddress;
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

    before(async function () {
        ({ MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings, manager, operator, reUSD, RSUP, sreUSD, staker } = await loadFixture(setUpSmartContracts));
        MagicPounderAddress = await MagicPounder.getAddress();
        MagicVoterAddress = await MagicVoter.getAddress();
        MagicStakerAddress = await MagicStaker.getAddress();
        MagicHarvesterAddress = await MagicHarvester.getAddress();
        MagicSavingsAddress = await MagicSavings.getAddress();
        reUSDAddress = await reUSD.getAddress();
        RSUPAddress = await RSUP.getAddress();
        sreUSDAddress = await sreUSD.getAddress();
        stakerAddress = await staker.getAddress();

        await impersonateAccount(manager);
        signers.manager = await ethers.getSigner(manager);
        await setBalance(manager, ethers.toBigInt("10000000000000000000"));

        await impersonateAccount(operator);
        signers.operator = await ethers.getSigner(operator);
        await setBalance(operator, ethers.toBigInt("10000000000000000000"));

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
        }
        

    });

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

    describe("Initial Setup", () => {
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
        it("Set MagicHarvester as Strategy 0 and Strategy 1 Harvester in MagicStaker", async () => {
            await MagicStaker.connect(signers.operator).setStrategyHarvester(MagicPounderAddress, MagicHarvesterAddress);
            expect(await MagicStaker.strategyHarvester(MagicPounderAddress)).to.be.equal(MagicHarvesterAddress);
            await MagicStaker.connect(signers.operator).setStrategyHarvester(MagicSavingsAddress, MagicHarvesterAddress);
            expect(await MagicStaker.strategyHarvester(MagicSavingsAddress)).to.be.equal(MagicHarvesterAddress);
        });
        it("Set magicStaker as rewardCaller on Harvester", async () => {
            expect(await MagicHarvester.connect(signers.operator).addRewardCaller(MagicStakerAddress)).to.be.not.reverted;
        });
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
    describe("Users 0-5", () => {
        it("Should have users set weights", async () => {
            for(var i=0; i<5; i++) {
                var strat0w = Math.floor(Math.random()*10000000);
                var strat1w = 10000000 - strat0w;
                expect(await MagicStaker.connect(signers.users[i]).setWeights([5000000, 5000000])).to.be.not.reverted;
            }
        });
        it("Should have users give token approval", async () => {
            for(var i=0; i<5; i++) {
                expect(await RSUP.connect(signers.users[i]).approve(MagicStakerAddress, 1000000000n*10n**18n)).to.be.not.reverted;
            }
        });
        it("Should have users stake/deposit", async () => {
            for(var i=0; i<5; i++) {
                expect(await MagicStaker.connect(signers.users[i]).stake(10000n*10n**18n)).to.be.not.reverted;
            }
        });
        it("Should not allow users to change weights in same epoch", async () => {
            for(var i=0; i<5; i++) {
                var strat0w = Math.floor(Math.random()*10000000);
                var strat1w = 10000000 - strat0w;
                // !epoch
                expect(MagicStaker.connect(signers.users[i]).setWeights([strat0w, strat1w])).to.be.revertedWith("!epoch");
            }
        });
    });
    describe("Test cooldowns and claims", () => {
        it("Should avance time until next cooldown epoch is reached", async () => {
            var isCooldown = false;
            var c = 0;
            while(!isCooldown) {
                await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
                await ethers.provider.send("evm_mine", []);
                isCooldown = await MagicStaker.isCooldownEpoch();
                c++;
            }
            console.log("  > advanced "+c+" weeks to reach cooldown epoch");
        });
        it("Should have users 3 and 4 enter cooldown", async () => {
            for(var i=3; i<5; i++) {
                expect(await MagicStaker.connect(signers.users[i]).cooldown(10000n*10n**18n)).to.be.not.reverted;
            }
        });
        it("Should harvest rewards", async () => {
            var earned = await staker.earned(MagicStakerAddress, reUSDAddress);
            console.log(`Claiming ${(earned/10n**18n)} reUSD from staker`);

            var RSUPbalBefore = await RSUP.balanceOf(MagicStakerAddress);
            var reUSDbalBefore = await reUSD.balanceOf(MagicStakerAddress);
        
            var mPuSBefore = await MagicPounder.underlyingTotalSupply();
            var mPtSBefore = await MagicPounder.totalSupply();

            expect(await MagicStaker.connect(signers.operator).harvest()).to.be.not.reverted;

            var RSUPbalAfter = await RSUP.balanceOf(MagicStakerAddress);
            var reUSDbalAfter = await reUSD.balanceOf(MagicStakerAddress);

            var mPuSAfter = await MagicPounder.underlyingTotalSupply();
            var mPtSAfter = await MagicPounder.totalSupply();
            
            console.log(`RSUP before: ${RSUPbalBefore} RSUP after: ${RSUPbalAfter}`);
            console.log(`reUSD before: ${reUSDbalBefore} re after: ${reUSDbalAfter}`);
            console.log(`Underlying supply before: ${mPuSBefore} , After: ${mPuSAfter}`);
            console.log(`Total supply before: ${mPtSBefore} , After: ${mPtSAfter}`)
        });
        it("Should increase unclaimedMagicTokens() of users 0-2", async () => {
            for(var i=0; i<5; i++) {
                var umt = await MagicStaker.unclaimedMagicTokens(users[i]);
                var w = await MagicStaker.accountStrategyWeight(users[i], 0);
                var ust = await MagicSavings.calculateRewardsEarned(users[i]);
                var sw = await MagicStaker.accountStrategyWeight(users[i], 1);
                console.log(`User ${i} has ${umt} RSUP with weight of ${w}`);
                console.log(`User ${i} has ${ust} reUSD with weight of ${sw}`);
            }
        })
        it("Should allow user 0 to cooldown including unclaimed amount", async () => {
            var umt = await MagicStaker.unclaimedMagicTokens(users[0]);
            await expect(MagicStaker.connect(signers.users[0]).cooldown(10000n*10n**18n + umt + 1n)).to.be.revertedWith("!balance");
            expect(await MagicStaker.connect(signers.users[0]).cooldown(10000n*10n**18n + umt)).to.be.not.reverted;
        });
    });

});