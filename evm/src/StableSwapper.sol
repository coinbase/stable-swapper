// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract StableSwapper is Initializable, AccessControlEnumerableUpgradeable, UUPSUpgradeable, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Vault information for a supported token
     * @dev Stores per-token state including reserves, enabled status, and decimal places
     * @param reservedAmount Amount of tokens reserved and not available for withdrawal
     * @param isEnabled Whether the token is currently enabled for swapping
     * @param decimals Number of decimal places the token uses (must be between MIN_DECIMALS and MAX_DECIMALS)
     */
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
    
    /// @notice Role identifier for operations authority (can manage tokens, liquidity, and fees)
    bytes32 public constant OPERATIONS_AUTHORITY = keccak256("OPERATIONS_AUTHORITY");
    
    /// @notice Role identifier for pause authority (can pause/unpause operations and manage whitelist)
    bytes32 public constant PAUSE_AUTHORITY = keccak256("PAUSE_AUTHORITY");
    
    /// @notice Role identifier for upgrade authority (can authorize contract upgrades)
    bytes32 public constant UPGRADE_AUTHORITY = keccak256("UPGRADE_AUTHORITY");

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

    /// @notice Whether swap operations are currently paused
    bool public swapsPaused;
    
    /// @notice Whether liquidity operations (deposits and withdrawals) are currently paused
    bool public liquidityPaused;

    /// @notice Pending upgrade authority in 2-step transfer process (must accept to complete transfer)
    address public pendingUpgradeAuthority;
    
    /// @notice Pending operations authority in 2-step transfer process (must accept to complete transfer)
    address public pendingOperationsAuthority;
    
    /// @notice Pending pause authority in 2-step transfer process (must accept to complete transfer)
    address public pendingPauseAuthority;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/5.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
    
    /**
     * @notice Emitted when the contract is initialized with initial authorities and fee configuration
     * @param upgradeAuthority Address granted the UPGRADE_AUTHORITY role
     * @param operationsAuthority Address granted the OPERATIONS_AUTHORITY role
     * @param pauseAuthority Address granted the PAUSE_AUTHORITY role
     * @param initialFeeRecipient Address that will receive swap fees
     * @param initialFeeRate Initial fee rate in basis points (e.g., 100 = 1%)
     */
    event Initialized(address upgradeAuthority, address operationsAuthority, address pauseAuthority, address initialFeeRecipient, uint64 initialFeeRate);
    
    /**
     * @notice Emitted when a new token is added to the supported tokens list
     * @param token Address of the token that was added
     * @param decimals Number of decimals the token uses
     */
    event TokenAdded(address indexed token, uint8 decimals);
    
    /**
     * @notice Emitted when a token is removed from the supported tokens list
     * @param token Address of the token that was removed
     */
    event TokenRemoved(address indexed token);
    
    /**
     * @notice Emitted when liquidity is deposited into a token vault
     * @param token Address of the token that was deposited
     * @param amount Amount of tokens deposited
     */
    event LiquidityDeposited(address indexed token, uint64 amount);
    
    /**
     * @notice Emitted when a swap is executed
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens provided (before fees)
     * @param amountOut Amount of output tokens sent to recipient (after decimal normalization)
     * @param fee Fee amount collected in input token
     */
    event Swap(address indexed tokenIn, address indexed tokenOut, uint64 amountIn, uint64 amountOut, uint64 fee);
    
    /**
     * @notice Emitted when liquidity is withdrawn from a token vault
     * @param token Address of the token that was withdrawn
     * @param amount Amount of tokens withdrawn
     */
    event LiquidityWithdrawn(address indexed token, uint64 amount);
    
    /**
     * @notice Emitted when the fee recipient address is updated
     * @param newFeeRecipient New address that will receive swap fees
     */
    event FeeRecipientUpdated(address newFeeRecipient);
    
    /**
     * @notice Emitted when the fee rate is updated
     * @param newFeeRate New fee rate in basis points (e.g., 100 = 1%)
     */
    event FeeRateUpdated(uint64 newFeeRate);
    
    /**
     * @notice Emitted when swap operations are paused
     */
    event SwapsPaused();
    
    /**
     * @notice Emitted when swap operations are unpaused
     */
    event SwapsUnpaused();
    
    /**
     * @notice Emitted when liquidity operations (deposits and withdrawals) are paused
     */
    event LiquidityPaused();
    
    /**
     * @notice Emitted when liquidity operations are unpaused
     */
    event LiquidityUnpaused();
    
    /**
     * @notice Emitted when a transfer of the upgrade authority role is proposed
     * @param currentAuthority Address of the current upgrade authority proposing the transfer
     * @param pendingAuthority Address that will receive upgrade authority if they accept
     */
    event UpgradeAuthorityTransferProposed(address currentAuthority, address pendingAuthority);
    
    /**
     * @notice Emitted when the upgrade authority role is transferred to a new address
     * @param previousAuthority Address of the previous upgrade authority
     * @param newUpgradeAuthority Address of the new upgrade authority
     */
    event UpgradeAuthorityUpdated(address previousAuthority, address newUpgradeAuthority);
    
    /**
     * @notice Emitted when a transfer of the operations authority role is proposed
     * @param currentAuthority Address of the current operations authority proposing the transfer
     * @param pendingAuthority Address that will receive operations authority if they accept
     */
    event OperationsAuthorityTransferProposed(address currentAuthority, address pendingAuthority);
    
    /**
     * @notice Emitted when the operations authority role is transferred to a new address
     * @param previousAuthority Address of the previous operations authority
     * @param newOperationsAuthority Address of the new operations authority
     */
    event OperationsAuthorityUpdated(address previousAuthority, address newOperationsAuthority);
    
    /**
     * @notice Emitted when a transfer of the pause authority role is proposed
     * @param currentAuthority Address of the current pause authority proposing the transfer
     * @param pendingAuthority Address that will receive pause authority if they accept
     */
    event PauseAuthorityTransferProposed(address currentAuthority, address pendingAuthority);
    
    /**
     * @notice Emitted when the pause authority role is transferred to a new address
     * @param previousAuthority Address of the previous pause authority
     * @param newPauseAuthority Address of the new pause authority
     */
    event PauseAuthorityUpdated(address previousAuthority, address newPauseAuthority);
    
    /**
     * @notice Emitted when a pending upgrade authority transfer is cancelled
     * @param cancelledAuthority Address of the pending authority that was cancelled
     */
    event UpgradeAuthorityTransferCancelled(address cancelledAuthority);
    
    /**
     * @notice Emitted when a pending operations authority transfer is cancelled
     * @param cancelledAuthority Address of the pending authority that was cancelled
     */
    event OperationsAuthorityTransferCancelled(address cancelledAuthority);
    
    /**
     * @notice Emitted when a pending pause authority transfer is cancelled
     * @param cancelledAuthority Address of the pending authority that was cancelled
     */
    event PauseAuthorityTransferCancelled(address cancelledAuthority);
    
    /**
     * @notice Emitted when a token's reserved amount is updated
     * @param token Address of the token whose reserved amount was updated
     * @param newReservedAmount New reserved amount (cannot be withdrawn from liquidity)
     */
    event ReservedAmountUpdated(address indexed token, uint64 newReservedAmount);
    
    /**
     * @notice Emitted when a token's enabled status is updated
     * @param token Address of the token whose status was updated
     * @param isEnabled True if token is enabled for swaps, false if disabled
     */
    event TokenStatusUpdated(address indexed token, bool isEnabled);
    
    /**
     * @notice Emitted when an address is added to the whitelist
     * @param addr Address that was added to the whitelist
     */
    event WhitelistAddressAdded(address addr);
    
    /**
     * @notice Emitted when an address is removed from the whitelist
     * @param addr Address that was removed from the whitelist
     */
    event WhitelistAddressRemoved(address addr);
    
    /**
     * @notice Emitted when whitelist enforcement is enabled
     * @dev When enabled, only whitelisted addresses can initiate swaps
     */
    event WhitelistEnabled();
    
    /**
     * @notice Emitted when whitelist enforcement is disabled
     * @dev When disabled, any address can initiate swaps
     */
    event WhitelistDisabled();

    error CannotBeZeroAddress();
    error TokenAlreadySupported(address token);
    error TokenNotSupported(address token);
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
    error LiquidityWithdrawExceedsAvailableBalance(address token, uint64 amount, uint256 availableBalance);
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
    error NoPendingAuthorityTransfer();
    error NotPendingAuthority();
    error PendingAuthorityAlreadySet();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the StableSwapper contract with authorities and fee configuration
     * @param upgradeAuthority Address that can authorize contract upgrades
     * @param operationsAuthority Address that can perform operational tasks (add/remove tokens, manage liquidity)
     * @param pauseAuthority Address that can pause/unpause swaps and liquidity operations
     * @param initialFeeRecipient Address that will receive swap fees
     * @param initialFeeRate Fee rate in basis points (e.g., 100 = 1%)
     */
    function initialize(address upgradeAuthority, address operationsAuthority, address pauseAuthority, address initialFeeRecipient, uint64 initialFeeRate) public initializer {
        __AccessControlEnumerable_init();
        
        require(initialFeeRate <= MAX_FEE_RATE, FeeRateExceedsMaximum(initialFeeRate));

        _grantRole(UPGRADE_AUTHORITY, upgradeAuthority);
        _grantRole(OPERATIONS_AUTHORITY, operationsAuthority);
        _grantRole(PAUSE_AUTHORITY, pauseAuthority);

        feeRecipient = initialFeeRecipient;
        feeRate = initialFeeRate;
        swapsPaused = false;
        liquidityPaused = false;
        whitelistEnabled = false;
        contractVersion = 1;

        emit Initialized(upgradeAuthority, operationsAuthority, pauseAuthority, initialFeeRecipient, initialFeeRate);
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation contract
     * Only addresses with UPGRADE_AUTHORITY role can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_AUTHORITY) {
        // Additional upgrade authorization logic can be added here
        // e.g., timelock checks, version validation, etc.
    }

    /**
     * @notice Adds a new token to the list of supported tokens for swapping
     * @param token Address of the ERC20 token to add (must have 6-9 decimals)
     */
    function addToken(address token) external onlyRole(OPERATIONS_AUTHORITY) {
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
        _vaults[token] = TokenVault(0, true, decimals);
        emit TokenAdded(token, decimals);
    }

    /**
     * @notice Removes a token from the list of supported tokens (token must be disabled and have zero balance)
     * @param token Address of the token to remove
     */
    function removeToken(address token) external onlyRole(OPERATIONS_AUTHORITY) {
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

    /**
     * @notice Deposits liquidity into the contract for a specific token
     * @param token Address of the token to deposit
     * @param amount Amount of tokens to deposit
     */
    function deposit_liquidity(address token, uint64 amount) external onlyRole(OPERATIONS_AUTHORITY) {
        require(token != address(0), CannotBeZeroAddress());
        require(!liquidityPaused, LiquidityCannotBePaused());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        require(amount > 0, CannotBeZeroAmount());
        
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        emit LiquidityDeposited(token, amount);
    }

    /**
     * @notice Swaps one stablecoin for another with automatic decimal normalization and fee deduction
     * @param tokenIn Address of the token being swapped from
     * @param tokenOut Address of the token being swapped to
     * @param amountIn Amount of tokenIn to swap (before fees)
     * @param minAmountOut Minimum acceptable amount of tokenOut to receive (for slippage protection)
     * @param recipient Address that will receive the output tokens
     */
    function swap(address tokenIn, address tokenOut, uint64 amountIn, uint64 minAmountOut, address recipient) external nonReentrant {
        // CHECKS: All validation and calculations
        require(!swapsPaused, SwapsCannotBePaused());
        require(tokenIn != address(0), CannotBeZeroAddress());
        require(tokenOut != address(0), CannotBeZeroAddress());
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

    /**
     * @notice Withdraws liquidity from the contract for a specific token
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw (must not exceed available balance minus reserved amount)
     */
    function withdraw_liquidity(address token, uint64 amount) external onlyRole(OPERATIONS_AUTHORITY) {
        require(token != address(0), CannotBeZeroAddress());
        require(!liquidityPaused, LiquidityCannotBePaused());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        require(amount > 0, CannotBeZeroAmount());

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, LiquidityWithdrawExceedsBalance(token, amount, balance));
        
        // Check that withdrawal doesn't exceed available balance (balance - reserved amount)
        uint256 availableBalance = balance - _vaults[token].reservedAmount;
        require(amount <= availableBalance, LiquidityWithdrawExceedsAvailableBalance(token, amount, availableBalance));
        
        SafeERC20.safeTransfer(IERC20(token), msg.sender, amount);

        emit LiquidityWithdrawn(token, amount);
    }

    /**
     * @notice Updates the address that receives swap fees
     * @param newFeeRecipient New address to receive fees
     */
    function updateFeeRecipient(address newFeeRecipient) external onlyRole(OPERATIONS_AUTHORITY) {
        require(newFeeRecipient != address(0), CannotBeZeroAddress());
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    /**
     * @notice Updates the fee rate charged on swaps
     * @param newFeeRate New fee rate in basis points (e.g., 100 = 1%, max 1000 = 10%)
     */
    function updateFeeRate(uint64 newFeeRate) external onlyRole(OPERATIONS_AUTHORITY) {
        require(newFeeRate <= MAX_FEE_RATE, FeeRateExceedsMaximum(newFeeRate));
        feeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }

    /**
     * @notice Pauses all swap operations
     */
    function pauseSwaps() external onlyRole(PAUSE_AUTHORITY) {
        swapsPaused = true;
        emit SwapsPaused();
    }

    /**
     * @notice Unpauses swap operations
     */
    function unpauseSwaps() external onlyRole(PAUSE_AUTHORITY) {
        swapsPaused = false;
        emit SwapsUnpaused();
    }

    /**
     * @notice Pauses all liquidity deposit and withdrawal operations
     */
    function pauseLiquidity() external onlyRole(PAUSE_AUTHORITY) {
        liquidityPaused = true;
        emit LiquidityPaused();
    }

    /**
     * @notice Unpauses liquidity operations
     */
    function unpauseLiquidity() external onlyRole(PAUSE_AUTHORITY) {
        liquidityPaused = false;
        emit LiquidityUnpaused();
    }

    /**
     * @notice Proposes a transfer of the upgrade authority role to a new address (step 1 of 2)
     * @dev The new authority must call acceptUpgradeAuthority() to complete the transfer
     * @param newUpgradeAuthority New address to receive upgrade authority
     */
    function proposeUpgradeAuthorityTransfer(address newUpgradeAuthority) external onlyRole(UPGRADE_AUTHORITY) {
        require(newUpgradeAuthority != address(0), CannotBeZeroAddress());
        require(pendingUpgradeAuthority == address(0), PendingAuthorityAlreadySet());
        pendingUpgradeAuthority = newUpgradeAuthority;
        emit UpgradeAuthorityTransferProposed(msg.sender, newUpgradeAuthority);
    }

    /**
     * @notice Accepts the upgrade authority role transfer (step 2 of 2)
     * @dev Can only be called by the pending upgrade authority
     */
    function acceptUpgradeAuthority() external {
        require(pendingUpgradeAuthority != address(0), NoPendingAuthorityTransfer());
        require(msg.sender == pendingUpgradeAuthority, NotPendingAuthority());
        
        address previousAuthority = _getCurrentUpgradeAuthority();
        address newAuthority = pendingUpgradeAuthority;
        
        // Clear pending state first (CEI pattern)
        pendingUpgradeAuthority = address(0);
        
        // Transfer role
        _grantRole(UPGRADE_AUTHORITY, newAuthority);
        if (previousAuthority != address(0)) {
            _revokeRole(UPGRADE_AUTHORITY, previousAuthority);
        }
        
        emit UpgradeAuthorityUpdated(previousAuthority, newAuthority);
    }

    /**
     * @notice Cancels a pending upgrade authority transfer
     * @dev Can only be called by the current upgrade authority
     */
    function cancelUpgradeAuthorityTransfer() external onlyRole(UPGRADE_AUTHORITY) {
        require(pendingUpgradeAuthority != address(0), NoPendingAuthorityTransfer());
        address cancelledAuthority = pendingUpgradeAuthority;
        pendingUpgradeAuthority = address(0);
        emit UpgradeAuthorityTransferCancelled(cancelledAuthority);
    }

    /**
     * @notice Proposes a transfer of the operations authority role to a new address (step 1 of 2)
     * @dev The new authority must call acceptOperationsAuthority() to complete the transfer
     * @param newOperationsAuthority New address to receive operations authority
     */
    function proposeOperationsAuthorityTransfer(address newOperationsAuthority) external onlyRole(OPERATIONS_AUTHORITY) {
        require(newOperationsAuthority != address(0), CannotBeZeroAddress());
        require(pendingOperationsAuthority == address(0), PendingAuthorityAlreadySet());
        pendingOperationsAuthority = newOperationsAuthority;
        emit OperationsAuthorityTransferProposed(msg.sender, newOperationsAuthority);
    }

    /**
     * @notice Accepts the operations authority role transfer (step 2 of 2)
     * @dev Can only be called by the pending operations authority
     */
    function acceptOperationsAuthority() external {
        require(pendingOperationsAuthority != address(0), NoPendingAuthorityTransfer());
        require(msg.sender == pendingOperationsAuthority, NotPendingAuthority());
        
        address previousAuthority = _getCurrentOperationsAuthority();
        address newAuthority = pendingOperationsAuthority;
        
        // Clear pending state first (CEI pattern)
        pendingOperationsAuthority = address(0);
        
        // Transfer role
        _grantRole(OPERATIONS_AUTHORITY, newAuthority);
        if (previousAuthority != address(0)) {
            _revokeRole(OPERATIONS_AUTHORITY, previousAuthority);
        }
        
        emit OperationsAuthorityUpdated(previousAuthority, newAuthority);
    }

    /**
     * @notice Cancels a pending operations authority transfer
     * @dev Can only be called by the current operations authority
     */
    function cancelOperationsAuthorityTransfer() external onlyRole(OPERATIONS_AUTHORITY) {
        require(pendingOperationsAuthority != address(0), NoPendingAuthorityTransfer());
        address cancelledAuthority = pendingOperationsAuthority;
        pendingOperationsAuthority = address(0);
        emit OperationsAuthorityTransferCancelled(cancelledAuthority);
    }

    /**
     * @notice Proposes a transfer of the pause authority role to a new address (step 1 of 2)
     * @dev The new authority must call acceptPauseAuthority() to complete the transfer
     * @param newPauseAuthority New address to receive pause authority
     */
    function proposePauseAuthorityTransfer(address newPauseAuthority) external onlyRole(PAUSE_AUTHORITY) {
        require(newPauseAuthority != address(0), CannotBeZeroAddress());
        require(pendingPauseAuthority == address(0), PendingAuthorityAlreadySet());
        pendingPauseAuthority = newPauseAuthority;
        emit PauseAuthorityTransferProposed(msg.sender, newPauseAuthority);
    }

    /**
     * @notice Accepts the pause authority role transfer (step 2 of 2)
     * @dev Can only be called by the pending pause authority
     */
    function acceptPauseAuthority() external {
        require(pendingPauseAuthority != address(0), NoPendingAuthorityTransfer());
        require(msg.sender == pendingPauseAuthority, NotPendingAuthority());
        
        address previousAuthority = _getCurrentPauseAuthority();
        address newAuthority = pendingPauseAuthority;
        
        // Clear pending state first (CEI pattern)
        pendingPauseAuthority = address(0);
        
        // Transfer role
        _grantRole(PAUSE_AUTHORITY, newAuthority);
        if (previousAuthority != address(0)) {
            _revokeRole(PAUSE_AUTHORITY, previousAuthority);
        }
        
        emit PauseAuthorityUpdated(previousAuthority, newAuthority);
    }

    /**
     * @notice Cancels a pending pause authority transfer
     * @dev Can only be called by the current pause authority
     */
    function cancelPauseAuthorityTransfer() external onlyRole(PAUSE_AUTHORITY) {
        require(pendingPauseAuthority != address(0), NoPendingAuthorityTransfer());
        address cancelledAuthority = pendingPauseAuthority;
        pendingPauseAuthority = address(0);
        emit PauseAuthorityTransferCancelled(cancelledAuthority);
    }

    /**
     * @notice Updates the reserved amount for a token (amount that cannot be withdrawn)
     * @param token Address of the token
     * @param newReservedAmount New reserved amount (must not exceed current balance)
     */
    function updateReservedAmount(address token, uint64 newReservedAmount) external onlyRole(OPERATIONS_AUTHORITY) {
        require(token != address(0), CannotBeZeroAddress());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        
        // Safety check: reserved amount must not exceed balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(newReservedAmount <= balance, ReservedAmountExceedsBalance(token, newReservedAmount, balance));
        
        _vaults[token].reservedAmount = newReservedAmount;
        emit ReservedAmountUpdated(token, newReservedAmount);
    }   

    /**
     * @notice Enables or disables a token for swapping
     * @param token Address of the token
     * @param isEnabled True to enable, false to disable
     */
    function updateTokenStatus(address token, bool isEnabled) external onlyRole(PAUSE_AUTHORITY) {
        require(token != address(0), CannotBeZeroAddress());
        require(_supportedTokens.contains(token), TokenNotSupported(token));
        _vaults[token].isEnabled = isEnabled;
        emit TokenStatusUpdated(token, isEnabled);
    }

    /**
     * @notice Adds an address to the whitelist (allowing it to initiate swaps when whitelist is enabled)
     * @param addr Address to add to whitelist
     */
    function addToWhitelist(address addr) external onlyRole(PAUSE_AUTHORITY) {
        require(addr != address(0), CannotBeZeroAddress());
        require(!_whitelistedAddresses.contains(addr), AddressAlreadyInWhitelist(addr));
        require(_whitelistedAddresses.length() < MAX_WHITELISTED_ADDRESSES, WhitelistExceedsMaximum(MAX_WHITELISTED_ADDRESSES));
        _whitelistedAddresses.add(addr);
        emit WhitelistAddressAdded(addr);
    }

    /**
     * @notice Removes an address from the whitelist
     * @param addr Address to remove from whitelist
     */
    function removeFromWhitelist(address addr) external onlyRole(PAUSE_AUTHORITY) {
        require(addr != address(0), CannotBeZeroAddress());
        require(_whitelistedAddresses.contains(addr), AddressNotInWhitelist(addr));
        _whitelistedAddresses.remove(addr);
        emit WhitelistAddressRemoved(addr);
    }

    /**
     * @notice Enables whitelist enforcement (only whitelisted addresses can initiate swaps)
     */
    function enableWhitelist() external onlyRole(PAUSE_AUTHORITY) {
        whitelistEnabled = true;
        emit WhitelistEnabled();
    }

    /**
     * @notice Disables whitelist enforcement (any address can initiate swaps)
     */
    function disableWhitelist() external onlyRole(PAUSE_AUTHORITY) {
        whitelistEnabled = false;
        emit WhitelistDisabled();
    }

    // View functions
    /**
     * @notice Returns an array of all supported token addresses
     * @return Array of token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return _supportedTokens.values();
    }

    /**
     * @notice Returns the number of supported tokens
     * @return Count of supported tokens
     */
    function getSupportedTokensCount() external view returns (uint256) {
        return _supportedTokens.length();
    }

    /**
     * @notice Returns vault information for a specific token
     * @param token Address of the token
     * @return TokenVault struct containing reserved amount, enabled status, and decimals
     */
    function getVault(address token) external view returns (TokenVault memory) {
        return _vaults[token];
    }

    /**
     * @notice Returns an array of all whitelisted addresses
     * @return Array of whitelisted addresses
     */
    function getWhitelistedAddresses() external view returns (address[] memory) {
        return _whitelistedAddresses.values();
    }

    /**
     * @notice Returns the number of whitelisted addresses
     * @return Count of whitelisted addresses
     */
    function getWhitelistedAddressesCount() external view returns (uint256) {
        return _whitelistedAddresses.length();
    }

    // Internal helper functions
    /**
     * @dev Returns the current upgrade authority address by finding who has the role
     * @return The address of the current upgrade authority, or address(0) if none
     */
    function _getCurrentUpgradeAuthority() private view returns (address) {
        uint256 memberCount = getRoleMemberCount(UPGRADE_AUTHORITY);
        if (memberCount == 0) {
            return address(0);
        }
        return getRoleMember(UPGRADE_AUTHORITY, 0);
    }

    /**
     * @dev Returns the current operations authority address by finding who has the role
     * @return The address of the current operations authority, or address(0) if none
     */
    function _getCurrentOperationsAuthority() private view returns (address) {
        uint256 memberCount = getRoleMemberCount(OPERATIONS_AUTHORITY);
        if (memberCount == 0) {
            return address(0);
        }
        return getRoleMember(OPERATIONS_AUTHORITY, 0);
    }

    /**
     * @dev Returns the current pause authority address by finding who has the role
     * @return The address of the current pause authority, or address(0) if none
     */
    function _getCurrentPauseAuthority() private view returns (address) {
        uint256 memberCount = getRoleMemberCount(PAUSE_AUTHORITY);
        if (memberCount == 0) {
            return address(0);
        }
        return getRoleMember(PAUSE_AUTHORITY, 0);
    }

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
            return uint64(result);
        } else {
            // Scaling down: divide by 10^decimalsDelta (no overflow possible)
            // Division automatically rounds down (floor)
            uint8 decimalsDelta = decimalsFrom - decimalsTo;
            uint256 divisor = 10 ** uint256(decimalsDelta);
            return uint64(uint256(amount) / divisor);
        }
    }
}