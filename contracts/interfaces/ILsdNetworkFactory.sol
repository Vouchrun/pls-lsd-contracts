pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only
import "./Errors.sol";

interface ILsdNetworkFactory is Errors {
    struct NetworkContracts {
        address _feePool;
        address _networkBalances;
        address _networkProposal;
        address _nodeDeposit;
        address _userDeposit;
        address _networkWithdraw;
        address _lsdToken;
        uint256 _block;
    }

    event LsdNetwork(NetworkContracts contracts);

    function createLsdNetwork(
        string memory _lsdTokenName,
        string memory _lsdTokenSymbol,
        address _networkAdmin,
        address[] memory _voters,
        uint256 _threshold
    ) external;

    function createLsdNetworkWithTimelock(
        string memory _lsdTokenName,
        string memory _lsdTokenSymbol,
        address[] memory _voters,
        uint256 _threshold,
        uint256 minDelay,
        address[] memory proposers
    ) external;
}
