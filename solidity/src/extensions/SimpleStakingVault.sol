// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/IMVSSubExtension.sol";
import "../interfaces/IYieldExtension.sol";

/**
 * @title SimpleStakingVault
 * @notice Example extension that implements simple staking with yield generation
 * @dev Implements both IMVSSubExtension and IYieldExtension interfaces
 */
contract SimpleStakingVault is IMVSSubExtension, IYieldExtension, Ownable, ReentrancyGuard, ERC165 {
    using SafeERC20 for IERC20;

    /// @notice The underlying asset token
    IERC20 public immutable assetToken;

    /// @notice The reward token (could be same as asset)
    IERC20 public immutable rewardToken;

    /// @notice The manager contract address
    address public immutable manager;

    /// @notice Mock staking pool address (in real implementation, this would be a protocol)
    address public stakingPool;

    /// @notice Current staked amount
    uint256 private _stakedAmount;

    /// @notice Total rewards harvested
    uint256 private _totalRewardsHarvested;

    /// @notice Last harvest timestamp
    uint256 private _lastHarvestTime;

    /// @notice Annual Percentage Yield in basis points (e.g., 500 = 5%)
    uint256 public currentAPY;

    /// @notice Base APY used for calculations
    uint256 public constant BASE_APY = 500; // 5%

    /// @notice Seconds in a year for APY calculations
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Events
    event AssetsStaked(uint256 amount);
    event AssetsUnstaked(uint256 amount);
    event RewardsHarvested(uint256 amount, address recipient);
    event RewardsCompounded(uint256 amount);
    event APYUpdated(uint256 newAPY);

    /// @notice Custom errors
    error OnlyManager();
    error InvalidAmount();
    error InsufficientStakedAmount();
    error InvalidStakingPool();

    /**
     * @notice Constructor
     * @param _asset The underlying asset token
     * @param _rewardToken The reward token address
     * @param _manager The manager contract address
     * @param _stakingPool Mock staking pool address
     */
    constructor(
        address _asset,
        address _rewardToken,
        address _manager,
        address _stakingPool
    ) Ownable(msg.sender) {
        assetToken = IERC20(_asset);
        rewardToken = IERC20(_rewardToken);
        manager = _manager;
        stakingPool = _stakingPool;
        currentAPY = BASE_APY;
        _lastHarvestTime = block.timestamp;
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
     * @return Total staked assets
     */
    function totalAssets() external view override returns (uint256) {
        return _stakedAmount;
    }

    /**
     * @notice Returns the underlying asset token address
     * @return Address of the underlying asset token
     */
    function asset() external view override returns (address) {
        return address(assetToken);
    }

    /**
     * @notice Pushes assets from manager to extension for staking
     * @param amount Amount of assets to stake
     * @param data Additional data (unused in this implementation)
     * @return success Whether the push was successful
     */
    function pushAssets(uint256 amount, bytes calldata data) external override onlyManager nonReentrant returns (bool success) {
        data; // Silence unused parameter warning
        
        if (amount == 0) revert InvalidAmount();

        // In a real implementation, this would stake tokens in an external protocol
        // For simulation, we just track the staked amount
        _stakedAmount += amount;

        // Update last harvest time
        _lastHarvestTime = block.timestamp;

        emit AssetsStaked(amount);
        return true;
    }

    /**
     * @notice Pulls assets from extension back to manager
     * @param amount Amount of assets to unstake and return
     * @param data Additional data (unused in this implementation)
     * @return success Whether the pull was successful
     */
    function pullAssets(uint256 amount, bytes calldata data) external override onlyManager nonReentrant returns (bool success) {
        data; // Silence unused parameter warning
        
        if (amount == 0) revert InvalidAmount();
        if (amount > _stakedAmount) revert InsufficientStakedAmount();

        // Unstake from the pool
        _stakedAmount -= amount;

        // Transfer assets back to manager
        assetToken.safeTransfer(manager, amount);

        emit AssetsUnstaked(amount);
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
     * @return Maximum pullable amount (all staked assets)
     */
    function maxPull() external view override returns (uint256) {
        return _stakedAmount;
    }

    /**
     * @notice Emergency withdrawal function
     * @return Amount withdrawn
     */
    function emergencyWithdraw() external override onlyManager returns (uint256) {
        uint256 stakedAmount = _stakedAmount;
        
        // Reset staked amount
        _stakedAmount = 0;

        // In a real implementation, this would emergency unstake from the protocol
        // Transfer any available balance back to manager
        uint256 availableBalance = assetToken.balanceOf(address(this));
        if (availableBalance > 0) {
            assetToken.safeTransfer(manager, availableBalance);
        }

        return stakedAmount;
    }

    /**
     * @notice Returns the extension's identifier
     * @return Extension identifier
     */
    function extensionId() external pure override returns (string memory) {
        return "SimpleStakingVault_v1.0";
    }

    /**
     * @notice Harvests accumulated yield/rewards
     * @param recipient Address to receive harvested tokens
     * @param data Additional parameters (unused)
     * @return harvestedAmounts Array of harvested amounts
     * @return tokens Array of token addresses
     */
    function harvest(address recipient, bytes calldata data) 
        external 
        override 
        onlyManager 
        returns (uint256[] memory harvestedAmounts, address[] memory tokens) 
    {
        data; // Silence unused parameter warning
        
        uint256 pendingRewards = getPendingYield();
        
        if (pendingRewards > 0) {
            _totalRewardsHarvested += pendingRewards;
            _lastHarvestTime = block.timestamp;

            // In a real implementation, this would claim rewards from the staking protocol
            // For simulation, we mint or transfer reward tokens
            if (address(rewardToken) != address(0)) {
                rewardToken.safeTransfer(recipient, pendingRewards);
            }

            emit RewardsHarvested(pendingRewards, recipient);
        }

        // Return arrays
        harvestedAmounts = new uint256[](1);
        tokens = new address[](1);
        harvestedAmounts[0] = pendingRewards;
        tokens[0] = address(rewardToken);
    }

    /**
     * @notice Gets current APY
     * @return apy Current APY in basis points
     */
    function getCurrentAPY() external view override returns (uint256 apy) {
        return currentAPY;
    }

    /**
     * @notice Gets historical performance metrics
     * @return totalYieldGenerated Total yield generated since inception
     * @return averageAPY Average APY (simplified as current APY)
     * @return lastHarvestTime Timestamp of last harvest
     */
    function getPerformanceMetrics() 
        external 
        view 
        override 
        returns (uint256 totalYieldGenerated, uint256 averageAPY, uint256 lastHarvestTime) 
    {
        return (_totalRewardsHarvested, currentAPY, _lastHarvestTime);
    }

    /**
     * @notice Gets pending rewards/yield amount
     * @return pendingYield Amount of yield ready to be harvested
     */
    function getPendingYield() public view override returns (uint256 pendingYield) {
        if (_stakedAmount == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - _lastHarvestTime;
        
        // Simple calculation: (stakedAmount * APY * timeElapsed) / (10000 * secondsPerYear)
        pendingYield = (_stakedAmount * currentAPY * timeElapsed) / (10000 * SECONDS_PER_YEAR);
    }

    /**
     * @notice Compounds earned yield back into the strategy
     * @param data Additional parameters (unused)
     * @return compoundedAmount Amount that was compounded
     */
    function compound(bytes calldata data) external override onlyManager returns (uint256 compoundedAmount) {
        data; // Silence unused parameter warning
        
        compoundedAmount = getPendingYield();
        
        if (compoundedAmount > 0) {
            // Add rewards to staked amount (auto-compound)
            _stakedAmount += compoundedAmount;
            _totalRewardsHarvested += compoundedAmount;
            _lastHarvestTime = block.timestamp;

            emit RewardsCompounded(compoundedAmount);
        }
    }

    /**
     * @notice Updates the APY rate (owner only)
     * @param newAPY New APY in basis points
     */
    function updateAPY(uint256 newAPY) external onlyOwner {
        // Harvest pending rewards with old APY first
        if (_stakedAmount > 0) {
            uint256 pending = getPendingYield();
            if (pending > 0) {
                _totalRewardsHarvested += pending;
            }
        }
        
        currentAPY = newAPY;
        _lastHarvestTime = block.timestamp;
        
        emit APYUpdated(newAPY);
    }

    /**
     * @notice Gets staking information
     * @return stakedAmount Current staked amount
     * @return totalHarvested Total rewards harvested
     * @return pendingRewards Current pending rewards
     * @return apy Current APY
     */
    function getStakingInfo() 
        external 
        view 
        returns (uint256 stakedAmount, uint256 totalHarvested, uint256 pendingRewards, uint256 apy) 
    {
        return (_stakedAmount, _totalRewardsHarvested, getPendingYield(), currentAPY);
    }

    /**
     * @notice Updates staking pool address (owner only)
     * @param newStakingPool New staking pool address
     */
    function updateStakingPool(address newStakingPool) external onlyOwner {
        if (newStakingPool == address(0)) revert InvalidStakingPool();
        stakingPool = newStakingPool;
    }

    /**
     * @notice See {IERC165-supportsInterface}
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IMVSSubExtension).interfaceId ||
               interfaceId == type(IYieldExtension).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}