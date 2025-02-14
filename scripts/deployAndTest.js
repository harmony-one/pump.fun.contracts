const { ethers } = require("hardhat");
const NonfungiblePositionManagerArtifact = require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json");

async function main() {
    const [owner, user] = await ethers.getSigners();

    const weth = { address: "0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a" };

    // Deploy Token contract
    const Token = await hre.ethers.getContractFactory("Token");
    const tokenImplementation = await Token.deploy();
    await tokenImplementation.deployed();
    console.log("Token deployed to:", tokenImplementation.address);

    console.log("Deploying BancorBondingCurve...");
    const BancorBondingCurve = await ethers.getContractFactory("BancorBondingCurve");
    const bondingCurve = await BancorBondingCurve.deploy(1000000, 1000000);
    await bondingCurve.deployed();
    console.log(`BancorBondingCurve deployed at: ${bondingCurve.address}`);

    // UniswapV3 Factory address
    let uniswapV3FactoryAddress = "0x12d21f5d0ab768c312e19653bf3f89917866b8e8";

    // Deploy PositionManager contract
    const PositionManager = new ethers.ContractFactory(
        NonfungiblePositionManagerArtifact.abi,
        NonfungiblePositionManagerArtifact.bytecode,
        owner
    );

    const positionManager = await PositionManager.deploy(uniswapV3FactoryAddress, weth.address, ethers.constants.AddressZero);
    await positionManager.deployed();
    console.log("NonfungiblePositionManager deployed to:", positionManager.address);

    // Deploy TokenFactoryUpgradeable proxy contract
    console.log("Deploying TokenFactory...");
    const TokenFactoryUpgradeable = await ethers.getContractFactory("TokenFactoryBase");
    const tokenFactory = await upgrades.deployProxy(
        TokenFactoryUpgradeable,
        [
            tokenImplementation.address,
            uniswapV3FactoryAddress,
            positionManager.address,
            bondingCurve.address,
            weth.address,
            100, // _feePercent
            ethers.utils.parseEther("1")
        ],
        { initializer: "initialize" }
    );
    await tokenFactory.deployed();
    console.log("TokenFactoryUpgradeable deployed to:", tokenFactory.address);

    console.log("Creating Token...");
    const tx = await tokenFactory.createToken("TestToken", "TTK", "testuri");
    const receipt = await tx.wait();
    const tokenAddress = receipt.events.find(e => e.event === "TokenCreated").args.token;
    console.log(`Token created at: ${tokenAddress}`);

    console.log("Buying Token...");
    await tokenFactory.connect(owner).buy(tokenAddress, { value: ethers.utils.parseEther("1") });
    const tokenInstance = await ethers.getContractAt("Token", tokenAddress);
    const userBalance = await tokenInstance.balanceOf(owner.address);
    console.log(`User bought tokens, balance: ${userBalance.toString()}`);

    console.log("Selling Token...");
    await tokenInstance.connect(owner).approve(tokenFactory.address, userBalance);
    await tokenFactory.connect(owner).sell(tokenAddress, userBalance);
    console.log("User sold tokens.");

    console.log("Withdrawing Fees...");
    await tokenFactory.withdrawFee();
    console.log("Fees withdrawn.");

    console.log("Buying Token...");
    await tokenFactory.connect(owner).buy(tokenAddress, { value: ethers.utils.parseEther("2") });

    console.log("publishToUniswap...");
    await tokenFactory.connect(owner).publishToUniswap(tokenAddress);

    console.log("Try Buying Token after publsih...");
    await tokenFactory.connect(owner).buy(tokenAddress, { value: ethers.utils.parseEther("1") });
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
