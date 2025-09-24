// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRebaseToken {
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address _user) external view returns (uint256);
}
