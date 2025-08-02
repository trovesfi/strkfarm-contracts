import { expect } from "chai";
import { ethers } from "hardhat";
import { MVSManager, LeverageVault, MockERC20 } from "../typechain-types";

describe("MVSManager", function () {
  let manager: MVSManager;
  let leverageVault: LeverageVault;
  let asset: MockERC20;
  let admin: any;
  let user: any;
  let rebalancer: any;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const INITIAL_LEVERAGE = 15000; // 1.5x

  beforeEach(async function () {
    [admin, user, rebalancer] = await ethers.getSigners();

    // Deploy mock ERC20
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    asset = await MockERC20Factory.deploy("Test Token", "TEST", 18);

    // Deploy MVS Manager
    const MVSManagerFactory = await ethers.getContractFactory("MVSManager");
    manager = await MVSManagerFactory.deploy(
      await asset.getAddress(),
      "MVS Vault Token",
      "mvsTEST",
      admin.address
    );

    // Deploy Leverage Vault
    const LeverageVaultFactory = await ethers.getContractFactory("LeverageVault");
    leverageVault = await LeverageVaultFactory.deploy(
      await asset.getAddress(),
      await manager.getAddress(),
      INITIAL_LEVERAGE
    );

    // Grant rebalancer role
    const REBALANCER_ROLE = await manager.REBALANCER_ROLE();
    await manager.connect(admin).grantRole(REBALANCER_ROLE, rebalancer.address);

    // Mint tokens
    await asset.mint(user.address, INITIAL_SUPPLY);
  });

  it("Should have correct initial state", async function () {
    expect(await manager.asset()).to.equal(await asset.getAddress());
    expect(await manager.name()).to.equal("MVS Vault Token");
    expect(await manager.symbol()).to.equal("mvsTEST");
    expect(await manager.getExtensionCount()).to.equal(0);
  });

  it("Should allow admin to add extensions", async function () {
    await manager.connect(admin).addExtension(await leverageVault.getAddress());
    expect(await manager.getExtensionCount()).to.equal(1);
    expect(await manager.getExtension(0)).to.equal(await leverageVault.getAddress());
  });

  it("Should allow deposits", async function () {
    const depositAmount = ethers.parseEther("1000");
    
    await asset.connect(user).approve(await manager.getAddress(), depositAmount);
    await manager.connect(user).deposit(depositAmount, user.address);
    
    expect(await manager.balanceOf(user.address)).to.equal(depositAmount);
    expect(await manager.totalAssets()).to.equal(depositAmount);
  });

  it("Should create and execute rebalance combinations", async function () {
    const depositAmount = ethers.parseEther("1000");
    const pushAmount = ethers.parseEther("300");

    // Add extension
    await manager.connect(admin).addExtension(await leverageVault.getAddress());

    // Deposit
    await asset.connect(user).approve(await manager.getAddress(), depositAmount);
    await manager.connect(user).deposit(depositAmount, user.address);

    // Create rebalance combination
    const steps = [{
      extensionIndex: 0,
      operation: 0, // push
      amount: pushAmount,
      data: "0x"
    }];

    await manager.connect(admin).addRebalanceCombination("Test Push", steps);

    // Execute rebalance
    await manager.connect(rebalancer).rebalance(0);

    // Check results
    const expectedManagerBalance = depositAmount - pushAmount;
    expect(await asset.balanceOf(await manager.getAddress())).to.equal(expectedManagerBalance);
  });
});