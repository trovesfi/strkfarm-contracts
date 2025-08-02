// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMVSSubExtension.sol";

/**
 * @title MVSManager
 * @notice Multi-Vault Strategy Manager - ERC4626 compatible vault with modular extensions
 * @dev Manages multiple sub-extensions and provides configurable rebalancing operations
 */
contract MVSManager is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    /// @notice Maximum number of extensions allowed
    uint256 public constant MAX_EXTENSIONS = 10;

    /// @notice Structure for rebalance operation steps
    struct RebalanceStep {
        uint8 extensionIndex; // Index in extensions array
        uint8 operation; // 0 = push, 1 = pull
        uint256 amount; // Amount for the operation (0 = max available)
        bytes data; // Additional data for the operation
    }

    /// @notice Structure for rebalance combinations
    struct RebalanceCombination {
        string name; // Human readable name
        RebalanceStep[] steps; // Array of steps to execute
        bool active; // Whether this combination is active
    }

    /// @notice Array of registered extensions
    IMVSSubExtension[] public extensions;

    /// @notice Mapping of combination ID to rebalance combination
    mapping(uint256 => RebalanceCombination) public rebalanceCombinations;

    /// @notice Next available combination ID
    uint256 public nextCombinationId;

    /// @notice Events
    event ExtensionAdded(address indexed extension, uint256 index);
    event ExtensionRemoved(address indexed extension, uint256 index);
    event RebalanceCombinationAdded(uint256 indexed combinationId, string name);
    event RebalanceCombinationUpdated(uint256 indexed combinationId, string name);
    event RebalanceCombinationDeactivated(uint256 indexed combinationId);
    event RebalanceExecuted(uint256 indexed combinationId, address indexed executor);
    event EmergencyWithdrawExecuted(uint256 indexed extensionIndex, uint256 amount);

    /// @notice Custom errors
    error MaxExtensionsReached();
    error ExtensionNotFound();
    error InvalidExtension();
    error InvalidCombinationId();
    error CombinationNotActive();
    error InvalidRebalanceStep();
    error RebalanceStepFailed(uint256 stepIndex);
    error EmptyStepsArray();

    /**
     * @notice Constructor
     * @param _asset The underlying asset token
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     * @param _admin Admin address for role management
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _admin
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REBALANCER_ROLE, _admin);
    }

    /**
     * @notice Returns total assets under management
     * @dev Includes manager contract balance + total assets of all extensions
     * @return Total assets denominated in the base asset
     */
    function totalAssets() public view override returns (uint256) {
        uint256 managerBalance = IERC20(asset()).balanceOf(address(this));
        uint256 extensionAssets = 0;

        for (uint256 i = 0; i < extensions.length; i++) {
            // Only count assets if extension uses the same base asset
            if (extensions[i].asset() == asset()) {
                extensionAssets += extensions[i].totalAssets();
            }
        }

        return managerBalance + extensionAssets;
    }

    /**
     * @notice Adds a new extension to the manager
     * @param extension Address of the extension contract
     */
    function addExtension(IMVSSubExtension extension) external onlyRole(ADMIN_ROLE) {
        if (extensions.length >= MAX_EXTENSIONS) revert MaxExtensionsReached();
        if (address(extension) == address(0)) revert InvalidExtension();
        if (extension.asset() != asset()) revert InvalidExtension();

        extensions.push(extension);
        emit ExtensionAdded(address(extension), extensions.length - 1);
    }

    /**
     * @notice Removes an extension from the manager
     * @param extensionIndex Index of the extension to remove
     */
    function removeExtension(uint256 extensionIndex) external onlyRole(ADMIN_ROLE) {
        if (extensionIndex >= extensions.length) revert ExtensionNotFound();

        address extensionAddress = address(extensions[extensionIndex]);
        
        // Move last element to the removed position and pop
        extensions[extensionIndex] = extensions[extensions.length - 1];
        extensions.pop();

        emit ExtensionRemoved(extensionAddress, extensionIndex);
    }

    /**
     * @notice Adds a new rebalance combination
     * @param name Human readable name for the combination
     * @param steps Array of rebalance steps
     * @return combinationId ID of the created combination
     */
    function addRebalanceCombination(
        string memory name,
        RebalanceStep[] memory steps
    ) external onlyRole(ADMIN_ROLE) returns (uint256 combinationId) {
        if (steps.length == 0) revert EmptyStepsArray();

        combinationId = nextCombinationId++;
        RebalanceCombination storage combination = rebalanceCombinations[combinationId];
        
        combination.name = name;
        combination.active = true;
        
        // Copy steps
        for (uint256 i = 0; i < steps.length; i++) {
            if (steps[i].extensionIndex >= extensions.length) revert InvalidRebalanceStep();
            combination.steps.push(steps[i]);
        }

        emit RebalanceCombinationAdded(combinationId, name);
    }

    /**
     * @notice Updates an existing rebalance combination
     * @param combinationId ID of the combination to update
     * @param name New name for the combination
     * @param steps New array of rebalance steps
     */
    function updateRebalanceCombination(
        uint256 combinationId,
        string memory name,
        RebalanceStep[] memory steps
    ) external onlyRole(ADMIN_ROLE) {
        if (combinationId >= nextCombinationId) revert InvalidCombinationId();
        if (steps.length == 0) revert EmptyStepsArray();

        RebalanceCombination storage combination = rebalanceCombinations[combinationId];
        
        // Clear existing steps
        delete combination.steps;
        
        combination.name = name;
        combination.active = true;
        
        // Copy new steps
        for (uint256 i = 0; i < steps.length; i++) {
            if (steps[i].extensionIndex >= extensions.length) revert InvalidRebalanceStep();
            combination.steps.push(steps[i]);
        }

        emit RebalanceCombinationUpdated(combinationId, name);
    }

    /**
     * @notice Deactivates a rebalance combination
     * @param combinationId ID of the combination to deactivate
     */
    function deactivateRebalanceCombination(uint256 combinationId) external onlyRole(ADMIN_ROLE) {
        if (combinationId >= nextCombinationId) revert InvalidCombinationId();
        
        rebalanceCombinations[combinationId].active = false;
        emit RebalanceCombinationDeactivated(combinationId);
    }

    /**
     * @notice Executes a rebalance combination
     * @param combinationId ID of the combination to execute
     */
    function rebalance(uint256 combinationId) external onlyRole(REBALANCER_ROLE) nonReentrant {
        if (combinationId >= nextCombinationId) revert InvalidCombinationId();
        
        RebalanceCombination storage combination = rebalanceCombinations[combinationId];
        if (!combination.active) revert CombinationNotActive();

        for (uint256 i = 0; i < combination.steps.length; i++) {
            RebalanceStep memory step = combination.steps[i];
            IMVSSubExtension extension = extensions[step.extensionIndex];

            bool success;
            if (step.operation == 0) { // Push operation
                uint256 pushAmount = step.amount;
                if (pushAmount == 0) {
                    // Use max available balance
                    pushAmount = IERC20(asset()).balanceOf(address(this));
                    pushAmount = pushAmount > extension.maxPush() ? extension.maxPush() : pushAmount;
                }
                
                // Transfer tokens to extension first
                IERC20(asset()).transfer(address(extension), pushAmount);
                success = extension.pushAssets(pushAmount, step.data);
            } else if (step.operation == 1) { // Pull operation
                uint256 pullAmount = step.amount;
                if (pullAmount == 0) {
                    // Use max available from extension
                    pullAmount = extension.maxPull();
                }
                
                success = extension.pullAssets(pullAmount, step.data);
            }

            if (!success) revert RebalanceStepFailed(i);
        }

        emit RebalanceExecuted(combinationId, msg.sender);
    }

    /**
     * @notice Emergency withdraw from a specific extension
     * @param extensionIndex Index of the extension to emergency withdraw from
     */
    function emergencyWithdrawExtension(uint256 extensionIndex) external onlyRole(ADMIN_ROLE) {
        if (extensionIndex >= extensions.length) revert ExtensionNotFound();
        
        uint256 amount = extensions[extensionIndex].emergencyWithdraw();
        emit EmergencyWithdrawExecuted(extensionIndex, amount);
    }

    /**
     * @notice Emergency withdraw from all extensions
     */
    function emergencyWithdrawAll() external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < extensions.length; i++) {
            uint256 amount = extensions[i].emergencyWithdraw();
            emit EmergencyWithdrawExecuted(i, amount);
        }
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Gets the number of registered extensions
     * @return Number of extensions
     */
    function getExtensionCount() external view returns (uint256) {
        return extensions.length;
    }

    /**
     * @notice Gets extension at specific index
     * @param index Index of the extension
     * @return Address of the extension
     */
    function getExtension(uint256 index) external view returns (address) {
        if (index >= extensions.length) revert ExtensionNotFound();
        return address(extensions[index]);
    }

    /**
     * @notice Gets rebalance combination steps
     * @param combinationId ID of the combination
     * @return steps Array of rebalance steps
     */
    function getRebalanceCombinationSteps(uint256 combinationId) external view returns (RebalanceStep[] memory steps) {
        if (combinationId >= nextCombinationId) revert InvalidCombinationId();
        return rebalanceCombinations[combinationId].steps;
    }

    /**
     * @notice Override deposit to add pause protection
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Override mint to add pause protection
     */
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Override withdraw to add pause protection
     */
    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Override redeem to add pause protection
     */
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }
}