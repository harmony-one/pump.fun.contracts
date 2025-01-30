const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0x4A03c2177c0E2aB6e60A78D751B1C55Bf9A31DBD";

  console.log("Upgrading TokenFactoryUpgradeable...");

  const TokenFactoryUpgradeableV2 = await ethers.getContractFactory("TokenFactory");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, TokenFactoryUpgradeableV2);

  console.log("TokenFactoryUpgradeable upgraded. Proxy now points to:", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
