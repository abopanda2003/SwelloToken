const path = require('path')
const { ethers, getNamedAccounts, getChainId, deployments } = require("hardhat");

const chalk = require('chalk');


let owner, user1, user2, user3, user4;
let auto, treasury, safety, charity;

function dim() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.dim.call(chalk, ...arguments));
  }
}

function cyan() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.cyan.call(chalk, ...arguments));
  }
}

function yellow() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.yellow.call(chalk, ...arguments));
  }
}

function green() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.green.call(chalk, ...arguments));
  }
}

function displayResult(name, result) {
  if (!result.newlyDeployed) {
    yellow(`Re-used existing ${name} at ${result.address}`);
  } else {
    green(`${name} deployed at ${result.address}`);
  }
}

const chainName = (chainId) => {
  switch (chainId) {
    case 1:
      return 'Mainnet';
    case 3:
      return 'Ropsten';
    case 4:
      return 'Rinkeby';
    case 5:
      return 'Goerli';
    case 42:
      return 'Kovan';
    case 56:
      return 'Binance Smart Chain';
    case 77:
      return 'POA Sokol';
    case 97:
      return 'Binance Smart Chain (testnet)';
    case 99:
      return 'POA';
    case 100:
      return 'xDai';
    case 137:
      return 'Matic';
    case 1337:
        return 'HardhatEVM';
    case 31337:
      return 'HardhatEVM';
    case 80001:
      return 'Matic (Mumbai)';
    default:
      return 'Unknown';
  }
};

const displayTokenInfo = async(tokenIns) => {
    cyan("*****************************");
    cyan("     Token Information     ");
    cyan("*****************************");
  
    const name = await tokenIns.name();
    dim(`token name: ${name}`);
    const symbol = await tokenIns.symbol();
    dim(`token symbol: ${symbol}`);
    const decimal = await tokenIns.decimals();
    dim(`token decimal: ${decimal.toString()}`);
    const totalSupply = await tokenIns.totalSupply();
    dim(`token total supply: ${ethers.utils.formatEther(totalSupply.toString())}`);
}
  
async function main() {

    const { getNamedAccounts } = hre;
    const { getContractFactory, getSigners } = ethers;

    let {
      Router,
      AutoLiquidityReceiver,
      TreasuryReceiver,
      SafetyFundReceiver,
      CharityReceiver,
      BUSD,
      SWELLO
    } = await getNamedAccounts();

    [owner] = await getSigners();

    const chainId = parseInt(await getChainId(), 10);
    const upgrades = hre.upgrades;

    dim('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    dim('Swello Contracts - Deploy Script');
    dim('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n');

    dim(`Network: ${chainName(chainId)}`);

    console.log("owner:", owner.address);

    let busdAddress = BUSD;

    if(options.deploySWL) {      
      const SwelloContract = await ethers.getContractFactory('Swello');
      console.log("Router: ", Router);
      console.log("busd: ", busdAddress);
      const swlIns = await upgrades.deployProxy(
        SwelloContract,
        [
          Router,
          busdAddress,
          AutoLiquidityReceiver,
          TreasuryReceiver,
          SafetyFundReceiver,
          CharityReceiver
        ],
        { initializer: 'initialize', kind: 'uups' }
      );
      await swlIns.deployed();
      displayResult("Swello Token Address: ", swlIns);
      await displayTokenInfo(swlIns);
      swlAddress = swlIns.address;            
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
