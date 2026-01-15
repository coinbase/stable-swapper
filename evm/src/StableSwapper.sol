// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title StableSwapper
/// @notice A 1:1 stablecoin swap contract with decimal normalization and role-based access control
///
/// @dev This contract enables swapping between stablecoins with different decimal places (6-18 decimals).
/// @dev It implements UUPS upgradeability pattern and uses role-based access control for administration.
/// @dev The contract supports three main feature flags: SWAP, WITHDRAW, and ALLOWLIST.
///
/// @dev Roles:
/// @dev - DEFAULT_ADMIN_ROLE: Can authorize upgrades and manage all other roles (single holder, 2-step transfer)
/// @dev - WITHDRAW_ROLE: Can withdraw liquidity (treasury) and update reserved amounts
/// @dev - CONFIGURE_ROLE: Can add/remove tokens, update fees, and manage allowlist
/// @dev - PAUSE_ROLE: Can pause/unpause swap and withdraw operations, and enable/disable individual tokens
///
/// @author Coinbase
contract StableSwapper is
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Feature flags for contract functionality
    enum FeatureFlag {
        SWAP,
        WITHDRAW,
        ALLOWLIST
    }

    /// @notice Fee denominator for basis points calculation (100% = 10000 basis points)
    uint16 public constant FEE_DENOMINATOR = 10000;

    /// @notice Role identifier for withdrawal role
    ///
    /// @dev Can withdraw liquidity (treasury operations) and update reserved amounts
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    /// @notice Role identifier for pause role
    ///
    /// @dev Can pause/unpause swaps and liquidity operations, and enable/disable individual tokens
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice Role identifier for configure role
    ///
    /// @dev Can add/remove tokens, update fee configuration, and manage allowlist
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant CONFIGURE_ROLE = keccak256("CONFIGURE_ROLE");

    /// @custom:storage-location erc7201:coinbase.storage.StableSwapper
    struct StableSwapperStorage {
        /// @dev Version number of the contract implementation
        uint8 contractVersion;
        /// @dev Set of addresses for tokens listed in this contract
        EnumerableSet.AddressSet listedTokens;
        /// @dev Mapping from token address to reserved amount (not available for withdrawal by swaps)
        mapping(address => uint256) reservedAmounts;
        /// @dev Mapping from token address to swappable status
        mapping(address => bool) tokenSwappable;
        /// @dev Address that receives fees collected from swaps
        address feeRecipient;
        /// @dev Current fee in basis points (e.g., 100 = 1%)
        uint16 feeBasisPoints;
        /// @dev Mapping of addresses allowed to initiate swaps when allowlist feature is enabled
        mapping(address account => bool allowed) allowlist;
        /// @dev Mapping of feature flags to their enabled status
        mapping(FeatureFlag => bool) featureFlags;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.StableSwapper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STABLE_SWAPPER_STORAGE_LOCATION =
        0xf2e0b1cd22eafe6a81cc5537d51093af5e5b8419839ce4a86b767790e5c10000;

    /// @notice Emitted when the contract is initialized with initial roles and fee configuration
    ///
    /// @dev DEFAULT_ADMIN_ROLE can grant/revoke other roles after initialization
    ///
    /// @param defaultAdmin Address granted the DEFAULT_ADMIN_ROLE (only role that can manage other roles)
    /// @param withdrawalAuthority Initial address granted the WITHDRAW_ROLE
    /// @param configureAuthority Initial address granted the CONFIGURE_ROLE
    /// @param pauseAuthority Initial address granted the PAUSE_ROLE
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeBasisPoints Initial fee in basis points (e.g., 100 = 1%)
    event Initialized(
        address defaultAdmin,
        address withdrawalAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint16 initialFeeBasisPoints
    );

    /// @notice Emitted when a new token is listed in the contract
    /// @param token Address of the token that was listed
    event TokenListed(address indexed token);

    /// @notice Emitted when a token is unlisted from the contract
    /// @param token Address of the token that was unlisted
    event TokenUnlisted(address indexed token);

    /// @notice Emitted when a swap is executed
    ///
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens provided (before fees)
    /// @param amountOut Amount of output tokens sent to recipient (after decimal normalization)
    /// @param fee Fee amount collected in input token
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 fee);

    /// @notice Emitted when liquidity is withdrawn from a token vault
    ///
    /// @param token Address of the token that was withdrawn
    /// @param recipient Address that received the withdrawn tokens
    /// @param amount Amount of tokens withdrawn
    event LiquidityWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when the fee recipient address is updated
    /// @param newFeeRecipient New address that will receive swap fees
    event FeeRecipientUpdated(address newFeeRecipient);

    /// @notice Emitted when the fee is updated
    /// @param newFeeBasisPoints New fee in basis points (e.g., 100 = 1%)
    event FeeUpdated(uint16 newFeeBasisPoints);

    /// @notice Emitted when a feature flag is updated
    ///
    /// @param feature The feature that was updated
    /// @param isEnabled True if the feature is enabled, false if disabled
    event FeatureFlagUpdated(FeatureFlag indexed feature, bool isEnabled);

    /// @notice Emitted when a token's reserved amount is updated
    ///
    /// @param token Address of the token whose reserved amount was updated
    /// @param newReservedAmount New reserved amount (cannot be withdrawn from liquidity)
    event ReservedAmountUpdated(address indexed token, uint256 newReservedAmount);

    /// @notice Emitted when a token's swappable status is updated
    ///
    /// @param token Address of the token whose status was updated
    /// @param isSwappable True if token is swappable, false if disabled
    event TokenStatusUpdated(address indexed token, bool isSwappable);

    /// @notice Emitted when an address is added to the allowlist
    /// @param addr Address that was added to the allowlist
    event AllowlistAddressAdded(address addr);

    /// @notice Emitted when an address is removed from the allowlist
    /// @param addr Address that was removed from the allowlist
    event AllowlistAddressRemoved(address addr);

    /// @notice Thrown when an address parameter is the zero address
    error CannotBeZeroAddress();

    /// @notice Thrown when attempting to list a token that is already listed
    error TokenAlreadyListed(address token);

    /// @notice Thrown when attempting an operation on a token that is not listed
    error TokenNotListed(address token);

    /// @notice Thrown when attempting to swap a token for itself
    error CannotSwapSameToken(address token);

    /// @notice Thrown when attempting to unlist a token that is still swappable
    error TokenMustNotBeSwappable(address token);

    /// @notice Thrown when an amount parameter is zero
    error CannotBeZeroAmount();

    /// @notice Thrown when the output amount is less than the minimum acceptable amount (slippage protection)
    error SlippageExceeded();

    /// @notice Thrown when a swap would result in zero output tokens
    error AmountOutCannotBeZero();

    /// @notice Thrown when the token out balance is less than the reserved amount
    error TokenOutBalanceLessThanReservedAmount(address token);

    /// @notice Thrown when the swap output amount exceeds available liquidity
    error AmountOutExceedsAvailableLiquidity(uint256 amountOut, uint256 availableLiquidity);

    /// @notice Thrown when attempting to withdraw liquidity while the withdraw feature is disabled
    error WithdrawalCannotBePaused();

    /// @notice Thrown when attempting to swap while the swap feature is disabled
    error SwapsCannotBePaused();

    /// @notice Thrown when attempting to swap with a token that is not swappable
    error TokenMustBeSwappable(address token);

    /// @notice Thrown when attempting to set a reserved amount greater than the token balance
    error ReservedAmountExceedsBalance(address token, uint256 reservedAmount, uint256 balance);

    /// @notice Thrown when attempting to add an address that is already in the allowlist
    error AddressAlreadyInAllowlist(address addr);

    /// @notice Thrown when attempting an operation on an address that is not in the allowlist
    error AddressNotInAllowlist(address addr);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the StableSwapper contract with roles and fee configuration
    ///
    /// @dev DEFAULT_ADMIN_ROLE uses a 2-step transfer process and can only be held by one address at a time
    /// @dev DEFAULT_ADMIN_ROLE is the only role that can grant/revoke other roles
    /// @dev Other roles (WITHDRAW_ROLE, CONFIGURE_ROLE, PAUSE_ROLE) can have multiple holders
    ///
    /// @param defaultAdmin Address granted DEFAULT_ADMIN_ROLE (can authorize UUPS upgrades and grant/revoke all other roles)
    /// @param withdrawalAuthority Initial address granted WITHDRAW_ROLE (can withdraw liquidity for treasury and update reserved amounts)
    /// @param configureAuthority Initial address granted CONFIGURE_ROLE (can add/remove tokens, update fees, manage allowlist)
    /// @param pauseAuthority Initial address granted PAUSE_ROLE (can pause/unpause operations and enable/disable tokens)
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeBasisPoints Initial fee in basis points (e.g., 100 = 1%)
    /// @param initialAdminTransferDelay Delay in seconds for 2-step DEFAULT_ADMIN_ROLE transfers (security feature)
    function initialize(
        address defaultAdmin,
        address withdrawalAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint16 initialFeeBasisPoints,
        uint48 initialAdminTransferDelay
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialAdminTransferDelay, defaultAdmin);

        _grantRole(WITHDRAW_ROLE, withdrawalAuthority);
        _grantRole(CONFIGURE_ROLE, configureAuthority);
        _grantRole(PAUSE_ROLE, pauseAuthority);

        StableSwapperStorage storage $ = _stableSwapperStorage();
        $.feeRecipient = initialFeeRecipient;
        $.feeBasisPoints = initialFeeBasisPoints;
        $.featureFlags[FeatureFlag.SWAP] = true;
        $.featureFlags[FeatureFlag.WITHDRAW] = true;
        $.featureFlags[FeatureFlag.ALLOWLIST] = false;
        $.contractVersion = 1;

        emit Initialized(
            defaultAdmin,
            withdrawalAuthority,
            configureAuthority,
            pauseAuthority,
            initialFeeRecipient,
            initialFeeBasisPoints
        );
    }

    /// @notice Swaps one stablecoin for another with automatic decimal normalization and fee deduction
    ///
    /// @param tokenIn Address of the token being swapped from
    /// @param tokenOut Address of the token being swapped to
    /// @param amountIn Amount of tokenIn to swap (before fees)
    /// @param minAmountOut Minimum acceptable amount of tokenOut to receive (for slippage protection)
    /// @param recipient Address that will receive the output tokens
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        nonReentrant
    {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        // CHECKS: All validation and calculations
        require($.featureFlags[FeatureFlag.SWAP], SwapsCannotBePaused());
        require(tokenIn != address(0), CannotBeZeroAddress());
        require(tokenOut != address(0), CannotBeZeroAddress());
        require(tokenIn != tokenOut, CannotSwapSameToken(tokenIn));
        require($.listedTokens.contains(tokenIn), TokenNotListed(tokenIn));
        require($.listedTokens.contains(tokenOut), TokenNotListed(tokenOut));
        require(amountIn > 0, CannotBeZeroAmount());
        require(minAmountOut > 0, CannotBeZeroAmount());

        // We only check that the initiator is in the allowlist if allowlist is enabled
        // The recipient does not need to be in the allowlist
        if ($.featureFlags[FeatureFlag.ALLOWLIST]) {
            require($.allowlist[msg.sender], AddressNotInAllowlist(msg.sender));
        }

        require($.tokenSwappable[tokenIn], TokenMustBeSwappable(tokenIn));
        require($.tokenSwappable[tokenOut], TokenMustBeSwappable(tokenOut));

        // Fee Model: Fee is charged on INPUT token
        // Example: User swaps 100 USDC → USDT with 1% fee
        //   - User provides: 100 USDC total
        //   - Contract receives: 100 USDC
        //   - fee_recipient receives: 1 USDC (protocol fee)
        //   - User receives: 99 USDT (1:1 swap of net amount, normalized for decimals)

        // Force rounding up to collect full fee amount by adding `FEE_DENOMINATOR - 1` to numerator
        uint256 amountInAfterFee = amountIn;
        uint256 fee = 0;
        if ($.feeBasisPoints > 0) {
            fee = (amountIn * $.feeBasisPoints + FEE_DENOMINATOR - 1) / FEE_DENOMINATOR;
            amountInAfterFee -= fee;
        }

        // Get decimals directly from tokens to avoid desync risk
        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
        uint256 amountOut = _normalizeDecimals(amountInAfterFee, decimalsIn, decimalsOut);

        require(amountOut > 0, AmountOutCannotBeZero());

        // Slippage protection: ensure normalized output meets user's minimum acceptable amount
        require(amountOut >= minAmountOut, SlippageExceeded());

        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(address(this));

        // Prevent underflow, there is no available liquidity if the token out balance is less than the reserved amount
        require($.reservedAmounts[tokenOut] <= tokenOutBalance, TokenOutBalanceLessThanReservedAmount(tokenOut));

        uint256 availableLiquidity = tokenOutBalance - $.reservedAmounts[tokenOut];
        require(amountOut <= availableLiquidity, AmountOutExceedsAvailableLiquidity(amountOut, availableLiquidity));

        // Step 1: Transfer the full amount in to the vaultIn from sender
        // This gets added to the pool's liquidity for the input token
        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

        // Step 2: Transfer the fee to the fee recipient
        if (fee > 0) {
            SafeERC20.safeTransfer(IERC20(tokenIn), $.feeRecipient, fee);
        }

        // Step 3: Transfer the amount out to the recipient
        SafeERC20.safeTransfer(IERC20(tokenOut), recipient, amountOut);

        emit Swap(tokenIn, tokenOut, amountIn, amountOut, fee);
    }

    // External functions
    /// @notice Lists a token in the contract for swapping.  Listed tokens can be paused via the `updateTokenStatus` function.
    ///
    /// @param token Address of the ERC20 token to list (must have 6-18 decimals)
    function listToken(address token) external onlyRole(CONFIGURE_ROLE) nonReentrant {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require(!$.listedTokens.contains(token), TokenAlreadyListed(token));

        $.listedTokens.add(token);
        $.tokenSwappable[token] = false;
        $.reservedAmounts[token] = 0;
        emit TokenListed(token);
    }

    /// @notice Unlists a token from the list of supported tokens. Tokens must be paused and have zero balance.
    ///
    /// @param token Address of the token to unlist
    function unlistToken(address token) external onlyRole(CONFIGURE_ROLE) nonReentrant {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require($.listedTokens.contains(token), TokenNotListed(token));

        // Safety check: token must not be swappable
        // This prevents accidental unlisting of active trading pairs
        require(!$.tokenSwappable[token], TokenMustNotBeSwappable(token));

        $.listedTokens.remove(token);
        delete $.tokenSwappable[token];
        delete $.reservedAmounts[token];
        emit TokenUnlisted(token);
    }

    /// @notice Updates the swappable status of a token
    ///
    /// @param token Address of the token
    /// @param isSwappable True to enable swapping, false to disable
    function updateTokenStatus(address token, bool isSwappable) external onlyRole(PAUSE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require($.listedTokens.contains(token), TokenNotListed(token));
        $.tokenSwappable[token] = isSwappable;
        emit TokenStatusUpdated(token, isSwappable);
    }

    /// @notice Withdraws liquidity from the contract for a specific token
    ///
    /// @dev Only callable by address with WITHDRAW_ROLE
    /// @dev Withdrawal role (treasury) can withdraw regardless of reserved amount (reserved amount only restricts swaps)
    ///
    /// @param token Address of the token to withdraw
    /// @param recipient Address to receive the withdrawn tokens
    /// @param amount Amount of tokens to withdraw
    function withdrawLiquidity(address token, address recipient, uint256 amount)
        external
        onlyRole(WITHDRAW_ROLE)
        nonReentrant
    {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require(recipient != address(0), CannotBeZeroAddress());
        require($.featureFlags[FeatureFlag.WITHDRAW], WithdrawalCannotBePaused());
        require($.listedTokens.contains(token), TokenNotListed(token));
        require(amount > 0, CannotBeZeroAmount());

        // Note: WITHDRAW_ROLE can withdraw regardless of reserved amount
        // Reserved amount is meant to protect swap users, not restrict withdrawal role
        // This allows treasury (withdrawal role) to manage liquidity in emergency situations
        SafeERC20.safeTransfer(IERC20(token), recipient, amount);

        emit LiquidityWithdrawn(token, recipient, amount);
    }

    /// @notice Updates the address that receives swap fees
    ///
    /// @param newFeeRecipient New address to receive fees
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(newFeeRecipient != address(0), CannotBeZeroAddress());
        $.feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    /// @notice Updates the fee charged on swaps
    ///
    /// @param newFeeBasisPoints New fee in basis points (e.g., 100 = 1%, max 1000 = 10%)
    function updateFeeBasisPoints(uint16 newFeeBasisPoints) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        $.feeBasisPoints = newFeeBasisPoints;
        emit FeeUpdated(newFeeBasisPoints);
    }

    /// @notice Updates the reserved amount for a token (amount that cannot be withdrawn by swaps)
    ///
    /// @dev Reserved amount does not restrict WITHDRAW_ROLE withdrawals
    ///
    /// @param token Address of the token
    /// @param newReservedAmount New reserved amount (must not exceed current balance)
    function updateReservedAmount(address token, uint256 newReservedAmount)
        external
        onlyRole(WITHDRAW_ROLE)
        nonReentrant
    {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require($.listedTokens.contains(token), TokenNotListed(token));

        // Safety check: reserved amount must not exceed balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(newReservedAmount <= balance, ReservedAmountExceedsBalance(token, newReservedAmount, balance));

        $.reservedAmounts[token] = newReservedAmount;
        emit ReservedAmountUpdated(token, newReservedAmount);
    }

    /// @notice Adds an address to the allowlist (allowing it to initiate swaps when allowlist feature is enabled)
    ///
    /// @param addr Address to add to allowlist
    function addToAllowlist(address addr) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(addr != address(0), CannotBeZeroAddress());
        require(!$.allowlist[addr], AddressAlreadyInAllowlist(addr));
        $.allowlist[addr] = true;
        emit AllowlistAddressAdded(addr);
    }

    /// @notice Removes an address from the allowlist
    ///
    /// @param addr Address to remove from allowlist
    function removeFromAllowlist(address addr) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(addr != address(0), CannotBeZeroAddress());
        require($.allowlist[addr], AddressNotInAllowlist(addr));
        delete $.allowlist[addr];
        emit AllowlistAddressRemoved(addr);
    }

    /// @notice Updates a feature flag's enabled status
    ///
    /// @dev SWAP and WITHDRAW require PAUSE_ROLE, ALLOWLIST requires CONFIGURE_ROLE
    ///
    /// @param feature The feature flag to update
    /// @param isEnabled True to enable the feature, false to disable
    function setFeatureFlag(FeatureFlag feature, bool isEnabled) external {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        if (feature == FeatureFlag.ALLOWLIST) {
            _checkRole(CONFIGURE_ROLE);
        } else {
            _checkRole(PAUSE_ROLE);
        }
        $.featureFlags[feature] = isEnabled;
        emit FeatureFlagUpdated(feature, isEnabled);
    }

    // View functions
    /// @notice Returns the current contract version
    ///
    /// @return Version number of the contract implementation
    function contractVersion() external view returns (uint8) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.contractVersion;
    }

    /// @notice Returns the current fee recipient address
    ///
    /// @return Address that receives fees collected from swaps
    function feeRecipient() external view returns (address) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.feeRecipient;
    }

    /// @notice Returns the current fee in basis points
    ///
    /// @return Current fee in basis points (e.g., 100 = 1%)
    function feeBasisPoints() external view returns (uint16) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.feeBasisPoints;
    }

    /// @notice Returns whether a feature flag is enabled
    ///
    /// @param feature The feature flag to check
    ///
    /// @return True if the feature is enabled, false otherwise
    function isFeatureEnabled(FeatureFlag feature) external view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.featureFlags[feature];
    }

    /// @notice Returns an array of all listed token addresses
    ///
    /// @return Array of token addresses
    function getListedTokens() external view returns (address[] memory) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.listedTokens.values();
    }

    /// @notice Returns the number of listed tokens
    ///
    /// @return Count of listed tokens
    function getListedTokensCount() external view returns (uint256) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.listedTokens.length();
    }

    /// @notice Returns the reserved amount for a token
    ///
    /// @param token Address of the token
    ///
    /// @return Reserved amount (not available for withdrawal by swaps)
    function getReservedAmount(address token) external view returns (uint256) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.reservedAmounts[token];
    }

    /// @notice Returns whether a token is swappable
    ///
    /// @param token Address of the token
    ///
    /// @return True if the token is swappable, false otherwise
    function isTokenSwappable(address token) external view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.tokenSwappable[token];
    }

    /// @notice Returns whether an address is in the allowlist
    ///
    /// @param addr Address to check
    ///
    /// @return True if the address is allowed, false otherwise
    function isAllowlisted(address addr) external view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.allowlist[addr];
    }

    // Internal functions
    /// @dev Function that authorizes an upgrade to a new implementation
    /// @dev Only the single address holding DEFAULT_ADMIN_ROLE can authorize upgrades
    ///
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Private functions
    /// @dev Returns the storage pointer for the StableSwapper storage struct using ERC-7201 namespacing
    ///
    /// @return $ Storage pointer to the StableSwapperStorage struct
    function _stableSwapperStorage() private pure returns (StableSwapperStorage storage $) {
        assembly {
            $.slot := STABLE_SWAPPER_STORAGE_LOCATION
        }
    }

    /// @dev Normalizes token amounts between different decimal places
    ///
    /// @param amount Amount to normalize
    /// @param decimalsFrom Decimals of the source token
    /// @param decimalsTo Decimals of the destination token
    ///
    /// @return Normalized amount in destination token decimals
    function _normalizeDecimals(uint256 amount, uint8 decimalsFrom, uint8 decimalsTo) private pure returns (uint256) {
        if (decimalsFrom == decimalsTo) return amount;

        if (decimalsFrom < decimalsTo) {
            return amount * 10 ** (decimalsTo - decimalsFrom);
        }
        return amount / 10 ** (decimalsFrom - decimalsTo);
    }
}
