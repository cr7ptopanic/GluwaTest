// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Gluwa is ReentrancyGuard, ERC20 {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeERC20 for IERC20;

    /// -----------------------------------------------------------------------
    /// Struct
    /// -----------------------------------------------------------------------

    /// @param trancheCount Total number of tranches
    /// @param startingTime Deposit time
    /// @param maturity Maturity
    /// @param depositAmount User deposited amount
    /// @param lockUp Bool variable if lock up or no lock up
    struct UserInfo {
        uint256 trancheCount;
        mapping(uint256 => uint256) startingTime;
        mapping(uint256 => uint256) maturity;
        mapping(uint256 => uint256) depositAmount;
        mapping(uint256 => bool) lockUp;
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    enum GluwaErrorCodes {
        INSUFFICIENT_BALANCE,
        INVALID_TRANCHE_ID,
        NOT_TIME_TO_WITHDRAW
    }

    error GluwaError(GluwaErrorCodes code);

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @dev Emits when user deposit.
    /// @param user User address
    /// @param amount Deposit amount
    /// @param lockUp Bool variable if lock up or no lock up
    /// @param maturity Maturity
    /// @param startingTime Deposit time
    /// @param trancheCount Total number of tranches
    event Deposited(
        address indexed user,
        uint256 amount,
        bool lockUp,
        uint256 maturity,
        uint256 startingTime,
        uint256 trancheCount
    );

    /// @dev Emits when user deposit.
    /// @param user User address
    /// @param trancheId Tranche Id
    /// @param reward Reward amount
    event RewardsWithdrew(
        address indexed user,
        uint256 trancheId,
        uint256 reward
    );

    /// @dev Emits when users withdraw their deposited tokens.
    /// @param user User address
    /// @param trancheId Tranche Id
    /// @param amount Amount to withdraw
    event DepositedTokensWithdrew(
        address indexed user,
        uint256 trancheId,
        uint256 amount
    );

    /// @dev Emits when users swap yDAI to DAI
    /// @param user User address
    /// @param amount Amount to swap
    event Swapped(address indexed user, uint256 amount);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice DAI which users deposit
    IERC20 public immutable DAI;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Mapping of User Info
    mapping(address => UserInfo) public userInfos;

    /* ===== INIT ===== */

    /// @dev Constructor
    /// @param _DAI Address of DAI
    constructor(address _DAI) ERC20("yDAI", "yDAI") {
        DAI = IERC20(_DAI);
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    /// @dev Deposits DAI tokesn to the contract
    /// @param _amount Amount of DAI tokens to deposit
    /// @param _maturity Maturity
    /// @param _lockUp Fixed lockup period or no-lockup period
    function deposit(
        uint256 _amount,
        uint256 _maturity,
        bool _lockUp
    ) external {
        if (_amount == 0)
            revert GluwaError(GluwaErrorCodes.INSUFFICIENT_BALANCE);

        DAI.safeTransferFrom(msg.sender, address(this), _amount);

        UserInfo storage userInfo = userInfos[msg.sender];

        userInfo.trancheCount++;
        userInfo.lockUp[userInfo.trancheCount] = _lockUp;
        userInfo.depositAmount[userInfo.trancheCount] = _amount;
        userInfo.maturity[userInfo.trancheCount] = _maturity;
        userInfo.startingTime[userInfo.trancheCount] = block.timestamp;

        emit Deposited(
            msg.sender,
            _amount,
            _lockUp,
            _maturity,
            block.timestamp,
            userInfo.trancheCount
        );
    }

    /// @dev Withdraw rewards after maturity.
    /// @param _trancheId Tranche Id
    function withdrawRewards(uint256 _trancheId) external nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];

        if (_trancheId > userInfo.trancheCount || _trancheId == 0)
            revert GluwaError(GluwaErrorCodes.INVALID_TRANCHE_ID);

        bool lockUp = userInfo.lockUp[_trancheId];
        uint256 startingTime = userInfo.startingTime[_trancheId];
        uint256 maturity = userInfo.maturity[_trancheId];
        uint256 depositAmount = userInfo.depositAmount[_trancheId];
        uint256 reward;

        if (block.timestamp < maturity + startingTime)
            revert GluwaError(GluwaErrorCodes.NOT_TIME_TO_WITHDRAW);

        if (lockUp == true) {
            reward =
                (((depositAmount * maturity) * uint256(10)**decimals()) /
                    (365 * 24 * 3600) /
                    100) *
                35;
        } else {
            reward =
                (((depositAmount * maturity) * uint256(10)**decimals()) /
                    (365 * 24 * 3600) /
                    100) *
                12;
        }

        _mint(msg.sender, reward / uint256(10)**decimals());

        emit RewardsWithdrew(msg.sender, _trancheId, reward);
    }

    /// @dev Withdraw deposited tokens.
    /// @param _amount Amount of DAI to withdraw
    /// @param _trancheId Tranche Id
    function withdrawDepositedTokens(uint256 _amount, uint256 _trancheId)
        external
        nonReentrant
    {
        UserInfo storage userInfo = userInfos[msg.sender];

        if (_trancheId > userInfo.trancheCount || _trancheId == 0)
            revert GluwaError(GluwaErrorCodes.INVALID_TRANCHE_ID);

        bool lockUp = userInfo.lockUp[_trancheId];
        uint256 startingTime = userInfo.startingTime[_trancheId];
        uint256 maturity = userInfo.maturity[_trancheId];
        uint256 depositAmount = userInfo.depositAmount[_trancheId];

        if (_amount == 0 || _amount > depositAmount)
            revert GluwaError(GluwaErrorCodes.INSUFFICIENT_BALANCE);

        userInfo.depositAmount[_trancheId] -= _amount;

        if (lockUp == true && block.timestamp < maturity + startingTime) {
            DAI.safeTransfer(
                msg.sender,
                (((_amount * uint256(10)**decimals()) / 100) * 85) /
                    uint256(10)**decimals()
            );
        } else {
            DAI.safeTransfer(msg.sender, _amount);
        }

        emit DepositedTokensWithdrew(msg.sender, _trancheId, _amount);
    }

    /// @dev Swap yDAI tokens to DAI tokens.
    /// @param _amount Amount of yDAI to swap
    function swap(uint256 _amount) external {
        if (_amount == 0 || _amount > balanceOf(msg.sender))
            revert GluwaError(GluwaErrorCodes.INSUFFICIENT_BALANCE);

        _burn(msg.sender, _amount);
        DAI.safeTransfer(msg.sender, _amount);

        emit Swapped(msg.sender, _amount);
    }
}
