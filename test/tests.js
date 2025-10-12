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
    let reUSD, RSUP;
    let reUSDAddress, RSUPAddress;
    let signers = {}

    before(async function () {
        ({ MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings, manager, operator, reUSD, RSUP } = await loadFixture(setUpSmartContracts));
        MagicPounderAddress = await MagicPounder.getAddress();
        MagicVoterAddress = await MagicVoter.getAddress();
        MagicStakerAddress = await MagicStaker.getAddress();
        MagicHarvesterAddress = await MagicHarvester.getAddress();
        MagicSavingsAddress = await MagicSavings.getAddress();
        reUSDAddress = reUSD.getAddress();
        RSUPAddress = RSUP.getAddress();


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
        reUSD.connect(signers.reUSDwhale).transfer(operator, 100000n*10n**18n);

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
        it("Set MagicHarvester as Strategy 0 Harvester in MagicStaker", async () => {
            await MagicStaker.connect(signers.operator).setStrategyHarvester(MagicPounderAddress, MagicHarvesterAddress);
            expect(await MagicStaker.strategyHarvester(MagicPounderAddress)).to.be.equal(MagicHarvesterAddress);
        });
        describe("Add reUSD->RSUP harvesting route", async () => {
            it("Approve reUSD for MagicHarvester", async () => {
                await reUSD.connect(signers.operator).approve(MagicHarvesterAddress, 1000000n*10n**18n);
                expect(await reUSD.allowance(signers.operator.address, MagicHarvesterAddress)).to.be.equal(1000000n*10n**18n);
            });
            /*     practice route:
        tokenIn = reUSD
        tokenOut = RSUP
            route[0] = { pool: 0xc522A6606BBA746d7960404F22a3DB936B6F4F50, tokenIn: reUSD, tokenOut: scrvUSD, functionType: 0, indexIn: 0, indexOut: 1 } // curve exchange
            route[1] = { pool: 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367, tokenIn: scrvUSD, tokenOut: crvUSD, functionType: 1 } // scrvUSD redeem
            route[2] = { pool: 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, tokenIn: crvUSD, tokenOut: WETH, functionType: 0 } // curve exchange
            route[3] = { pool: 0xEe351f12EAE8C2B8B9d1B9BFd3c5dd565234578d, tokenIn: WETH, tokenOut: RSUP, functionType: 0 } // curve exchange
        */
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
                        indexIn: 0, 
                        indexOut: 1 
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
    });
});