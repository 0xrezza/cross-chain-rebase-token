// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Reza Ghoreyshi
 * @notice This is a cross-chain rebase token that encourages users to deposit into vault and gain interest in reward.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate based on their deposit time
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldRate, uint256 newRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastUpdatedTimestamp) private s_userLastUpdatedTimestamp;

    event InterestRateChanged(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    /**
     * @notice Grant the mint and burn role to an account
     * @param _account The address to grant the mint and burn role to
     * @dev Only the owner can grant the mint and burn role
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateChanged(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user without the interest that has accumulated since the last update
     * @param _user The address of the user
     * @return The principle balance of the user without the interest that has accumulated since the last update
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     * @dev When minting, we need to update the user's interest rate and last updated timestamp
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn
     * @dev If the amount is max uint256, burn the entire balance of the user
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculate the balance of the user including the interest that has accumulated since the last update
     * @param _user The address of the user
     * @return The balance of the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from the sender to the recipient
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount of tokens to transfer
     * @dev If the amount is max uint256, transfer the entire balance of the sender
     * @dev Update the interest for both the sender and the recipient before transferring
     * @dev If the recipient has no balance, set their interest rate to the sender's interest rate
     * @return A boolean value indicating whether the operation succeeded
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one address to another
     * @param _sender The address to transfer tokens from
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount of tokens to transfer
     * @dev If the amount is max uint256, transfer the entire balance of the sender
     * @dev Update the interest for both the sender and the recipient before transferring
     * @dev If the recipient has no balance, set their interest rate to the sender's interest rate
     * @return A boolean value indicating whether the operation succeeded
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest for
     * @return linearInterest The interest that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        uint256 interestRate = s_userInterestRate[_user];
        linearInterest = (interestRate * timeElapsed) + PRECISION_FACTOR;
        return linearInterest;
    }

    /**
     * @notice Mint the accrued interest to the user
     * @param _user The address of the user
     * @dev Mint the accrued interest to the user and update the last updated timestamp
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;

        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the interest rate of the user
     * @param _user The address of the user
     * @return userInterestRate The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256 userInterestRate) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the global interest rate of the contract
     * @return The global interest rate of the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
