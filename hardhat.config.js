require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-etherscan");

const env = require('./env.json');

const { MAINNET_URL, MAINNET_DEPLOY_KEY } = env;

const getEnvAccounts = (DEFAULT_DEPLOYER_KEY) => [DEFAULT_DEPLOYER_KEY];

task('accounts', 'Prints the list of accounts', async (_, hre) => {
  const accounts = await hre.ethers.getSigners();
  accounts.forEach(account => console.info(account.address));
});

task('balance', "Prints an account's balance")
  .addParam('account', "The account's address")
  .setAction(async (taskArgs, hre) => {
    const balance = await hre.ethers.provider.getBalance(taskArgs.account);
    console.log(ethers.formatEther(balance), 'ETH');
  });

task('processFees', 'Processes fees')
  .addParam('steps', 'The steps to run')
  .setAction(async (taskArgs) => {
    const { processFees } = require('./scripts/core/processFees');
    await processFees(taskArgs);
  });

module.exports = {
  networks: {
    localhost: {
      timeout: 120000,
    },
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    mainnet: {
      url: MAINNET_URL,
      accounts: [`0x${MAINNET_DEPLOY_KEY}`],
      gasLimit: 30000000,
      gasPrice: 101_000_000_000,
    },
  },
  etherscan: {
    apiKey: MAINNET_DEPLOY_KEY,
  },
  solidity: {
    version: '0.8.26',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};