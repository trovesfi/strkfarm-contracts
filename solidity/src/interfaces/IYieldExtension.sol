// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMVSSubExtension.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IYieldExtension
 * @notice Extended interface for yield-generating extensions
 * @dev Adds yield harvesting and performance tracking capabilities
 */
interface IYieldExtension is IMVSSubExtension, IERC165 {
    /**
     * @notice Harvests accumulated yield/rewards
     * @param recipient Address to receive harvested tokens
     * @param data Additional parameters for harvest operation
     * @return harvestedAmounts Array of harvested token amounts
     * @return tokens Array of harvested token addresses
     */
    function harvest(address recipient, bytes calldata data) 
        external 
        returns (uint256[] memory harvestedAmounts, address[] memory tokens);

    /**
     * @notice Gets current APY/yield rate
     * @return apy Current APY in basis points (10000 = 100%)
     */
    function getCurrentAPY() external view returns (uint256 apy);

    /**
     * @notice Gets historical performance metrics
     * @return totalYieldGenerated Total yield generated since inception
     * @return averageAPY Average APY over lifetime
     * @return lastHarvestTime Timestamp of last harvest
     */
    function getPerformanceMetrics() 
        external 
        view 
        returns (uint256 totalYieldGenerated, uint256 averageAPY, uint256 lastHarvestTime);

    /**
     * @notice Gets pending rewards/yield amount
     * @return pendingYield Amount of yield ready to be harvested
     */
    function getPendingYield() external view returns (uint256 pendingYield);

    /**
     * @notice Compounds earned yield back into the strategy
     * @param data Additional parameters for compound operation
     * @return compoundedAmount Amount that was compounded
     */
    function compound(bytes calldata data) external returns (uint256 compoundedAmount);
}