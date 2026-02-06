// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title StableSwapper
/// @notice A 1:1 stablecoin swap contract with decimal normalization and role-based access control
///
/// @dev This contract enables swapping between stablecoins with different decimal places.
/// @dev It implements UUPS upgradeability pattern and uses role-based access control for administration.
/// @dev The contract supports three main feature flags: SWAP, WITHDRAW, and ALLOWLIST.
///
/// @dev IMPORTANT LIMITATION: This contract does NOT support fee-on-transfer tokens. The swap logic
/// @dev assumes 1:1 transfers where the received amount equals the specified transfer amount. Tokens
/// @dev that deduct fees during transfers (like USDT's fee mechanism if enabled) would cause accounting
/// @dev errors and must NOT be listed. If a listed token activates transfer fees, it must be immediately
/// @dev disabled via updateTokenStatus() and removed via updateTokenListing() after draining liquidity.
///
/// @dev Roles:
/// @dev - DEFAULT_ADMIN_ROLE: Can authorize upgrades and manage all other roles (single holder, 2-step transfer)
/// @dev - TREASURY_ROLE: Can withdraw liquidity (treasury) and update reserved amounts
/// @dev - CONFIGURE_ROLE: Can list/unlist tokens, update fees, and manage allowlist
/// @dev - PAUSE_ROLE: Can pause/unpause swap and withdraw operations, and pause/unpause individual tokens
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

    /// @notice Role identifier for treasury role
    ///
    /// @dev Can withdraw liquidity (treasury operations) and update reserved amounts
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

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

    /// @notice Storage struct for StableSwapper using ERC-7201 namespaced storage pattern
    ///
    /// @custom:storage-location erc7201:coinbase.storage.StableSwapper
    struct StableSwapperStorage {
        /// @dev Set of addresses for tokens listed in this contract
        EnumerableSet.AddressSet listedTokens;
        /// @dev Mapping from token address to reserved amount (not available for withdrawal by swaps)
        mapping(address => uint256) reservedAmounts;
        /// @dev Mapping from token address to swappable status
        mapping(address => bool) tokenSwappable;
        /// @dev Mapping from token address to cached decimals value
        mapping(address => uint8) tokenDecimals;
        /// @dev Address that receives fees collected from swaps
        address feeRecipient;
        /// @dev Current fee in basis points (e.g., 100 = 1%)
        uint16 feeBasisPoints;
        /// @dev Mapping of addresses allowed to initiate swaps when allowlist feature is enabled
        mapping(address addr => bool allowed) allowlist;
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
    /// @param treasuryAuthority Initial address granted the TREASURY_ROLE
    /// @param configureAuthority Initial address granted the CONFIGURE_ROLE
    /// @param pauseAuthority Initial address granted the PAUSE_ROLE
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeBasisPoints Initial fee in basis points (e.g., 100 = 1%)
    /// @param initialAdminTransferDelay Delay in seconds for 2-step DEFAULT_ADMIN_ROLE transfers
    event Initialized(
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint16 initialFeeBasisPoints,
        uint48 initialAdminTransferDelay
    );

    /// @notice Emitted when a token's listing status is updated
    ///
    /// @param token Address of the token
    /// @param isListed True if the token was listed, false if unlisted
    event TokenListingUpdated(address indexed token, bool isListed);

    /// @notice Emitted when a swap is executed
    ///
    /// @param caller Address that initiated the swap (msg.sender)
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens provided (before fees)
    /// @param amountOut Amount of output tokens sent to recipient (after decimal normalization)
    /// @param fee Fee amount collected in input token
    /// @param recipient Address that received the output tokens
    event Swap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        address recipient
    );

    /// @notice Emitted when liquidity is withdrawn from the contract
    ///
    /// @param caller Address that initiated the withdrawal (TREASURY_ROLE holder)
    /// @param token Address of the token that was withdrawn
    /// @param recipient Address that received the withdrawn tokens
    /// @param amount Amount of tokens withdrawn
    event LiquidityWithdrawn(address indexed caller, address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when the fee recipient address is updated
    ///
    /// @param oldFeeRecipient Previous address that received swap fees
    /// @param newFeeRecipient New address that will receive swap fees
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    /// @notice Emitted when the fee is updated
    ///
    /// @param oldFeeBasisPoints Previous fee in basis points
    /// @param newFeeBasisPoints New fee in basis points (e.g., 100 = 1%)
    event FeeUpdated(uint16 oldFeeBasisPoints, uint16 newFeeBasisPoints);

    /// @notice Emitted when a feature flag is updated
    ///
    /// @param feature The feature that was updated
    /// @param isEnabled True if the feature is enabled, false if disabled
    event FeatureFlagUpdated(FeatureFlag indexed feature, bool isEnabled);

    /// @notice Emitted when a token's reserved amount is updated
    ///
    /// @param token Address of the token whose reserved amount was updated
    /// @param oldReservedAmount Previous reserved amount
    /// @param newReservedAmount New reserved amount (cannot be withdrawn from liquidity)
    event ReservedAmountUpdated(address indexed token, uint256 oldReservedAmount, uint256 newReservedAmount);

    /// @notice Emitted when a token's swappable status is updated
    ///
    /// @param token Address of the token whose status was updated
    /// @param isSwappable True if token is swappable, false if disabled
    event TokenStatusUpdated(address indexed token, bool isSwappable);

    /// @notice Emitted when an address's allowlist status is updated
    ///
    /// @param addr Address whose allowlist status was updated
    /// @param isAllowlisted True if the address was added to the allowlist, false if removed
    event AllowlistUpdated(address indexed addr, bool isAllowlisted);

    /// @notice Thrown when an address parameter is the zero address
    error CannotBeZeroAddress();

    /// @notice Thrown when a token's listing status doesn't match the expected state
    ///
    /// @param token Address of the token
    /// @param state The current listing state
    error InvalidTokenListingState(address token, bool state);

    /// @notice Thrown when attempting an operation on a token that is not listed
    ///
    /// @param token Address of the token
    error TokenNotListed(address token);

    /// @notice Thrown when attempting to swap a token for itself
    ///
    /// @param token Address of the token
    error CannotSwapSameToken(address token);

    /// @notice Thrown when attempting to unlist a token that is still swappable
    ///
    /// @param token Address of the token
    error TokenMustNotBeSwappable(address token);

    /// @notice Thrown when an amount parameter is zero
    error CannotBeZeroAmount();

    /// @notice Thrown when the output amount is less than the minimum acceptable amount (slippage protection)
    error SlippageExceeded();

    /// @notice Thrown when the token out balance is less than the reserved amount
    ///
    /// @param token Address of the token
    error TokenOutBalanceLessThanReservedAmount(address token);

    /// @notice Thrown when the swap output amount exceeds available liquidity
    ///
    /// @param amountOut The amount of output tokens requested
    /// @param availableLiquidity The available liquidity for the output token
    error AmountOutExceedsAvailableLiquidity(uint256 amountOut, uint256 availableLiquidity);

    /// @notice Thrown when attempting to withdraw liquidity while the withdraw feature is disabled
    error WithdrawalCannotBePaused();

    /// @notice Thrown when attempting to swap while the swap feature is disabled
    error SwapsCannotBePaused();

    /// @notice Thrown when attempting to swap with a token that is not swappable
    ///
    /// @param token Address of the token
    error TokenMustBeSwappable(address token);

    /// @notice Thrown when an address's allowlist status doesn't match the expected state
    ///
    /// @param addr Address that was checked
    /// @param state The current allowlist state
    error InvalidAllowlistState(address addr, bool state);

    /// @notice Thrown when attempting an operation on an address that is not in the allowlist
    ///
    /// @param addr Address that is not in the allowlist
    error AddressNotInAllowlist(address addr);

    /// @notice Thrown when attempting to set a fee greater than the denominator
    ///
    /// @param feeBasisPoints The fee in basis points that was attempted
    error FeeExceedsDenominator(uint16 feeBasisPoints);

    /// @notice Thrown when a token's swappable status doesn't match the expected state
    ///
    /// @param token Address of the token
    /// @param state The current swappable state
    error InvalidTokenSwappableState(address token, bool state);

    /// @notice Thrown when a feature flag's enabled status doesn't match the expected state
    ///
    /// @param feature The feature flag
    /// @param state The current enabled state
    error InvalidFeatureFlagState(FeatureFlag feature, bool state);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the StableSwapper contract with roles and fee configuration
    ///
    /// @dev DEFAULT_ADMIN_ROLE uses a 2-step transfer process and can only be held by one address at a time
    /// @dev DEFAULT_ADMIN_ROLE is the only role that can grant/revoke other roles
    /// @dev Other roles (TREASURY_ROLE, CONFIGURE_ROLE, PAUSE_ROLE) can have multiple holders
    ///
    /// @param defaultAdmin Address granted DEFAULT_ADMIN_ROLE (can authorize UUPS upgrades and grant/revoke all other roles)
    /// @param treasuryAuthority Initial address granted TREASURY_ROLE (can withdraw liquidity for treasury and update reserved amounts)
    /// @param configureAuthority Initial address granted CONFIGURE_ROLE (can add/remove tokens, update fees, manage allowlist)
    /// @param pauseAuthority Initial address granted PAUSE_ROLE (can pause/unpause operations and enable/disable tokens)
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeBasisPoints Initial fee in basis points (e.g., 100 = 1%)
    /// @param initialAdminTransferDelay Delay in seconds for 2-step DEFAULT_ADMIN_ROLE transfers (security feature)
    function initialize(
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint16 initialFeeBasisPoints,
        uint48 initialAdminTransferDelay
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialAdminTransferDelay, defaultAdmin);

        require(treasuryAuthority != address(0), CannotBeZeroAddress());
        require(configureAuthority != address(0), CannotBeZeroAddress());
        require(pauseAuthority != address(0), CannotBeZeroAddress());

        _grantRole(TREASURY_ROLE, treasuryAuthority);
        _grantRole(CONFIGURE_ROLE, configureAuthority);
        _grantRole(PAUSE_ROLE, pauseAuthority);

        require(initialFeeBasisPoints <= FEE_DENOMINATOR, FeeExceedsDenominator(initialFeeBasisPoints));
        require(initialFeeRecipient != address(0), CannotBeZeroAddress());

        StableSwapperStorage storage $ = _stableSwapperStorage();
        $.feeRecipient = initialFeeRecipient;
        $.feeBasisPoints = initialFeeBasisPoints;
        $.featureFlags[FeatureFlag.SWAP] = true;
        $.featureFlags[FeatureFlag.WITHDRAW] = true;
        $.featureFlags[FeatureFlag.ALLOWLIST] = false;

        emit Initialized(
            defaultAdmin,
            treasuryAuthority,
            configureAuthority,
            pauseAuthority,
            initialFeeRecipient,
            initialFeeBasisPoints,
            initialAdminTransferDelay
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
        // CHECKS: All validation and calculations
        require(isFeatureEnabled(FeatureFlag.SWAP), SwapsCannotBePaused());
        require(recipient != address(0), CannotBeZeroAddress());
        require(tokenIn != tokenOut, CannotSwapSameToken(tokenIn));
        require(isTokenListed(tokenIn), TokenNotListed(tokenIn));
        require(isTokenListed(tokenOut), TokenNotListed(tokenOut));
        require(amountIn > 0, CannotBeZeroAmount());
        require(minAmountOut > 0, CannotBeZeroAmount());

        // We only check that the initiator is in the allowlist if allowlist is enabled
        // The recipient does not need to be in the allowlist
        if (isFeatureEnabled(FeatureFlag.ALLOWLIST)) {
            require(isAllowlisted(msg.sender), AddressNotInAllowlist(msg.sender));
        }

        require(isTokenSwappable(tokenIn), TokenMustBeSwappable(tokenIn));
        require(isTokenSwappable(tokenOut), TokenMustBeSwappable(tokenOut));

        // Fee Model: Fee is charged on INPUT token
        // Example: User swaps 100 USDC → USDT with 1% fee
        //   - User provides: 100 USDC total
        //   - Contract receives: 100 USDC
        //   - fee_recipient receives: 1 USDC (protocol fee)
        //   - User receives: 99 USDT (1:1 swap of net amount, normalized for decimals)

        // Force rounding up to collect full fee amount by adding `FEE_DENOMINATOR - 1` to numerator
        uint256 amountInAfterFee = amountIn;
        uint256 fee = 0;
        uint16 currentFeeBasisPoints = feeBasisPoints();
        if (currentFeeBasisPoints > 0) {
            fee = (amountIn * currentFeeBasisPoints + FEE_DENOMINATOR - 1) / FEE_DENOMINATOR;
            amountInAfterFee -= fee;
        }

        // Get decimals from cache (set when tokens are listed)
        uint8 decimalsIn = getTokenDecimals(tokenIn);
        uint8 decimalsOut = getTokenDecimals(tokenOut);
        uint256 amountOut = _normalizeDecimals(amountInAfterFee, decimalsIn, decimalsOut);

        // Slippage protection: ensure normalized output meets user's minimum acceptable amount
        // Note: Since minAmountOut > 0 (checked above) and amountOut >= minAmountOut, amountOut is guaranteed to be > 0
        require(amountOut >= minAmountOut, SlippageExceeded());

        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(address(this));

        // Prevent underflow, there is no available liquidity if the token out balance is less than the reserved amount
        uint256 reservedAmount = getReservedAmount(tokenOut);
        require(reservedAmount <= tokenOutBalance, TokenOutBalanceLessThanReservedAmount(tokenOut));

        uint256 availableLiquidity = tokenOutBalance - reservedAmount;
        require(amountOut <= availableLiquidity, AmountOutExceedsAvailableLiquidity(amountOut, availableLiquidity));

        // Step 1: Transfer the full amount in to the contract from sender
        // This gets added to the pool's liquidity for the input token
        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

        // Step 2: Transfer the fee to the fee recipient
        if (fee > 0) {
            SafeERC20.safeTransfer(IERC20(tokenIn), feeRecipient(), fee);
        }

        // Step 3: Transfer the amount out to the recipient
        SafeERC20.safeTransfer(IERC20(tokenOut), recipient, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, fee, recipient);
    }

    /// @notice Updates the listing status of a token
    ///
    /// @dev When listing a token (isListed=true), the token is added with swappable=false and reservedAmount=0
    /// @dev When unlisting a token (isListed=false), the token must not be swappable
    ///
    /// @dev IMPORTANT: Before listing any token, verify it does NOT implement fee-on-transfer mechanisms.
    /// @dev The contract assumes 1:1 transfers. Tokens with transfer fees will cause accounting errors.
    /// @dev Avoid listing tokens with configurable transfer fees, even if currently disabled (e.g., USDT).
    ///
    /// @param token Address of the ERC20 token
    /// @param isListed True to list the token, false to unlist it
    function updateTokenListing(address token, bool isListed) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(token != address(0), CannotBeZeroAddress());
        require(isTokenListed(token) != isListed, InvalidTokenListingState(token, isTokenListed(token)));
        require(!isTokenSwappable(token), TokenMustNotBeSwappable(token));

        $.reservedAmounts[token] = 0;

        if (isListed) {
            $.listedTokens.add(token);
            $.tokenDecimals[token] = IERC20Metadata(token).decimals();
        } else {
            $.listedTokens.remove(token);
            delete $.tokenDecimals[token];
        }

        emit TokenListingUpdated(token, isListed);
    }

    /// @notice Updates the swappable status of a token
    ///
    /// @param token Address of the token
    /// @param isSwappable True to enable swapping, false to disable
    function updateTokenStatus(address token, bool isSwappable) external onlyRole(PAUSE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(isTokenListed(token), TokenNotListed(token));
        require(isTokenSwappable(token) != isSwappable, InvalidTokenSwappableState(token, isTokenSwappable(token)));
        $.tokenSwappable[token] = isSwappable;
        emit TokenStatusUpdated(token, isSwappable);
    }

    /// @notice Withdraws liquidity from the contract for a specific token
    ///
    /// @dev Only callable by address with TREASURY_ROLE
    /// @dev Treasury role can withdraw regardless of reserved amount (reserved amount only restricts swaps)
    ///
    /// @param token Address of the token to withdraw
    /// @param amount Amount of tokens to withdraw
    /// @param recipient Address to receive the withdrawn tokens
    function withdrawLiquidity(address token, uint256 amount, address recipient)
        external
        onlyRole(TREASURY_ROLE)
        nonReentrant
    {
        require(token != address(0), CannotBeZeroAddress());
        require(recipient != address(0), CannotBeZeroAddress());
        require(isFeatureEnabled(FeatureFlag.WITHDRAW), WithdrawalCannotBePaused());
        require(isTokenListed(token), TokenNotListed(token));
        require(amount > 0, CannotBeZeroAmount());

        // Note: TREASURY_ROLE can withdraw regardless of reserved amount
        // Reserved amount is meant to protect swap users, not restrict treasury role
        // This allows treasury role to manage liquidity in emergency situations
        SafeERC20.safeTransfer(IERC20(token), recipient, amount);

        emit LiquidityWithdrawn(msg.sender, token, recipient, amount);
    }

    /// @notice Updates the address that receives swap fees
    ///
    /// @param newFeeRecipient New address to receive fees
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(newFeeRecipient != address(0), CannotBeZeroAddress());
        address oldFeeRecipient = feeRecipient();
        $.feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(oldFeeRecipient, newFeeRecipient);
    }

    /// @notice Updates the fee charged on swaps
    ///
    /// @param newFeeBasisPoints New fee in basis points (e.g., 100 = 1%, max 10000 = 100%)
    function updateFeeBasisPoints(uint16 newFeeBasisPoints) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(newFeeBasisPoints <= FEE_DENOMINATOR, FeeExceedsDenominator(newFeeBasisPoints));
        uint16 oldFeeBasisPoints = feeBasisPoints();
        $.feeBasisPoints = newFeeBasisPoints;
        emit FeeUpdated(oldFeeBasisPoints, newFeeBasisPoints);
    }

    /// @notice Updates the reserved amount for a token (amount that cannot be withdrawn by swaps)
    ///
    /// @dev Reserved amount does not restrict TREASURY_ROLE withdrawals
    ///
    /// @param token Address of the token
    /// @param newReservedAmount New reserved amount (can be any value)
    function updateReservedAmount(address token, uint256 newReservedAmount) external onlyRole(TREASURY_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(isTokenListed(token), TokenNotListed(token));

        uint256 oldReservedAmount = getReservedAmount(token);
        $.reservedAmounts[token] = newReservedAmount;
        emit ReservedAmountUpdated(token, oldReservedAmount, newReservedAmount);
    }

    /// @notice Updates an address's allowlist status
    ///
    /// @param addr Address to update
    /// @param allowed True to add to allowlist, false to remove
    function updateAllowlist(address addr, bool allowed) external onlyRole(CONFIGURE_ROLE) {
        StableSwapperStorage storage $ = _stableSwapperStorage();

        require(addr != address(0), CannotBeZeroAddress());
        require(isAllowlisted(addr) != allowed, InvalidAllowlistState(addr, isAllowlisted(addr)));

        $.allowlist[addr] = allowed;
        emit AllowlistUpdated(addr, allowed);
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
        require(isFeatureEnabled(feature) != isEnabled, InvalidFeatureFlagState(feature, isFeatureEnabled(feature)));
        $.featureFlags[feature] = isEnabled;
        emit FeatureFlagUpdated(feature, isEnabled);
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

    /// @notice Returns the current fee recipient address
    ///
    /// @return Address that receives fees collected from swaps
    function feeRecipient() public view returns (address) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.feeRecipient;
    }

    /// @notice Returns the current fee in basis points
    ///
    /// @return Current fee in basis points (e.g., 100 = 1%)
    function feeBasisPoints() public view returns (uint16) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.feeBasisPoints;
    }

    /// @notice Returns whether a feature flag is enabled
    ///
    /// @param feature The feature flag to check
    ///
    /// @return True if the feature is enabled, false otherwise
    function isFeatureEnabled(FeatureFlag feature) public view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.featureFlags[feature];
    }

    /// @notice Returns whether a token is listed
    ///
    /// @param token Address of the token
    ///
    /// @return True if the token is listed, false otherwise
    function isTokenListed(address token) public view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.listedTokens.contains(token);
    }

    /// @notice Returns the reserved amount for a token
    ///
    /// @param token Address of the token
    ///
    /// @return Reserved amount (not available for withdrawal by swaps)
    function getReservedAmount(address token) public view returns (uint256) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.reservedAmounts[token];
    }

    /// @notice Returns whether a token is swappable
    ///
    /// @param token Address of the token
    ///
    /// @return True if the token is swappable, false otherwise
    function isTokenSwappable(address token) public view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.tokenSwappable[token];
    }

    /// @notice Returns whether an address is in the allowlist
    ///
    /// @param addr Address to check
    ///
    /// @return True if the address is allowed, false otherwise
    function isAllowlisted(address addr) public view returns (bool) {
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.allowlist[addr];
    }

    /// @notice Returns the cached decimals value for a token
    ///
    /// @param token Address of the token
    ///
    /// @return The cached decimals value (set when token is listed)
    function getTokenDecimals(address token) public view returns (uint8) {
        require(isTokenListed(token), TokenNotListed(token));
        StableSwapperStorage storage $ = _stableSwapperStorage();
        return $.tokenDecimals[token];
    }

    /// @dev Function that authorizes an upgrade to a new implementation
    /// @dev Only the single address holding DEFAULT_ADMIN_ROLE can authorize upgrades
    ///
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

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
