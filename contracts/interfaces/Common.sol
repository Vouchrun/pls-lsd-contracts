pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

interface Common {
    function reinit() external;

    function version() external returns (uint8);
}