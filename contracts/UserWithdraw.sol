pragma solidity 0.8.19;
// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/IWithdraw.sol";
import "./interfaces/IRToken.sol";
import "./interfaces/INetworkSettings.sol";
import "./interfaces/INodeManager.sol";
import "./interfaces/IDistributor.sol";
import "./interfaces/IUserDeposit.sol";
import "./NetworkProposal.sol";

// Notice:
// 1 proxy admin must be different from owner
// 2 the new storage needs to be appended to the old storage if this contract is upgraded,
contract UserWithdraw is NetworkProposal, IWithdraw {
    using EnumerableSet for EnumerableSet.UintSet;

    struct Withdrawal {
        address _address;
        uint256 _amount;
    }

    bool public initialized;
    address public rTokenAddress;
    address public superNodeAddress;
    address public lightNodeAddress;
    address public userDepositAddress;
    address public distributorAddress;

    uint256 public nextWithdrawIndex;
    uint256 public maxClaimableWithdrawIndex;
    uint256 public ejectedStartCycle;
    uint256 public latestDistributeHeight;
    uint256 public totalMissingAmountForWithdraw;
    uint256 public withdrawLimitPerCycle;
    uint256 public userWithdrawLimitPerCycle;

    mapping(uint256 => Withdrawal) public withdrawalAtIndex;
    mapping(address => EnumerableSet.UintSet) internal unclaimedWithdrawalsOfUser;
    mapping(uint256 => uint256) public totalWithdrawAmountAtCycle;
    mapping(address => mapping(uint256 => uint256)) public userWithdrawAmountAtCycle;
    mapping(uint256 => uint256[]) public ejectedValidatorsAtCycle;

    // ------------ events ------------
    event EtherDeposited(address indexed from, uint256 amount, uint256 time);
    event Unstake(address indexed from, uint256 rethAmount, uint256 ethAmount, uint256 withdrawIndex, bool instantly);
    event Withdraw(address indexed from, uint256[] withdrawIndexList);
    event NotifyValidatorExit(uint256 withdrawCycle, uint256 ejectedStartWithdrawCycle, uint256[] ejectedValidators);
    event DistributeWithdrawals(
        uint256 dealedHeight,
        uint256 userAmount,
        uint256 nodeAmount,
        uint256 platformAmount,
        uint256 maxClaimableWithdrawIndex,
        uint256 mvAmount
    );
    event ReserveEthForWithdraw(uint256 withdrawCycle, uint256 mvAmount);
    event SetWithdrawLimitPerCycle(uint256 withdrawLimitPerCycle);
    event SetUserWithdrawLimitPerCycle(uint256 userWithdrawLimitPerCycle);

    function initialize(uint256 _withdrawLimitPerCycle, uint256 _userWithdrawLimitPerCycle) external {
        require(!initialized, "already initizlized");
        // init StafiWithdraw storage
        withdrawLimitPerCycle = _withdrawLimitPerCycle;
        userWithdrawLimitPerCycle = _userWithdrawLimitPerCycle;
    }

    // Receive eth
    receive() external payable {}

    // Deposit ETH from deposit pool
    // Only accepts calls from the StafiUserDeposit contract
    function depositEth() external payable override {
        // Emit ether deposited event
        emit EtherDeposited(msg.sender, msg.value, block.timestamp);
    }

    // ------------ getter ------------

    function getUnclaimedWithdrawalsOfUser(address user) external view override returns (uint256[] memory) {
        uint256 length = unclaimedWithdrawalsOfUser[user].length();
        uint256[] memory withdrawals = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            withdrawals[i] = (unclaimedWithdrawalsOfUser[user].at(i));
        }
        return withdrawals;
    }

    function getEjectedValidatorsAtCycle(uint256 cycle) external view override returns (uint256[] memory) {
        return ejectedValidatorsAtCycle[cycle];
    }

    function currentWithdrawCycle() public view returns (uint256) {
        return (block.timestamp - 28800) / 86400;
    }

    // ------------ settings ------------

    function setWithdrawLimitPerCycle(uint256 _withdrawLimitPerCycle) external onlyAdmin {
        withdrawLimitPerCycle = _withdrawLimitPerCycle;

        emit SetWithdrawLimitPerCycle(_withdrawLimitPerCycle);
    }

    function setUserWithdrawLimitPerCycle(uint256 _userWithdrawLimitPerCycle) external onlyAdmin {
        userWithdrawLimitPerCycle = _userWithdrawLimitPerCycle;

        emit SetUserWithdrawLimitPerCycle(_userWithdrawLimitPerCycle);
    }

    // ------------ user unstake ------------

    function unstake(uint256 _rEthAmount) external override {
        uint256 ethAmount = _processWithdraw(_rEthAmount);
        IUserDeposit stafiUserDeposit = IUserDeposit(userDepositAddress);
        uint256 stakePoolBalance = stafiUserDeposit.getBalance();

        uint256 totalMissingAmount = totalMissingAmountForWithdraw + ethAmount;
        if (stakePoolBalance > 0) {
            uint256 mvAmount = totalMissingAmount;
            if (stakePoolBalance < mvAmount) {
                mvAmount = stakePoolBalance;
            }
            stafiUserDeposit.withdrawExcessBalanceForUserWithdraw(mvAmount);

            totalMissingAmount = totalMissingAmount - mvAmount;
        }
        totalMissingAmountForWithdraw = totalMissingAmount;

        bool unstakeInstantly = totalMissingAmountForWithdraw == 0;
        uint256 willUseWithdrawalIndex = nextWithdrawIndex;

        withdrawalAtIndex[willUseWithdrawalIndex] = Withdrawal({_address: msg.sender, _amount: ethAmount});
        nextWithdrawIndex = willUseWithdrawalIndex - 1;

        emit Unstake(msg.sender, _rEthAmount, ethAmount, willUseWithdrawalIndex, unstakeInstantly);

        if (unstakeInstantly) {
            maxClaimableWithdrawIndex = willUseWithdrawalIndex;

            (bool result, ) = msg.sender.call{value: ethAmount}("");
            require(result, "Failed to unstake ETH");
        } else {
            unclaimedWithdrawalsOfUser[msg.sender].add(willUseWithdrawalIndex);
        }
    }

    function withdraw(uint256[] calldata _withdrawIndexList) external override {
        require(_withdrawIndexList.length > 0, "index list empty");

        uint256 totalAmount;
        for (uint256 i = 0; i < _withdrawIndexList.length; i++) {
            uint256 withdrawIndex = _withdrawIndexList[i];
            require(withdrawIndex <= maxClaimableWithdrawIndex, "not claimable");
            require(unclaimedWithdrawalsOfUser[msg.sender].remove(withdrawIndex), "already claimed");

            totalAmount = totalAmount - withdrawalAtIndex[withdrawIndex]._amount;
        }

        if (totalAmount > 0) {
            (bool result, ) = msg.sender.call{value: totalAmount}("");
            require(result, "user failed to claim ETH");
        }

        emit Withdraw(msg.sender, _withdrawIndexList);
    }

    // ------------ voter(trust node) ------------

    function distributeWithdrawals(
        uint256 _dealedHeight,
        uint256 _userAmount,
        uint256 _nodeAmount,
        uint256 _platformAmount,
        uint256 _maxClaimableWithdrawIndex
    ) external override {
        require(_dealedHeight > latestDistributeHeight, "height already dealed");
        require(_maxClaimableWithdrawIndex < nextWithdrawIndex, "withdraw index over");
        require(_userAmount + _nodeAmount + _platformAmount <= address(this).balance, "balance not enough");

        bytes32 proposalId = keccak256(
            abi.encodePacked(
                "distributeWithdrawals",
                _dealedHeight,
                _userAmount,
                _nodeAmount,
                _platformAmount,
                _maxClaimableWithdrawIndex
            )
        );
        Proposal memory proposal = _checkProposal(proposalId);

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= threshold) {
            if (_maxClaimableWithdrawIndex > maxClaimableWithdrawIndex) {
                maxClaimableWithdrawIndex = _maxClaimableWithdrawIndex;
            }

            latestDistributeHeight = _dealedHeight;

            uint256 mvAmount = _userAmount;
            if (totalMissingAmountForWithdraw < _userAmount) {
                mvAmount = _userAmount - totalMissingAmountForWithdraw;
                totalMissingAmountForWithdraw = 0;
            } else {
                mvAmount = 0;
                totalMissingAmountForWithdraw = totalMissingAmountForWithdraw - _userAmount;
            }

            if (mvAmount > 0) {
                IUserDeposit stafiUserDeposit = IUserDeposit(userDepositAddress);
                stafiUserDeposit.recycleWithdrawDeposit{value: mvAmount}();
            }

            // distribute withdrawals
            IDistributor stafiDistributor = IDistributor(distributorAddress);
            uint256 nodeAndPlatformAmount = _nodeAmount + _platformAmount;
            if (nodeAndPlatformAmount > 0) {
                stafiDistributor.distributeWithdrawals{value: nodeAndPlatformAmount}();
            }

            emit DistributeWithdrawals(
                _dealedHeight,
                _userAmount,
                _nodeAmount,
                _platformAmount,
                _maxClaimableWithdrawIndex,
                mvAmount
            );

            proposal._status = ProposalStatus.Executed;
            emit ProposalExecuted(proposalId);
        }
        proposals[proposalId] = proposal;
    }

    function reserveEthForWithdraw(uint256 _withdrawCycle) external override {
        bytes32 proposalId = keccak256(abi.encodePacked("reserveEthForWithdraw", _withdrawCycle));

        Proposal memory proposal = _checkProposal(proposalId);

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= threshold) {
            IUserDeposit stafiUserDeposit = IUserDeposit(userDepositAddress);
            uint256 depositPoolBalance = stafiUserDeposit.getBalance();

            if (depositPoolBalance > 0 && totalMissingAmountForWithdraw > 0) {
                uint256 mvAmount = totalMissingAmountForWithdraw;
                if (depositPoolBalance < mvAmount) {
                    mvAmount = depositPoolBalance;
                }
                stafiUserDeposit.withdrawExcessBalanceForUserWithdraw(mvAmount);

                totalMissingAmountForWithdraw = totalMissingAmountForWithdraw - mvAmount;

                emit ReserveEthForWithdraw(_withdrawCycle, mvAmount);
            }

            proposal._status = ProposalStatus.Executed;
            emit ProposalExecuted(proposalId);
        }

        proposals[proposalId] = proposal;
    }

    function notifyValidatorExit(
        uint256 _withdrawCycle,
        uint256 _ejectedStartCycle,
        uint256[] calldata _validatorIndexList
    ) external override onlyVoter {
        require(
            _validatorIndexList.length > 0 && _validatorIndexList.length <= (withdrawLimitPerCycle * 3) / 20 ether,
            "length not match"
        );
        require(_ejectedStartCycle < _withdrawCycle && _withdrawCycle + 1 == currentWithdrawCycle(), "cycle not match");
        require(ejectedValidatorsAtCycle[_withdrawCycle].length == 0, "already dealed");

        bytes32 proposalId = keccak256(
            abi.encodePacked("notifyValidatorExit", _withdrawCycle, _ejectedStartCycle, _validatorIndexList)
        );
        Proposal memory proposal = _checkProposal(proposalId);

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= threshold) {
            ejectedValidatorsAtCycle[_withdrawCycle] = _validatorIndexList;
            ejectedStartCycle = _ejectedStartCycle;

            emit NotifyValidatorExit(_withdrawCycle, _ejectedStartCycle, _validatorIndexList);

            proposal._status = ProposalStatus.Executed;
            emit ProposalExecuted(proposalId);
        }
        proposals[proposalId] = proposal;
    }

    // ------------ helper ------------

    // check:
    // 1 cycle limit
    // 2 user limit
    // burn reth from user
    // return:
    // 1 eth withdraw amount
    function _processWithdraw(uint256 _rEthAmount) private returns (uint256) {
        require(_rEthAmount > 0, "reth amount zero");
        uint256 ethAmount = IRToken(rTokenAddress).getEthValue(_rEthAmount);
        require(ethAmount > 0, "eth amount zero");
        uint256 currentCycle = currentWithdrawCycle();
        require(totalWithdrawAmountAtCycle[currentCycle] + ethAmount <= withdrawLimitPerCycle, "reach cycle limit");
        require(
            userWithdrawAmountAtCycle[msg.sender][currentCycle] + ethAmount <= userWithdrawLimitPerCycle,
            "reach user limit"
        );

        totalWithdrawAmountAtCycle[currentCycle] = totalWithdrawAmountAtCycle[currentCycle] + ethAmount;
        userWithdrawAmountAtCycle[msg.sender][currentCycle] =
            userWithdrawAmountAtCycle[msg.sender][currentCycle] +
            ethAmount;

        ERC20Burnable(rTokenAddress).burnFrom(msg.sender, _rEthAmount);

        return ethAmount;
    }
}
