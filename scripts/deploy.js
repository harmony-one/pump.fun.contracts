const { upgrades } = require("hardhat");
const hre = require("hardhat");

const NonfungiblePositionManagerArtifact = require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json");

async function main() {
    console.log("Deploying TokenFactoryUpgradeable...");

    const [deployer] = await ethers.getSigners();

    const weth = { address: "0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a" };

    // Deploy Token contract
    const Token = await hre.ethers.getContractFactory("Token");
    const tokenImplementation = await Token.deploy();
    await tokenImplementation.deployed();
    console.log("Token deployed to:", tokenImplementation.address);

    // Deploy BancorBondingCurve contract
    const BondingCurve = await ethers.getContractFactory("BancorBondingCurve");
    const bondingCurve = await BondingCurve.deploy(1000000, 1000000);
    await bondingCurve.deployed();
    console.log("BancorBondingCurve deployed to:", bondingCurve.address);

    // UniswapV3 Factory address
    let uniswapV3FactoryAddress = "0x12d21f5d0ab768c312e19653bf3f89917866b8e8";

    // Deploy PositionManager contract
    const PositionManager = new ethers.ContractFactory(
        NonfungiblePositionManagerArtifact.abi,
        NonfungiblePositionManagerArtifact.bytecode,
        deployer
    );
    const positionManager = await PositionManager.deploy(uniswapV3FactoryAddress, weth.address, ethers.constants.AddressZero);
    await positionManager.deployed();
    console.log("NonfungiblePositionManager deployed to:", positionManager.address);

    // Deploy TokenFactoryUpgradeable proxy contract
    const TokenFactoryUpgradeable = await ethers.getContractFactory("TokenFactory");
    const proxy = await upgrades.deployProxy(
        TokenFactoryUpgradeable,
        [
            tokenImplementation.address,
            uniswapV3FactoryAddress,
            positionManager.address,
            bondingCurve.address,
            weth.address,
            100, // _feePercent
            deployer.address
        ],
        { initializer: "initialize" }
    );
    await proxy.deployed();
    console.log("TokenFactoryUpgradeable deployed to:", proxy.address);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
