// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMVSSubExtension
 * @notice Interface for MVS (Multi-Vault Strategy) Sub Extensions
 * @dev Extensions are modular components that can be managed by the MVSManager
 */
interface IMVSSubExtension {
    /**
     * @notice Returns the total assets managed by this extension
     * @dev Must return value denominated in the manager's base asset
     * @return Total asset value managed by this extension
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the underlying asset token address
     * @return Address of the underlying asset token
     */
    function asset() external view returns (address);

    /**
     * @notice Pushes assets from manager to extension
     * @param amount Amount of assets to push to extension
     * @param data Additional data for the push operation
     * @return success Whether the push was successful
     */
    function pushAssets(uint256 amount, bytes calldata data) external returns (bool success);

    /**
     * @notice Pulls assets from extension back to manager
     * @param amount Amount of assets to pull from extension
     * @param data Additional data for the pull operation
     * @return success Whether the pull was successful
     */
    function pullAssets(uint256 amount, bytes calldata data) external returns (bool success);

    /**
     * @notice Gets the maximum amount that can be pushed to this extension
     * @return Maximum pushable amount
     */
    function maxPush() external view returns (uint256);

    /**
     * @notice Gets the maximum amount that can be pulled from this extension
     * @return Maximum pullable amount
     */
    function maxPull() external view returns (uint256);

    /**
     * @notice Emergency withdrawal function
     * @dev Should only be callable by manager in emergency situations
     * @return Amount withdrawn
     */
    function emergencyWithdraw() external returns (uint256);

    /**
     * @notice Returns the extension's identifier/name
     * @return Extension identifier
     */
    function extensionId() external pure returns (string memory);
}