pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

import "./interfaces/IFeePool.sol";

// receive priority fee
contract FeePool is IFeePool {
    address public distributorAddress;

    // Events
    event EtherWithdrawn(address indexed to, uint256 amount, uint256 time);

    // Allow receiving ETH
    receive() external payable {}

    // Withdraws ETH to given address
    // Only accepts calls from network contracts
    function withdrawEther(address _to, uint256 _amount) external override {
        require(_amount > 0, "No valid amount of ETH given to withdraw");
        require(msg.sender == distributorAddress, "not allowed sender");
        // Send the ETH
        (bool result, ) = distributorAddress.call{value: _amount}("");

        require(result, "Failed to withdraw ETH");

        // Emit ether withdrawn event
        emit EtherWithdrawn(_to, _amount, block.timestamp);
    }
}