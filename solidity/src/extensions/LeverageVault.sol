// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IMVSSubExtension.sol";

/**
 * @title LeverageVault
 * @notice Example implementation of IMVSSubExtension for leveraged strategies
 * @dev This is a simplified example - real implementation would integrate with lending protocols
 */
contract LeverageVault is IMVSSubExtension, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The underlying asset token
    IERC20 public immutable assetToken;

    /// @notice The manager contract address
    address public immutable manager;

    /// @notice Current leverage multiplier (in basis points, 10000 = 1x)
    uint256 public leverageMultiplier;

    /// @notice Maximum leverage allowed (in basis points)
    uint256 public constant MAX_LEVERAGE = 30000; // 3x

    /// @notice Minimum leverage allowed (in basis points)
    uint256 public constant MIN_LEVERAGE = 10000; // 1x (no leverage)

    /// @notice Total assets currently managed by this extension
    uint256 private _totalAssets;

    /// @notice Events
    event AssetsDeployed(uint256 amount, uint256 leverage);
    event AssetsWithdrawn(uint256 amount);
    event LeverageUpdated(uint256 oldLeverage, uint256 newLeverage);
    event EmergencyWithdrawExecuted(uint256 amount);

    /// @notice Custom errors
    error OnlyManager();
    error InvalidLeverage();
    error InsufficientBalance();
    error InvalidAmount();

    /**
     * @notice Constructor
     * @param _asset The underlying asset token
     * @param _manager The manager contract address
     * @param _initialLeverage Initial leverage multiplier in basis points
     */
    constructor(
        address _asset,
        address _manager,
        uint256 _initialLeverage
    ) Ownable(msg.sender) {
        if (_initialLeverage < MIN_LEVERAGE || _initialLeverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        assetToken = IERC20(_asset);
        manager = _manager;
        leverageMultiplier = _initialLeverage;
    }

    /**
     * @notice Modifier to restrict access to manager only
     */
    modifier onlyManager() {
        if (msg.sender != manager) revert OnlyManager();
        _;
    }

    /**
     * @notice Returns the total assets managed by this extension
     * @return Total asset value
     */
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    /**
     * @notice Returns the underlying asset token address
     * @return Address of the underlying asset token
     */
    function asset() external view override returns (address) {
        return address(assetToken);
    }

    /**
     * @notice Pushes assets from manager to extension
     * @param amount Amount of assets to receive
     * @param data Additional data (encoded leverage parameters if any)
     * @return success Whether the push was successful
     */
    function pushAssets(uint256 amount, bytes calldata data) external override onlyManager nonReentrant returns (bool success) {
        if (amount == 0) revert InvalidAmount();

        // Decode data if provided (could contain leverage adjustment)
        if (data.length > 0) {
            uint256 newLeverage = abi.decode(data, (uint256));
            if (newLeverage >= MIN_LEVERAGE && newLeverage <= MAX_LEVERAGE) {
                _updateLeverage(newLeverage);
            }
        }

        // Simulate deploying assets with leverage
        // In a real implementation, this would interact with lending protocols
        uint256 leveragedAmount = (amount * leverageMultiplier) / 10000;
        _totalAssets += leveragedAmount;

        emit AssetsDeployed(amount, leverageMultiplier);
        return true;
    }

    /**
     * @notice Pulls assets from extension back to manager
     * @param amount Amount of assets to send back
     * @param data Additional data (unused in this example)
     * @return success Whether the pull was successful
     */
    function pullAssets(uint256 amount, bytes calldata data) external override onlyManager nonReentrant returns (bool success) {
        data; // Silence unused parameter warning
        
        if (amount == 0) revert InvalidAmount();
        if (amount > maxPull()) revert InsufficientBalance();

        // Simulate unwinding leveraged position
        // In a real implementation, this would unwind positions on lending protocols
        uint256 actualWithdrawAmount = (amount * 10000) / leverageMultiplier;
        _totalAssets -= amount;

        // Transfer assets back to manager
        assetToken.safeTransfer(manager, actualWithdrawAmount);

        emit AssetsWithdrawn(actualWithdrawAmount);
        return true;
    }

    /**
     * @notice Gets the maximum amount that can be pushed to this extension
     * @return Maximum pushable amount (unlimited for this example)
     */
    function maxPush() external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Gets the maximum amount that can be pulled from this extension
     * @return Maximum pullable amount
     */
    function maxPull() external view override returns (uint256) {
        return _totalAssets;
    }

    /**
     * @notice Emergency withdrawal function
     * @return Amount withdrawn
     */
    function emergencyWithdraw() external override onlyManager returns (uint256) {
        uint256 currentBalance = assetToken.balanceOf(address(this));
        uint256 totalManagedAssets = _totalAssets;
        
        // Reset total assets
        _totalAssets = 0;

        // In a real implementation, this would emergency exit all positions
        // For simplicity, we'll just transfer the current balance
        if (currentBalance > 0) {
            assetToken.safeTransfer(manager, currentBalance);
        }

        emit EmergencyWithdrawExecuted(currentBalance);
        return totalManagedAssets;
    }

    /**
     * @notice Returns the extension's identifier
     * @return Extension identifier
     */
    function extensionId() external pure override returns (string memory) {
        return "LeverageVault_v1.0";
    }

    /**
     * @notice Updates the leverage multiplier
     * @param newLeverage New leverage multiplier in basis points
     */
    function updateLeverage(uint256 newLeverage) external onlyOwner {
        _updateLeverage(newLeverage);
    }

    /**
     * @notice Internal function to update leverage
     * @param newLeverage New leverage multiplier in basis points
     */
    function _updateLeverage(uint256 newLeverage) internal {
        if (newLeverage < MIN_LEVERAGE || newLeverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        uint256 oldLeverage = leverageMultiplier;
        leverageMultiplier = newLeverage;

        emit LeverageUpdated(oldLeverage, newLeverage);
    }

    /**
     * @notice Gets current leverage information
     * @return current Current leverage multiplier
     * @return min Minimum allowed leverage
     * @return max Maximum allowed leverage
     */
    function getLeverageInfo() external view returns (uint256 current, uint256 min, uint256 max) {
        return (leverageMultiplier, MIN_LEVERAGE, MAX_LEVERAGE);
    }

    /**
     * @notice Simulates the effective APY with current leverage
     * @param baseApy Base APY without leverage (in basis points)
     * @return Effective APY with leverage applied
     */
    function getEffectiveAPY(uint256 baseApy) external view returns (uint256) {
        // Simplified calculation: effectiveAPY = baseAPY * leverage - borrowCost
        // In reality, this would be much more complex
        uint256 borrowCostBps = 300; // 3% borrow cost
        uint256 effectiveAPY = (baseApy * leverageMultiplier) / 10000;
        
        if (effectiveAPY > borrowCostBps) {
            return effectiveAPY - borrowCostBps;
        }
        return 0;
    }
}