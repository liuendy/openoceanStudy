// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title OpenOcean Aggregator V1
 * @author OpenOcean Team
 * @notice Production-ready DEX aggregator contract with advanced routing capabilities
 * @dev Implements gas optimization, security best practices, and modular design patterns
 */

// ====== Interfaces ======

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

// ====== Libraries ======

/**
 * @title SafeERC20
 * @notice Safe wrapper for ERC20 operations that handles non-standard tokens
 */
library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: operation did not succeed");
        }
    }
}

/**
 * @title ReentrancyGuard
 * @notice Prevents reentrancy attacks
 */
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/**
 * @title Pausable
 * @notice Emergency pause mechanism
 */
abstract contract Pausable {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/**
 * @title Ownable
 * @notice Provides basic access control mechanism
 */
abstract contract Ownable {
    address private _owner;
    address private _pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function acceptOwnership() public {
        require(pendingOwner() == msg.sender, "Ownable: caller is not the pending owner");
        _transferOwnership(msg.sender);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// ====== Main Contract ======

contract OpenOceanAggregatorV1 is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ====== Constants ======
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant MAX_SLIPPAGE = 5000; // 50%

    // ====== State Variables ======
    address public immutable WETH;

    // Fee configuration
    uint256 public feeRate; // basis points (e.g., 30 = 0.3%)
    address public feeCollector;

    // Security
    mapping(address => bool) public authorized;
    mapping(address => bool) public whitelistedRouters;

    // Statistics
    uint256 public totalVolume;
    uint256 public totalFeeCollected;

    // ====== Structs ======

    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags; // Bit flags for swap options
    }

    struct RouteDescription {
        address target;     // DEX router address
        uint256 percentage; // Percentage of input (basis points)
        bytes payload;      // Encoded call data
    }

    // ====== Events ======

    event Swapped(
        address indexed sender,
        address indexed srcToken,
        address indexed dstToken,
        uint256 srcAmount,
        uint256 dstAmount,
        uint256 feeAmount
    );

    event FeeUpdated(uint256 newFeeRate, address newFeeCollector);
    event RouterWhitelisted(address router, bool status);
    event EmergencyWithdraw(address token, uint256 amount);

    // ====== Modifiers ======

    modifier onlyAuthorized() {
        require(authorized[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier ensureDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "Transaction expired");
        _;
    }

    // ====== Constructor ======

    constructor(address _weth) {
        require(_weth != address(0), "Invalid WETH address");
        WETH = _weth;
        feeCollector = msg.sender;
        feeRate = 0; // Start with 0 fee
    }

    // ====== Main Functions ======

    /**
     * @notice Execute a token swap through multiple DEXs
     * @dev Main entry point for aggregated swaps
     * @param desc Swap description containing tokens and amounts
     * @param routes Array of route descriptions for splitting
     * @param deadline Transaction deadline timestamp
     * @return returnAmount The actual amount of destination tokens received
     */
    function swap(
        SwapDescription calldata desc,
        RouteDescription[] calldata routes,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        whenNotPaused
        ensureDeadline(deadline)
        returns (uint256 returnAmount)
    {
        // Input validation
        require(desc.amount > 0, "Invalid amount");
        require(desc.minReturnAmount > 0, "Invalid min return");
        require(desc.srcToken != desc.dstToken, "Same token swap");
        require(routes.length > 0 && routes.length <= 5, "Invalid routes");

        // Validate percentages sum to 100%
        uint256 totalPercentage;
        for (uint256 i = 0; i < routes.length;) {
            totalPercentage += routes[i].percentage;
            unchecked { ++i; }
        }
        require(totalPercentage == FEE_DENOMINATOR, "Invalid percentages");

        // Handle input tokens
        if (_isETH(desc.srcToken)) {
            require(msg.value == desc.amount, "Invalid ETH amount");
            // Wrap ETH to WETH
            IWETH(WETH).deposit{value: desc.amount}();
        } else {
            require(msg.value == 0, "Unexpected ETH sent");
            IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), desc.amount);
        }

        // Execute routes
        returnAmount = _executeRoutes(desc, routes);

        // Check slippage
        require(returnAmount >= desc.minReturnAmount, "Return amount too low");

        // Handle fees
        uint256 feeAmount;
        if (feeRate > 0 && feeCollector != address(0)) {
            feeAmount = (returnAmount * feeRate) / FEE_DENOMINATOR;
            returnAmount -= feeAmount;
            totalFeeCollected += feeAmount;
        }

        // Handle output tokens
        if (_isETH(desc.dstToken)) {
            // Unwrap WETH to ETH
            IWETH(WETH).withdraw(returnAmount);
            _sendETH(desc.dstReceiver, returnAmount);
            if (feeAmount > 0) {
                IWETH(WETH).withdraw(feeAmount);
                _sendETH(payable(feeCollector), feeAmount);
            }
        } else {
            IERC20(desc.dstToken).safeTransfer(desc.dstReceiver, returnAmount);
            if (feeAmount > 0) {
                IERC20(desc.dstToken).safeTransfer(feeCollector, feeAmount);
            }
        }

        // Update statistics
        totalVolume += desc.amount;

        emit Swapped(
            msg.sender,
            desc.srcToken,
            desc.dstToken,
            desc.amount,
            returnAmount,
            feeAmount
        );
    }

    /**
     * @notice Execute routes through different DEXs
     * @dev Internal function to split and execute swaps
     */
    function _executeRoutes(
        SwapDescription calldata desc,
        RouteDescription[] calldata routes
    ) private returns (uint256 totalOutput) {
        address srcToken = _isETH(desc.srcToken) ? WETH : desc.srcToken;
        address dstToken = _isETH(desc.dstToken) ? WETH : desc.dstToken;

        for (uint256 i = 0; i < routes.length;) {
            RouteDescription calldata route = routes[i];

            // Validate router is whitelisted
            require(whitelistedRouters[route.target], "Router not whitelisted");

            // Calculate input amount for this route
            uint256 routeAmount = (desc.amount * route.percentage) / FEE_DENOMINATOR;

            // Approve tokens to router
            IERC20(srcToken).safeApprove(route.target, routeAmount);

            // Record balance before swap
            uint256 balanceBefore = IERC20(dstToken).balanceOf(address(this));

            // Execute swap on target DEX
            (bool success,) = route.target.call(route.payload);
            require(success, "Route execution failed");

            // Calculate output from this route
            uint256 balanceAfter = IERC20(dstToken).balanceOf(address(this));
            uint256 routeOutput = balanceAfter - balanceBefore;

            // Reset approval
            IERC20(srcToken).safeApprove(route.target, 0);

            totalOutput += routeOutput;

            unchecked { ++i; }
        }
    }

    /**
     * @notice Rescue stuck tokens
     * @dev Emergency function to withdraw stuck tokens
     */
    function rescueTokens(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (_isETH(token)) {
            _sendETH(payable(owner()), amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
        emit EmergencyWithdraw(token, amount);
    }

    // ====== Admin Functions ======

    /**
     * @notice Update fee configuration
     */
    function setFeeConfig(
        uint256 _feeRate,
        address _feeCollector
    ) external onlyOwner {
        require(_feeRate <= 100, "Fee too high"); // Max 1%
        require(_feeCollector != address(0), "Invalid fee collector");

        feeRate = _feeRate;
        feeCollector = _feeCollector;

        emit FeeUpdated(_feeRate, _feeCollector);
    }

    /**
     * @notice Whitelist/blacklist DEX routers
     */
    function setRouterWhitelist(
        address router,
        bool status
    ) external onlyOwner {
        whitelistedRouters[router] = status;
        emit RouterWhitelisted(router, status);
    }

    /**
     * @notice Add/remove authorized callers
     */
    function setAuthorized(
        address user,
        bool status
    ) external onlyOwner {
        authorized[user] = status;
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyAuthorized {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ====== View Functions ======

    /**
     * @notice Get contract statistics
     */
    function getStatistics() external view returns (
        uint256 volume,
        uint256 feeCollected,
        uint256 currentFeeRate,
        address currentFeeCollector
    ) {
        return (totalVolume, totalFeeCollected, feeRate, feeCollector);
    }

    // ====== Internal Utilities ======

    function _isETH(address token) private pure returns (bool) {
        return token == ETH_ADDRESS;
    }

    function _sendETH(address payable recipient, uint256 amount) private {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // ====== Receive ETH ======

    receive() external payable {
        // Accept ETH for WETH wrapping
    }

    fallback() external payable {
        revert("Direct ETH transfers not accepted");
    }
}

// ====== DEX Adapters ======

/**
 * @title UniswapV3Adapter
 * @notice Adapter for interacting with Uniswap V3
 */
contract UniswapV3Adapter {
    address private constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function swapOnUniswapV3(
        ExactInputSingleParams memory params
    ) external returns (uint256 amountOut) {
        // Implementation would interact with actual Uniswap V3 router
        // This is a placeholder for the actual implementation
    }
}

/**
 * @title CurveAdapter
 * @notice Adapter for interacting with Curve pools
 */
contract CurveAdapter {
    function swapOnCurve(
        address pool,
        int128 i,
        int128 j,
        uint256 amount,
        uint256 minOut
    ) external returns (uint256 amountOut) {
        // Implementation would interact with actual Curve pools
        // This is a placeholder for the actual implementation
    }
}

/**
 * @title BalancerAdapter
 * @notice Adapter for interacting with Balancer V2
 */
contract BalancerAdapter {
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    struct SingleSwap {
        bytes32 poolId;
        uint8 kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    function swapOnBalancer(
        SingleSwap memory singleSwap,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        // Implementation would interact with actual Balancer Vault
        // This is a placeholder for the actual implementation
    }
}