// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/MVSManager.sol";
import "../src/extensions/LeverageVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**decimals_);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}

contract MVSManagerTest {
    MVSManager public manager;
    LeverageVault public leverageVault;
    MockERC20 public asset;
    
    address public admin = address(0x1);
    address public user = address(0x2);
    address public rebalancer = address(0x3);
    
    uint256 public constant INITIAL_SUPPLY = 1000000e18;
    uint256 public constant INITIAL_LEVERAGE = 15000; // 1.5x

    function setUp() public {
        // Deploy mock ERC20 token
        asset = new MockERC20("Test Token", "TEST", 18);
        
        // Deploy MVS Manager
        manager = new MVSManager(
            IERC20(address(asset)),
            "MVS Vault Token",
            "mvsTEST",
            admin
        );
        
        // Deploy Leverage Vault extension
        leverageVault = new LeverageVault(
            address(asset),
            address(manager),
            INITIAL_LEVERAGE
        );
        
        // Setup roles - would be done by admin in real deployment
        
        // Mint tokens to test accounts
        asset.mint(user, INITIAL_SUPPLY);
        asset.mint(address(this), INITIAL_SUPPLY);
    }

    function testInitialState() public {
        assertEq(manager.asset(), address(asset));
        assertEq(manager.name(), "MVS Vault Token");
        assertEq(manager.symbol(), "mvsTEST");
        assertEq(manager.getExtensionCount(), 0);
        assertEq(manager.nextCombinationId(), 0);
    }

    function testAddExtension() public {
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        assertEq(manager.getExtensionCount(), 1);
        assertEq(manager.getExtension(0), address(leverageVault));
    }

    function testAddExtensionOnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        manager.addExtension(leverageVault);
    }

    function testRemoveExtension() public {
        vm.startPrank(admin);
        manager.addExtension(leverageVault);
        assertEq(manager.getExtensionCount(), 1);
        
        manager.removeExtension(0);
        assertEq(manager.getExtensionCount(), 0);
        vm.stopPrank();
    }

    function testBasicDeposit() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        uint256 shares = manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        assertEq(shares, depositAmount); // 1:1 for first deposit
        assertEq(manager.balanceOf(user), shares);
        assertEq(manager.totalAssets(), depositAmount);
    }

    function testTotalAssetsWithExtensions() public {
        uint256 depositAmount = 1000e18;
        uint256 extensionAmount = 500e18;
        
        // Add extension
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        // Deposit to manager
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Transfer some assets to extension and simulate push
        asset.transfer(address(leverageVault), extensionAmount);
        vm.prank(address(manager));
        leverageVault.pushAssets(extensionAmount, "");
        
        uint256 expectedTotal = (depositAmount - extensionAmount) + // Manager balance
                               (extensionAmount * INITIAL_LEVERAGE / 10000); // Extension assets with leverage
        
        assertEq(manager.totalAssets(), expectedTotal);
    }

    function testCreateRebalanceCombination() public {
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        MVSManager.RebalanceStep[] memory steps = new MVSManager.RebalanceStep[](1);
        steps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0,
            operation: 0, // push
            amount: 100e18,
            data: ""
        });
        
        vm.prank(admin);
        uint256 combinationId = manager.addRebalanceCombination("Test Push", steps);
        
        assertEq(combinationId, 0);
        assertEq(manager.nextCombinationId(), 1);
        
        MVSManager.RebalanceStep[] memory savedSteps = manager.getRebalanceCombinationSteps(combinationId);
        assertEq(savedSteps.length, 1);
        assertEq(savedSteps[0].extensionIndex, 0);
        assertEq(savedSteps[0].operation, 0);
        assertEq(savedSteps[0].amount, 100e18);
    }

    function testExecuteRebalance() public {
        uint256 depositAmount = 1000e18;
        uint256 pushAmount = 300e18;
        
        // Setup
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        // Deposit assets
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Create rebalance combination
        MVSManager.RebalanceStep[] memory steps = new MVSManager.RebalanceStep[](1);
        steps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0,
            operation: 0, // push
            amount: pushAmount,
            data: ""
        });
        
        vm.prank(admin);
        uint256 combinationId = manager.addRebalanceCombination("Push to Leverage", steps);
        
        // Execute rebalance
        vm.prank(rebalancer);
        manager.rebalance(combinationId);
        
        // Check results
        uint256 expectedManagerBalance = depositAmount - pushAmount;
        uint256 expectedExtensionAssets = pushAmount * INITIAL_LEVERAGE / 10000;
        
        assertEq(asset.balanceOf(address(manager)), expectedManagerBalance);
        assertEq(leverageVault.totalAssets(), expectedExtensionAssets);
    }

    function testExecuteRebalanceWithPull() public {
        uint256 depositAmount = 1000e18;
        uint256 pushAmount = 300e18;
        uint256 pullAmount = 150e18;
        
        // Setup
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        // Deposit and push assets first
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Push assets to extension
        MVSManager.RebalanceStep[] memory pushSteps = new MVSManager.RebalanceStep[](1);
        pushSteps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0,
            operation: 0, // push
            amount: pushAmount,
            data: ""
        });
        
        vm.prank(admin);
        uint256 pushCombinationId = manager.addRebalanceCombination("Push", pushSteps);
        
        vm.prank(rebalancer);
        manager.rebalance(pushCombinationId);
        
        // Now create pull combination
        MVSManager.RebalanceStep[] memory pullSteps = new MVSManager.RebalanceStep[](1);
        pullSteps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0,
            operation: 1, // pull
            amount: pullAmount,
            data: ""
        });
        
        vm.prank(admin);
        uint256 pullCombinationId = manager.addRebalanceCombination("Pull", pullSteps);
        
        // Execute pull
        vm.prank(rebalancer);
        manager.rebalance(pullCombinationId);
        
        // Verify assets were pulled back
        uint256 expectedPulledAmount = pullAmount * 10000 / INITIAL_LEVERAGE;
        assertTrue(asset.balanceOf(address(manager)) > depositAmount - pushAmount);
    }

    function testEmergencyWithdraw() public {
        uint256 depositAmount = 1000e18;
        uint256 pushAmount = 300e18;
        
        // Setup
        vm.prank(admin);
        manager.addExtension(leverageVault);
        
        // Deposit and push assets
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Push to extension
        MVSManager.RebalanceStep[] memory steps = new MVSManager.RebalanceStep[](1);
        steps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0,
            operation: 0,
            amount: pushAmount,
            data: ""
        });
        
        vm.prank(admin);
        uint256 combinationId = manager.addRebalanceCombination("Push", steps);
        
        vm.prank(rebalancer);
        manager.rebalance(combinationId);
        
        // Emergency withdraw
        vm.prank(admin);
        manager.emergencyWithdrawExtension(0);
        
        // Extension should have zero assets
        assertEq(leverageVault.totalAssets(), 0);
    }

    function testPauseUnpause() public {
        uint256 depositAmount = 100e18;
        
        // Pause the contract
        vm.prank(admin);
        manager.pause();
        
        // Try to deposit while paused - should revert
        vm.startPrank(user);
        asset.approve(address(manager), depositAmount);
        vm.expectRevert();
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Unpause
        vm.prank(admin);
        manager.unpause();
        
        // Should work after unpause
        vm.startPrank(user);
        manager.deposit(depositAmount, user);
        vm.stopPrank();
        
        assertEq(manager.balanceOf(user), depositAmount);
    }

    function testMaxExtensions() public {
        vm.startPrank(admin);
        
        // Add maximum number of extensions
        for (uint256 i = 0; i < 10; i++) {
            LeverageVault newVault = new LeverageVault(
                address(asset),
                address(manager),
                INITIAL_LEVERAGE
            );
            manager.addExtension(newVault);
        }
        
        // Try to add one more - should revert
        LeverageVault extraVault = new LeverageVault(
            address(asset),
            address(manager),
            INITIAL_LEVERAGE
        );
        
        vm.expectRevert(MVSManager.MaxExtensionsReached.selector);
        manager.addExtension(extraVault);
        
        vm.stopPrank();
    }

    function testInvalidRebalanceCombination() public {
        // Try to create combination with invalid extension index
        MVSManager.RebalanceStep[] memory steps = new MVSManager.RebalanceStep[](1);
        steps[0] = MVSManager.RebalanceStep({
            extensionIndex: 0, // No extensions added yet
            operation: 0,
            amount: 100e18,
            data: ""
        });
        
        vm.prank(admin);
        vm.expectRevert(MVSManager.InvalidRebalanceStep.selector);
        manager.addRebalanceCombination("Invalid", steps);
    }

    function testLeverageVaultSpecificFunctions() public {
        assertEq(leverageVault.extensionId(), "LeverageVault_v1.0");
        
        (uint256 current, uint256 min, uint256 max) = leverageVault.getLeverageInfo();
        assertEq(current, INITIAL_LEVERAGE);
        assertEq(min, 10000);
        assertEq(max, 30000);
        
        uint256 effectiveAPY = leverageVault.getEffectiveAPY(1000); // 10% base APY
        assertTrue(effectiveAPY > 0);
    }
}