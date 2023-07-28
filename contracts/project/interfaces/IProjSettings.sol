pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

interface IProjSettings {
    function getNodeConsensusThreshold() external view returns (uint256);

    function getSubmitBalancesEnabled() external view returns (bool);

    function getProcessWithdrawalsEnabled() external view returns (bool);

    function getNodeFee() external view returns (uint256);

    function getNodeRefundRatio() external view returns (uint256);

    function getNodeTrustedRefundRatio() external view returns (uint256);

    function getWithdrawalCredentials() external view returns (bytes memory);

    function getSuperNodePubkeyLimit() external view returns (uint256);
}