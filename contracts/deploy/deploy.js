// Deploy script for OpenOcean contracts
// Usage: npx hardhat run scripts/deploy.js --network mainnet

const { ethers, upgrades } = require("hardhat");

// Configuration
const CONFIG = {
  mainnet: {
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    UniswapV3Router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    CurveRegistry: "0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5",
    BalancerVault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",

    feeCollector: "0x...", // Treasury address
    feeRate: 30, // 0.3%

    keepers: [
      "0x...", // Keeper 1
      "0x...", // Keeper 2
    ],

    whitelistedRouters: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", // Uniswap V3
      "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // SushiSwap
      "0x1111111254fb6c44bAC0beD2854e76F90643097d", // 1inch
    ]
  },

  goerli: {
    WETH: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    // ... testnet addresses
  }
};

async function main() {
  const network = await ethers.provider.getNetwork();
  const config = CONFIG[network.name] || CONFIG.goerli;

  console.log(`Deploying to ${network.name} (chainId: ${network.chainId})`);
  console.log("========================================");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.utils.formatEther(await deployer.getBalance()), "ETH");
  console.log("");

  // ============ Deploy OpenOcean Aggregator ============
  console.log("1. Deploying OpenOcean Aggregator V1...");

  const AggregatorFactory = await ethers.getContractFactory("OpenOceanAggregatorV1");
  const aggregator = await upgrades.deployProxy(
    AggregatorFactory,
    [config.WETH],
    {
      initializer: "initialize",
      kind: "uups"
    }
  );

  await aggregator.deployed();
  console.log("   ✅ Aggregator deployed to:", aggregator.address);

  // Configure aggregator
  console.log("   Configuring aggregator...");

  // Set fee configuration
  await aggregator.setFeeConfig(config.feeRate, config.feeCollector);
  console.log("   ✅ Fee configured:", config.feeRate / 100 + "%");

  // Whitelist routers
  for (const router of config.whitelistedRouters) {
    await aggregator.setRouterWhitelist(router, true);
    console.log(`   ✅ Router whitelisted: ${router}`);
  }

  // ============ Deploy Limit Order Protocol ============
  console.log("\n2. Deploying Limit Order Protocol...");

  const LimitOrderFactory = await ethers.getContractFactory("OpenOceanLimitOrder");
  const limitOrder = await LimitOrderFactory.deploy();
  await limitOrder.deployed();

  console.log("   ✅ Limit Order deployed to:", limitOrder.address);

  // ============ Deploy DCA Vault ============
  console.log("\n3. Deploying DCA Vault...");

  const DCAFactory = await ethers.getContractFactory("OpenOceanDCA");
  const dcaVault = await DCAFactory.deploy(aggregator.address);
  await dcaVault.deployed();

  console.log("   ✅ DCA Vault deployed to:", dcaVault.address);

  // Configure DCA Vault
  console.log("   Configuring DCA Vault...");

  for (const keeper of config.keepers) {
    await dcaVault.addKeeper(keeper);
    console.log(`   ✅ Keeper added: ${keeper}`);
  }

  // ============ Verify Contracts ============
  console.log("\n4. Preparing verification data...");

  const contracts = {
    aggregator: {
      address: aggregator.address,
      constructorArguments: [config.WETH]
    },
    limitOrder: {
      address: limitOrder.address,
      constructorArguments: []
    },
    dcaVault: {
      address: dcaVault.address,
      constructorArguments: [aggregator.address]
    }
  };

  // Save deployment info
  const fs = require('fs');
  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: contracts,
    config: config
  };

  fs.writeFileSync(
    `deployment-${network.name}.json`,
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("   ✅ Deployment info saved to deployment-" + network.name + ".json");

  // ============ Post-deployment setup ============
  console.log("\n5. Post-deployment setup...");

  // Grant roles
  console.log("   Setting up access control...");

  // Transfer ownership to multisig (if configured)
  if (config.multisig) {
    console.log("   Transferring ownership to multisig...");
    await aggregator.transferOwnership(config.multisig);
    await limitOrder.transferOwnership(config.multisig);
    await dcaVault.transferOwnership(config.multisig);
    console.log("   ✅ Ownership transferred to:", config.multisig);
  }

  // ============ Summary ============
  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE!");
  console.log("========================================");
  console.log("Aggregator:", aggregator.address);
  console.log("Limit Order:", limitOrder.address);
  console.log("DCA Vault:", dcaVault.address);
  console.log("========================================");

  // ============ Verify on Etherscan ============
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\nTo verify contracts on Etherscan, run:");
    console.log(`npx hardhat verify --network ${network.name} ${aggregator.address} "${config.WETH}"`);
    console.log(`npx hardhat verify --network ${network.name} ${limitOrder.address}`);
    console.log(`npx hardhat verify --network ${network.name} ${dcaVault.address} "${aggregator.address}"`);
  }
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });