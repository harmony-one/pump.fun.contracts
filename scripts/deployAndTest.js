const { ethers } = require("hardhat");

async function main() {
    const [owner, user] = await ethers.getSigners();

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

    console.log("Deploying TokenFactory...");
    const TokenFactory = await ethers.getContractFactory("TokenFactoryBase");
    const tokenFactory = await TokenFactory.deploy();
    await tokenFactory.initialize(tokenImplementation.address, bondingCurve.address, 100);
    console.log(`TokenFactory deployed at: ${tokenFactory.address}`);

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
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
