// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract StableSwapper is
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Vault information for a supported token
    ///
    /// @dev Stores per-token state including reserves, enabled status, and decimal places
    ///
    /// @param reservedAmount Amount of tokens reserved and not available for withdrawal
    /// @param isEnabled Whether the token is currently enabled for swapping
    /// @param decimals Number of decimal places the token uses (must be between MIN_DECIMALS and MAX_DECIMALS)
    struct TokenVault {
        uint256 reservedAmount;
        bool isEnabled;
        uint8 decimals;
    }

    /// @notice Maximum fee rate in basis points (10% = 1000 basis points)
    uint64 public constant MAX_FEE_RATE = 1000;

    /// @notice Fee denominator for basis points calculation (100% = 10000 basis points)
    uint64 public constant FEE_DENOMINATOR = 10000;

    /// @notice Maximum number of addresses that can be whitelisted
    uint64 public constant MAX_WHITELISTED_ADDRESSES = 100;

    /// @notice Maximum number of tokens that can be supported simultaneously
    uint64 public constant MAX_SUPPORTED_TOKENS = 50;

    /// @notice Minimum number of decimals a token must have to be supported
    uint8 public constant MIN_DECIMALS = 6;

    /// @notice Maximum number of decimals a token can have to be supported
    uint8 public constant MAX_DECIMALS = 9;

    /// @notice Role identifier for treasury role
    /// @dev Can withdraw liquidity and update reserved amounts
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    /// @notice Role identifier for pause role
    /// @dev Can pause/unpause swaps and liquidity operations, and enable/disable individual tokens
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice Role identifier for configure role
    /// @dev Can add/remove tokens, update fee configuration, and manage whitelist
    /// @dev Multiple addresses can hold this role simultaneously
    bytes32 public constant CONFIGURE_ROLE = keccak256("CONFIGURE_ROLE");

    /// @notice Version number of the contract implementation
    uint8 public contractVersion;

    /// @dev Set of addresses for tokens supported by this contract
    EnumerableSet.AddressSet private _supportedTokens;

    /// @dev Mapping from token address to its vault information
    mapping(address => TokenVault) private _vaults;

    /// @notice Address that receives fees collected from swaps
    address public feeRecipient;

    /// @notice Current fee rate in basis points (e.g., 100 = 1%)
    uint64 public feeRate;

    /// @dev Set of addresses that are whitelisted to initiate swaps (when whitelist is enabled)
    EnumerableSet.AddressSet private _whitelistedAddresses;

    /// @notice Whether whitelist enforcement is currently enabled
    bool public whitelistEnabled;

    /// @notice Whether swap operations are currently enabled
    bool public swapsEnabled;

    /// @notice Whether liquidity operations (withdrawals) are currently enabled
    bool public liquidityEnabled;

    /// @notice Emitted when the contract is initialized with initial roles and fee configuration
    /// @dev DEFAULT_ADMIN_ROLE can grant/revoke other roles after initialization
    ///
    /// @param defaultAdmin Address granted the DEFAULT_ADMIN_ROLE (only role that can manage other roles)
    /// @param treasuryAuthority Initial address granted the TREASURY_ROLE role
    /// @param configureAuthority Initial address granted the CONFIGURE_ROLE role
    /// @param pauseAuthority Initial address granted the PAUSE_ROLE role
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeRate Initial fee rate in basis points (e.g., 100 = 1%)
    event Initialized(
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint64 initialFeeRate
    );

    /// @notice Emitted when a new token is added to the supported tokens list
    ///
    /// @param token Address of the token that was added
    /// @param decimals Number of decimals the token uses
    event TokenAdded(address indexed token, uint8 decimals);

    /// @notice Emitted when a token is removed from the supported tokens list
    /// @param token Address of the token that was removed
    event TokenRemoved(address indexed token);

    /// @notice Emitted when a swap is executed
    ///
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens provided (before fees)
    /// @param amountOut Amount of output tokens sent to recipient (after decimal normalization)
    /// @param fee Fee amount collected in input token
    event Swap(address indexed tokenIn, address indexed tokenOut, uint64 amountIn, uint64 amountOut, uint64 fee);

    /// @notice Emitted when liquidity is withdrawn from a token vault
    ///
    /// @param token Address of the token that was withdrawn
    /// @param recipient Address that received the withdrawn tokens
    /// @param amount Amount of tokens withdrawn
    event LiquidityWithdrawn(address indexed token, address indexed recipient, uint64 amount);

    /// @notice Emitted when the fee recipient address is updated
    /// @param newFeeRecipient New address that will receive swap fees
    event FeeRecipientUpdated(address newFeeRecipient);

    /// @notice Emitted when the fee rate is updated
    /// @param newFeeRate New fee rate in basis points (e.g., 100 = 1%)
    event FeeRateUpdated(uint64 newFeeRate);

    /// @notice Emitted when swap status is updated
    /// @param isEnabled True if swaps are enabled, false if disabled
    event SwapStatusUpdated(bool isEnabled);

    /// @notice Emitted when liquidity status is updated
    /// @param isEnabled True if liquidity operations are enabled, false if disabled
    event LiquidityStatusUpdated(bool isEnabled);

    /// @notice Emitted when a token's reserved amount is updated
    ///
    /// @param token Address of the token whose reserved amount was updated
    /// @param newReservedAmount New reserved amount (cannot be withdrawn from liquidity)
    event ReservedAmountUpdated(address indexed token, uint64 newReservedAmount);

    /// @notice Emitted when a token's enabled status is updated
    ///
    /// @param token Address of the token whose status was updated
    /// @param isEnabled True if token is enabled for swaps, false if disabled
    event TokenStatusUpdated(address indexed token, bool isEnabled);

    /// @notice Emitted when an address is added to the whitelist
    /// @param addr Address that was added to the whitelist
    event WhitelistAddressAdded(address addr);

    /// @notice Emitted when an address is removed from the whitelist
    /// @param addr Address that was removed from the whitelist
    event WhitelistAddressRemoved(address addr);

    /// @notice Emitted when whitelist enforcement is enabled
    /// @dev When enabled, only whitelisted addresses can initiate swaps
    event WhitelistEnabled();

    /// @notice Emitted when whitelist enforcement is disabled
    /// @dev When disabled, any address can initiate swaps
    event WhitelistDisabled();

    error CannotBeZeroAddress();
    error TokenAlreadySupported(address token);
    error TokenNotSupported(address token);
    error CannotSwapSameToken(address token);
    error SupportedTokensExceedsMaximum(uint64 maxTokens);
    error TokenDoesNotImplementDecimals(address token);
    error TokenMustBeDisabled(address token);
    error TokenHasBalance(address token);
    error CannotBeZeroAmount();
    error SlippageExceeded();
    error AmountOutCannotBeZero();
    error AmountOutExceedsAvailableLiquidity(uint64 amountOut, uint256 availableLiquidity);
    error LiquidityCannotBePaused();
    error LiquidityWithdrawExceedsBalance(address token, uint64 amount, uint256 balance);
    error SwapsCannotBePaused();
    error VaultMustBeEnabled(address token);
    error FeeCalculationOverflow();
    error DecimalsOutOfRange(address token, uint8 decimals);
    error FeeRateExceedsMaximum(uint64 feeRate);
    error ReservedAmountExceedsBalance(address token, uint64 reservedAmount, uint256 balance);
    error WhitelistExceedsMaximum(uint64 maxAddresses);
    error AddressAlreadyInWhitelist(address addr);
    error AddressNotInWhitelist(address addr);
    error DecimalNormalizationOverflow();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the StableSwapper contract with roles and fee configuration
    /// @dev DEFAULT_ADMIN_ROLE uses a 2-step transfer process and can only be held by one address at a time
    /// @dev DEFAULT_ADMIN_ROLE is the only role that can grant/revoke other roles
    /// @dev Other roles (TREASURY_ROLE, CONFIGURE_ROLE, PAUSE_ROLE) can have multiple holders
    ///
    /// @param defaultAdmin Address granted DEFAULT_ADMIN_ROLE (can authorize UUPS upgrades and grant/revoke all other roles)
    /// @param treasuryAuthority Initial address granted TREASURY_ROLE (can withdraw liquidity and update reserved amounts)
    /// @param configureAuthority Initial address granted CONFIGURE_ROLE (can add/remove tokens, update fees, manage whitelist)
    /// @param pauseAuthority Initial address granted PAUSE_ROLE (can pause/unpause operations and enable/disable tokens)
    /// @param initialFeeRecipient Address that will receive swap fees
    /// @param initialFeeRate Fee rate in basis points (e.g., 100 = 1%)
    /// @param initialAdminTransferDelay Delay in seconds for 2-step DEFAULT_ADMIN_ROLE transfers (security feature)
    function initialize(
        address defaultAdmin,
        address treasuryAuthority,
        address configureAuthority,
        address pauseAuthority,
        address initialFeeRecipient,
        uint64 initialFeeRate,
        uint48 initialAdminTransferDelay
    ) public initializer {
        __AccessControlDefaultAdminRules_init(initialAdminTransferDelay, defaultAdmin);

        require(initialFeeRate <= MAX_FEE_RATE, FeeRateExceedsMaximum(initialFeeRate));

        _grantRole(TREASURY_ROLE, treasuryAuthority);
        _grantRole(CONFIGURE_ROLE, configureAuthority);
        _grantRole(PAUSE_ROLE, pauseAuthority);

        feeRecipient = initialFeeRecipient;
        feeRate = initialFeeRate;
        swapsEnabled = true;
        liquidityEnabled = true;
        whitelistEnabled = false;
        contractVersion = 1;

        emit Initialized(
            defaultAdmin, treasuryAuthority, configureAuthority, pauseAuthority, initialFeeRecipient, initialFeeRate
        );
    }

    /// @dev Function that authorizes an upgrade to a new implementation
    /// @dev Only the single address holding DEFAULT_ADMIN_ROLE can authorize upgrades
    ///
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Adds a new token to the list of supported tokens for swapping
    ///
    /// @param token Address of the ERC20 token to add (must have 6-9 decimals)
    function addToken(address token) external onlyRole(CONFIGURE_ROLE) {
        require(token != address(0), CannotBeZeroAddress());
        require(!_supportedTokens.contains(token), TokenAlreadySupported(token));
        require(_supportedTokens.length() < MAX_SUPPORTED_TOKENS, SupportedTokensExceedsMaximum(MAX_SUPPORTED_TOKENS));

        uint8 decimals;
        try IERC20Metadata(token).decimals() returns (uint8 _decimals) {
            decimals = _decimals;
        } catch {
            // If token doesn't implement decimals(), revert
            revert TokenDoesNotImplementDecimals(token);
        }

        // Validate decimal range (6-9 decimals only)
        require(decimals >= MIN_DECIMALS && decimals <= MAX_DECIMALS, DecimalsOutOfRange(token, decimals));

        _supportedTokens.add(token);
        _vaults[token] = TokenVault({reservedAmount: 0, isEnabled: true, decimals: decimals});
        emit TokenAdded(token, decimals);
    }

    /// @notice Removes a token from the list of supported tokens (token must be disabled and have zero balance)
    ///
    /// @param token Address of the token to remove
    function removeToken(address token) external onlyRole(CONFIGURE_ROLE) {
        require(token != address(0), CannotBeZeroAddress());
        require(_supportedTokens.contains(token), TokenNotSupported(token));

        // Safety check: token must be disabled first
        // This prevents accidental removal of active trading pairs
        require(!_vaults[token].isEnabled, TokenMustBeDisabled(token));

        // Safety check: token must have no balance in the contract
        // This prevents accidental removal of tokens with remaining balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance == 0, TokenHasBalance(token));

        _supportedTokens.remove(token);
        delete _vaults[token];
        emit TokenRemoved(token);
    }

    /// @notice Swaps one stablecoin for another with automatic decimal normalization and fee deduction
    ///
    /// @param tokenIn Address of the token being swapped from
    /// @param tokenOut Address of the token being swapped to
    /// @param amountIn Amount of tokenIn to swap (before fees)
    /// @param minAmountOut Minimum acceptable amount of tokenOut to receive (for slippage protection)
    /// @param recipient Address that will receive the output tokens
    function swap(address tokenIn, address tokenOut, uint64 amountIn, uint64 minAmountOut, address recipient)
        external
        nonReentrant
    {
        // CHECKS: All validation and calculations
        require(swapsEnabled, SwapsCannotBePaused());
        require(tokenIn != address(0), CannotBeZeroAddress());
        require(tokenOut != address(0), CannotBeZeroAddress());
        require(tokenIn != tokenOut, CannotSwapSameToken(tokenIn));
        require(_supportedTokens.contains(tokenIn), TokenNotSupported(tokenIn));
        require(_supportedTokens.contains(tokenOut), TokenNotSupported(tokenOut));
        require(amountIn > 0, CannotBeZeroAmount());
        require(minAmountOut > 0, CannotBeZeroAmount());

        // We only check that the initiator is in the whitelist if whitelist is enabled
        // The recipient does not need to be in the whitelist
        if (whitelistEnabled) {
            require(_whitelistedAddresses.contains(msg.sender), AddressNotInWhitelist(msg.sender));
        }

        TokenVault storage vaultIn = _vaults[tokenIn];
        TokenVault storage vaultOut = _vaults[tokenOut];

        require(vaultIn.isEnabled, VaultMustBeEnabled(tokenIn));
        require(vaultOut.isEnabled, VaultMustBeEnabled(tokenOut));

        // Fee Model: Fee is charged on INPUT token (from_mint)
        // Example: User swaps 100 USDC → SOL with 1% fee
        //   - User provides: 100 USDC total
        //   - from_vault receives: 99 USDC (liquidity)
        //   - fee_recipient receives: 1 USDC (protocol fee)
        //   - to_vault sends: 99 SOL to user (1:1 swap of net amount, normalized for decimals)

        // Calculate fee (in basis points, e.g., 100 = 1%)
        // Round up to ensure protocol always collects full fee amount
        uint256 feeNumerator = uint256(amountIn) * uint256(feeRate);
        uint256 fee256 = (feeNumerator + FEE_DENOMINATOR - 1) / FEE_DENOMINATOR;

        // Fee should never exceed amountIn, but add safety check
        require(fee256 <= type(uint64).max, FeeCalculationOverflow());
        // casting to 'uint64' is safe because we check fee256 <= type(uint64).max above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 fee = uint64(fee256);

        // Checked subtraction to prevent underflow (though fee <= amountIn by construction)
        require(fee <= amountIn, FeeCalculationOverflow());
        uint64 amountInAfterFee = amountIn - fee;

        uint64 amountOut = normalizeDecimals(amountInAfterFee, vaultIn.decimals, vaultOut.decimals);

        require(amountOut > 0, AmountOutCannotBeZero());

        // Slippage protection: ensure normalized output meets user's minimum acceptable amount
        require(amountOut >= minAmountOut, SlippageExceeded());

        uint256 availableLiquidity = IERC20(tokenOut).balanceOf(address(this)) - vaultOut.reservedAmount;
        require(amountOut <= availableLiquidity, AmountOutExceedsAvailableLiquidity(amountOut, availableLiquidity));

        // EFFECTS: Cache state variables before external calls
        // This prevents TOCTOU (Time-of-Check-Time-of-Use) issues where feeRecipient
        // could be changed by another transaction between check and use
        address cachedFeeRecipient = feeRecipient;

        // INTERACTIONS: All external calls happen last to prevent reentrancy exploits
        // Following the Checks-Effects-Interactions pattern for maximum security

        // Step 1: Transfer the full amount in to the vaultIn from sender
        // This gets added to the pool's liquidity for the input token
        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

        // Step 2: Transfer the fee to the cached fee recipient
        // Using cached value prevents malicious fee recipient changes during execution
        SafeERC20.safeTransfer(IERC20(tokenIn), cachedFeeRecipient, fee);

        // Step 3: Transfer the amount out to the recipient
        SafeERC20.safeTransfer(IERC20(tokenOut), recipient, amountOut);

        emit Swap(tokenIn, tokenOut, amountIn, amountOut, fee);
    }

    /// @notice Withdraws liquidity from the contract for a specific token
    /// @dev Only callable by address with TREASURY_ROLE role
    /// @dev Treasury role can withdraw regardless of reserved amount (reserved amount only restricts swaps)
    ///
    /// @param token Address of the token to withdraw
    /// @param recipient Address to receive the withdrawn tokens
    /// @param amount Amount of tokens to withdraw
    function withdrawLiquidity(address token, address recipient, uint64 amount) external onlyRole(TREASURY_ROLE) {
        require(token != address(0), CannotBeZeroAddress());
        require(recipient != address(0), CannotBeZeroAddress());
        require(liquidityEnabled, LiquidityCannotBePaused());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        require(amount > 0, CannotBeZeroAmount());

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, LiquidityWithdrawExceedsBalance(token, amount, balance));

        // Note: TREASURY_ROLE can withdraw regardless of reserved amount
        // Reserved amount is meant to protect swap users, not restrict treasury role
        // This allows treasury role to manage liquidity in emergency situations

        SafeERC20.safeTransfer(IERC20(token), recipient, amount);

        emit LiquidityWithdrawn(token, recipient, amount);
    }

    /// @notice Updates the address that receives swap fees
    ///
    /// @param newFeeRecipient New address to receive fees
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(CONFIGURE_ROLE) {
        require(newFeeRecipient != address(0), CannotBeZeroAddress());
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    /// @notice Updates the fee rate charged on swaps
    ///
    /// @param newFeeRate New fee rate in basis points (e.g., 100 = 1%, max 1000 = 10%)
    function updateFeeRate(uint64 newFeeRate) external onlyRole(CONFIGURE_ROLE) {
        require(newFeeRate <= MAX_FEE_RATE, FeeRateExceedsMaximum(newFeeRate));
        feeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }

    /// @notice Updates the swap operations status
    /// @param isEnabled True to enable swaps, false to disable
    function updateSwapStatus(bool isEnabled) external onlyRole(PAUSE_ROLE) {
        swapsEnabled = isEnabled;
        emit SwapStatusUpdated(isEnabled);
    }

    /// @notice Updates the liquidity operations status
    /// @param isEnabled True to enable liquidity operations, false to disable
    function updateLiquidityStatus(bool isEnabled) external onlyRole(PAUSE_ROLE) {
        liquidityEnabled = isEnabled;
        emit LiquidityStatusUpdated(isEnabled);
    }

    /// @notice Updates the reserved amount for a token (amount that cannot be withdrawn by swaps)
    /// @dev Reserved amount does not restrict TREASURY_ROLE withdrawals
    ///
    /// @param token Address of the token
    /// @param newReservedAmount New reserved amount (must not exceed current balance)
    function updateReservedAmount(address token, uint64 newReservedAmount) external onlyRole(TREASURY_ROLE) {
        require(token != address(0), CannotBeZeroAddress());
        require(_supportedTokens.contains(token), TokenNotSupported(token));

        // Safety check: reserved amount must not exceed balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(newReservedAmount <= balance, ReservedAmountExceedsBalance(token, newReservedAmount, balance));

        _vaults[token].reservedAmount = newReservedAmount;
        emit ReservedAmountUpdated(token, newReservedAmount);
    }

    /// @notice Enables or disables a token for swapping
    ///
    /// @param token Address of the token
    /// @param isEnabled True to enable, false to disable
    function updateTokenStatus(address token, bool isEnabled) external onlyRole(PAUSE_ROLE) {
        require(token != address(0), CannotBeZeroAddress());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        _vaults[token].isEnabled = isEnabled;
        emit TokenStatusUpdated(token, isEnabled);
    }

    /// @notice Adds an address to the whitelist (allowing it to initiate swaps when whitelist is enabled)
    ///
    /// @param addr Address to add to whitelist
    function addToWhitelist(address addr) external onlyRole(CONFIGURE_ROLE) {
        require(addr != address(0), CannotBeZeroAddress());
        require(!_whitelistedAddresses.contains(addr), AddressAlreadyInWhitelist(addr));
        require(
            _whitelistedAddresses.length() < MAX_WHITELISTED_ADDRESSES,
            WhitelistExceedsMaximum(MAX_WHITELISTED_ADDRESSES)
        );
        _whitelistedAddresses.add(addr);
        emit WhitelistAddressAdded(addr);
    }

    /// @notice Removes an address from the whitelist
    ///
    /// @param addr Address to remove from whitelist
    function removeFromWhitelist(address addr) external onlyRole(CONFIGURE_ROLE) {
        require(addr != address(0), CannotBeZeroAddress());
        require(_whitelistedAddresses.contains(addr), AddressNotInWhitelist(addr));
        _whitelistedAddresses.remove(addr);
        emit WhitelistAddressRemoved(addr);
    }

    /// @notice Enables whitelist enforcement (only whitelisted addresses can initiate swaps)
    function enableWhitelist() external onlyRole(CONFIGURE_ROLE) {
        whitelistEnabled = true;
        emit WhitelistEnabled();
    }

    /// @notice Disables whitelist enforcement (any address can initiate swaps)
    function disableWhitelist() external onlyRole(CONFIGURE_ROLE) {
        whitelistEnabled = false;
        emit WhitelistDisabled();
    }

    // View functions
    /// @notice Returns an array of all supported token addresses
    ///
    /// @return Array of token addresses
    function getSupportedTokens() external view returns (address[] memory) {
        return _supportedTokens.values();
    }

    /// @notice Returns the number of supported tokens
    ///
    /// @return Count of supported tokens
    function getSupportedTokensCount() external view returns (uint256) {
        return _supportedTokens.length();
    }

    /// @notice Returns vault information for a specific token
    ///
    /// @param token Address of the token
    ///
    /// @return TokenVault struct containing reserved amount, enabled status, and decimals
    function getVault(address token) external view returns (TokenVault memory) {
        return _vaults[token];
    }

    /// @notice Returns an array of all whitelisted addresses
    ///
    /// @return Array of whitelisted addresses
    function getWhitelistedAddresses() external view returns (address[] memory) {
        return _whitelistedAddresses.values();
    }

    /// @notice Returns the number of whitelisted addresses
    ///
    /// @return Count of whitelisted addresses
    function getWhitelistedAddressesCount() external view returns (uint256) {
        return _whitelistedAddresses.length();
    }

    // Internal helper functions
    function normalizeDecimals(uint64 amount, uint8 decimalsFrom, uint8 decimalsTo) private pure returns (uint64) {
        if (decimalsFrom == decimalsTo) {
            return amount;
        }

        if (decimalsFrom < decimalsTo) {
            // Scaling up: multiply by 10^decimalsDelta
            uint8 decimalsDelta = decimalsTo - decimalsFrom;

            // Use uint256 to prevent overflow during multiplication
            uint256 multiplier = 10 ** uint256(decimalsDelta);
            uint256 result = uint256(amount) * multiplier;

            // Ensure result fits in uint64
            require(result <= type(uint64).max, DecimalNormalizationOverflow());
            // casting to 'uint64' is safe because we check result <= type(uint64).max above
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint64(result);
        } else {
            // Scaling down: divide by 10^decimalsDelta (no overflow possible)
            // Division automatically rounds down (floor)
            uint8 decimalsDelta = decimalsFrom - decimalsTo;
            uint256 divisor = 10 ** uint256(decimalsDelta);
            // casting to 'uint64' is safe because division can only decrease or maintain the value,
            // and the input amount is already uint64
            // forge-lint: disable-next-line(unsafe-typecast)
            return uint64(uint256(amount) / divisor);
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/5.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}
