pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

interface INetworkWithdraw {
    enum ClaimType {
        None,
        ClaimReward,
        ClaimDeposit,
        ClaimTotal
    }

    enum DistributeType {
        None,
        DistributeWithdrawals,
        DistributePriorityFee
    }

    event NodeClaimed(
        uint256 index,
        address account,
        uint256 claimableReward,
        uint256 claimableDeposit,
        ClaimType claimType
    );

    struct Withdrawal {
        address _address;
        uint256 _amount;
    }

    event SetWithdrawLimitPerCycle(uint256 _withdrawLimitPerCycle);
    event SetUserWithdrawLimitPerCycle(uint256 _userWithdrawLimitPerCycle);
    event SetWithdrawCycleSeconds(uint256 _seconds);
    event SetMerkleRoot(uint256 dealedEpoch, bytes32 merkleRoot);
    event EtherDeposited(address indexed _from, uint256 _amount, uint256 _time);
    event Unstake(
        address indexed _from,
        uint256 _lsdTokenAmount,
        uint256 _ethAmount,
        uint256 _withdrawIndex,
        bool _instantly
    );
    event Withdraw(address indexed _from, uint256[] _withdrawIndexList);
    event DistributeRewards(
        DistributeType _distributeType,
        uint256 _dealedHeight,
        uint256 _userAmount,
        uint256 _nodeAmount,
        uint256 _platformAmount,
        uint256 _maxClaimableWithdrawIndex,
        uint256 _mvAmount
    );
    event NotifyValidatorExit(uint256 _withdrawCycle, uint256 _ejectedStartWithdrawCycle, uint256[] _ejectedValidators);

    function init(
        address _lsdTokenAddress,
        address _userDepositAddress,
        address _networkProposalAddress,
        address _feePoolAddress,
        address _factoryAddress
    ) external;

    // getter
    function getUnclaimedWithdrawalsOfUser(address user) external view returns (uint256[] memory);

    function getEjectedValidatorsAtCycle(uint256 cycle) external view returns (uint256[] memory);

    function totalMissingAmountForWithdraw() external view returns (uint256);

    // user
    function unstake(uint256 _lsdTokenAmount) external;

    function withdraw(uint256[] calldata _withdrawIndexList) external;

    // ejector
    function notifyValidatorExit(
        uint256 _withdrawCycle,
        uint256 _ejectedStartWithdrawCycle,
        uint256[] calldata _validatorIndex
    ) external;

    // voter
    function distribute(
        DistributeType _distributeType,
        uint256 _dealedHeight,
        uint256 _userAmount,
        uint256 _nodeAmount,
        uint256 _platformAmount,
        uint256 _maxClaimableWithdrawIndex
    ) external;

    function depositEth() external payable;
}