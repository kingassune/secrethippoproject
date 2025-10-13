var { ethers } = require("hardhat");
const {
  impersonateAccount,
  setBalance,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

var { MagicPounderModule, MagicVoterModule, MagicStakerModule, MagicHarvesterModule, MagicSavingsModule } = require("../ignition/modules/Deployment");

var erc20Abi = [
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function transfer(address to, uint256 amount) external returns (bool)",
    "function balanceOf(address account) external view returns (uint256)",
    "function allowance(address owner, address spender) external view returns (uint256)",
];

var stakerAbi = [
    "function earned(address _account, address _rewardToken) external view returns (uint256)",
]

async function reUSDSetUp() {
    var reUSD;
    var reUSDAddress = "0x57aB1E0003F623289CD798B1824Be09a793e4Bec";
    reUSD = new ethers.Contract(reUSDAddress, erc20Abi, ethers.provider);
    return reUSD;
}

async function RSUPSetUp() {
    var RSUP;
    var RSUPAddress = "0x419905009e4656fdC02418C7Df35B1E61Ed5F726";
    RSUP = new ethers.Contract(RSUPAddress, erc20Abi, ethers.provider);
    return RSUP;
}

async function sreUSDSetUp() {
    var sreUSD;
    var sreUSDAddress = "0x557AB1e003951A73c12D16F0fEA8490E39C33C35";
    sreUSD = new ethers.Contract(sreUSDAddress, erc20Abi, ethers.provider);
    return sreUSD;
}

async function stakerSetUp() {
    var staker;
    var stakerAddress = "0x22222222E9fE38F6f1FC8C61b25228adB4D8B953";
    staker = new ethers.Contract(stakerAddress, stakerAbi, ethers.provider);
    return staker;
}

async function setUpSmartContracts() {
    var reUSD = await reUSDSetUp();
    var RSUP = await RSUPSetUp();
    var sreUSD = await sreUSDSetUp();
    var staker = await stakerSetUp();

    var operator = "0xAdE9e51C9E23d64E538A7A38656B78aB6Bcc349e";
    var manager = "0xdC7C7F0bEA8444c12ec98Ec626ff071c6fA27a19";

    const { MagicPounder } = await ignition.deploy(MagicPounderModule, {
    parameters: {
        DeployMagicPounder: {
        _operator: operator,
        _manager: manager,
        },
    },
    });

    const { MagicVoter } = await ignition.deploy(MagicVoterModule, {
    parameters: {
        DeployMagicVoter: {
        _operator: operator,
        _manager: manager,
        },
    },
    });

    var pounder = await MagicPounder.getAddress();
    var voter = await MagicVoter.getAddress();

    const { MagicStaker } = await ignition.deploy(MagicStakerModule, {
    parameters: {
        DeployMagicStaker: {
        _magicPounder: pounder,
        _magicVoter: voter,
        _operator: operator,
        _manager: manager,
        },
    },
    });

    var magicStakerAddress = await MagicStaker.getAddress();

    const { MagicHarvester } = await ignition.deploy(MagicHarvesterModule, {
    parameters: {
        DeployMagicHarvester: {
        _operator: operator,
        _manager: manager,
        },
    },
    });

    var sreUSDAddress = "0x557AB1e003951A73c12D16F0fEA8490E39C33C35";
    const { MagicSavings } = await ignition.deploy(MagicSavingsModule, {
    parameters: {
        DeployMagicSavings: {
        _magicStaker: magicStakerAddress,
        _rewardToken: sreUSDAddress,
        },
    },
    });


    return { MagicPounder, MagicVoter, MagicStaker, MagicHarvester, MagicSavings, manager, operator, reUSD, RSUP, sreUSD, staker };
}

module.exports = { setUpSmartContracts };