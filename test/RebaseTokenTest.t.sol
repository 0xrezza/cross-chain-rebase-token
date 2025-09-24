// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Test, console} from "forge-std/Test.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 _rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: _rewardAmount}("");
    }

    function testDepositLinear(uint256 _amount) public {
        _amount = bound(_amount, 1e6, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, _amount);
        vault.deposit{value: _amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start balance:", startBalance);
        assertEq(startBalance, _amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle balance:", middleBalance);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("End balance:", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 _amount) public {
        _amount = bound(_amount, 1e6, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, _amount);
        vault.deposit{value: _amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start balance:", startBalance);
        assertEq(startBalance, _amount);

        // vault.redeem(startBalance);
        vault.redeem(type(uint256).max);

        uint256 endBalance = address(user).balance;
        console.log("End balance:", endBalance);
        assertEq(endBalance, _amount);

        uint256 finalTokenBalance = rebaseToken.balanceOf(user);
        console.log("Final token balance:", finalTokenBalance);
        assertEq(finalTokenBalance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 _amount, uint256 _timePassed) public {
        _amount = bound(_amount, 1e5, type(uint32).max);
        _timePassed = bound(_timePassed, 1000, type(uint32).max);

        vm.startPrank(user);
        vm.deal(user, _amount);
        vault.deposit{value: _amount}();
        vm.stopPrank();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start balance:", startBalance);
        assertEq(startBalance, _amount);

        vm.warp(block.timestamp + _timePassed);

        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle balance:", middleBalance);
        assertGt(middleBalance, startBalance);

        vm.deal(owner, middleBalance - _amount);
        vm.prank(owner);
        addRewardsToVault(middleBalance - _amount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 endBalance = address(user).balance;
        console.log("End balance:", endBalance);
        assertGt(endBalance, _amount);

        uint256 finalTokenBalance = rebaseToken.balanceOf(user);
        console.log("Final token balance:", finalTokenBalance);
        assertEq(finalTokenBalance, 0);
    }
}
