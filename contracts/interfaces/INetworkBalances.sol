pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

interface INetworkBalances {
    // Events
    event BalancesSubmitted(
        address indexed from,
        uint256 block,
        uint256 totalEth,
        uint256 stakingEth,
        uint256 lsdTokenSupply,
        uint256 time
    );
    event BalancesUpdated(uint256 block, uint256 totalEth, uint256 stakingEth, uint256 lsdTokenSupply, uint256 time);

    function getBalancesBlock() external view returns (uint256);

    function getTotalETHBalance() external view returns (uint256);

    function getStakingETHBalance() external view returns (uint256);

    function getTotalLsdTokenSupply() external view returns (uint256);

    function getETHStakingRate() external view returns (uint256);

    function submitBalances(uint256 _block, uint256 _total, uint256 _staking, uint256 _lsdTokenSupply) external;
}
