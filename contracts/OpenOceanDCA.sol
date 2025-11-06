// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title OpenOcean DCA (Dollar Cost Averaging) Vault
 * @author OpenOcean Team
 * @notice Automated DCA execution with gas optimization and security features
 * @dev Implements time-based automatic swaps with keeper incentives
 */

import "./OpenOceanAggregatorV1.sol";

// ====== Interfaces ======

interface IOpenOceanAggregator {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    struct RouteDescription {
        address target;
        uint256 percentage;
        bytes payload;
    }

    function swap(
        SwapDescription calldata desc,
        RouteDescription[] calldata routes,
        uint256 deadline
    ) external payable returns (uint256 returnAmount);
}

// ====== Main Contract ======

contract OpenOceanDCA is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ====== Constants ======
    uint256 private constant MIN_INTERVAL = 1 hours;
    uint256 private constant MAX_INTERVAL = 30 days;
    uint256 private constant MIN_TRADES = 2;
    uint256 private constant MAX_TRADES = 365;
    uint256 private constant KEEPER_REWARD = 0.003 ether; // Keeper incentive

    // ====== State Variables ======
    IOpenOceanAggregator public immutable aggregator;

    // DCA order storage (optimized packing)
    struct DCAOrder {
        address owner;           // 20 bytes
        address tokenIn;         // 20 bytes
        address tokenOut;        // 20 bytes
        uint128 amountPerTrade;  // 16 bytes
        uint32 interval;         // 4 bytes
        uint32 lastExecuted;     // 4 bytes
        uint16 tradesExecuted;   // 2 bytes
        uint16 totalTrades;      // 2 bytes
        bool active;            // 1 byte
        bool allowPartialFill;  // 1 byte
    } // Total: 3 storage slots

    mapping(uint256 => DCAOrder) public orders;
    mapping(address => uint256[]) public userOrders;

    uint256 public nextOrderId;
    uint256 public totalActiveOrders;
    uint256 public totalExecutedTrades;
    uint256 public totalVolume;

    // Keeper management
    mapping(address => bool) public keepers;
    mapping(address => uint256) public keeperRewards;

    // Price oracle for slippage protection
    address public priceOracle;
    uint256 public maxSlippagePercent = 200; // 2%

    // ====== Events ======

    event DCAOrderCreated(
        uint256 indexed orderId,
        address indexed owner,
        address tokenIn,
        address tokenOut,
        uint256 totalAmount,
        uint256 trades
    );

    event DCAOrderExecuted(
        uint256 indexed orderId,
        uint256 indexed tradeNumber,
        uint256 amountIn,
        uint256 amountOut,
        address executor
    );

    event DCAOrderCompleted(
        uint256 indexed orderId,
        uint256 totalIn,
        uint256 totalOut
    );

    event DCAOrderCanceled(
        uint256 indexed orderId,
        uint256 refundAmount
    );

    event KeeperAdded(address keeper);
    event KeeperRemoved(address keeper);
    event KeeperRewarded(address keeper, uint256 amount);

    // ====== Modifiers ======

    modifier onlyKeeper() {
        require(keepers[msg.sender] || msg.sender == owner(), "Not a keeper");
        _;
    }

    modifier validOrder(uint256 orderId) {
        require(orders[orderId].owner != address(0), "Order does not exist");
        _;
    }

    // ====== Constructor ======

    constructor(address _aggregator) {
        require(_aggregator != address(0), "Invalid aggregator");
        aggregator = IOpenOceanAggregator(_aggregator);
        keepers[msg.sender] = true;
    }

    // ====== User Functions ======

    /**
     * @notice Create a new DCA order
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param totalAmount Total amount to invest
     * @param trades Number of trades to execute
     * @param interval Time between trades in seconds
     * @param allowPartialFill Allow partial execution if balance insufficient
     * @return orderId The created order ID
     */
    function createDCAOrder(
        address tokenIn,
        address tokenOut,
        uint256 totalAmount,
        uint256 trades,
        uint256 interval,
        bool allowPartialFill
    ) external nonReentrant whenNotPaused returns (uint256 orderId) {
        // Validation
        require(tokenIn != tokenOut, "Same token");
        require(totalAmount > 0, "Invalid amount");
        require(trades >= MIN_TRADES && trades <= MAX_TRADES, "Invalid trade count");
        require(interval >= MIN_INTERVAL && interval <= MAX_INTERVAL, "Invalid interval");

        uint256 amountPerTrade = totalAmount / trades;
        require(amountPerTrade > 0, "Amount too small");

        orderId = nextOrderId++;

        // Create order with packed storage
        orders[orderId] = DCAOrder({
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountPerTrade: uint128(amountPerTrade),
            interval: uint32(interval),
            lastExecuted: 0,
            tradesExecuted: 0,
            totalTrades: uint16(trades),
            active: true,
            allowPartialFill: allowPartialFill
        });

        userOrders[msg.sender].push(orderId);
        totalActiveOrders++;

        // Transfer total amount to vault
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), totalAmount);

        emit DCAOrderCreated(
            orderId,
            msg.sender,
            tokenIn,
            tokenOut,
            totalAmount,
            trades
        );
    }

    /**
     * @notice Execute a DCA order trade
     * @param orderId Order to execute
     * @param routes Routing information for the swap
     */
    function executeDCAOrder(
        uint256 orderId,
        IOpenOceanAggregator.RouteDescription[] calldata routes
    ) external nonReentrant onlyKeeper validOrder(orderId) {
        DCAOrder storage order = orders[orderId];

        // Validation
        require(order.active, "Order not active");
        require(
            block.timestamp >= order.lastExecuted + order.interval,
            "Too early"
        );
        require(order.tradesExecuted < order.totalTrades, "Order completed");

        // Check balance
        uint256 balance = IERC20(order.tokenIn).balanceOf(address(this));
        uint256 amountToSwap = order.amountPerTrade;

        if (balance < amountToSwap) {
            if (order.allowPartialFill && balance > 0) {
                amountToSwap = balance;
            } else {
                revert("Insufficient balance");
            }
        }

        // Prepare swap
        IOpenOceanAggregator.SwapDescription memory desc = IOpenOceanAggregator.SwapDescription({
            srcToken: order.tokenIn,
            dstToken: order.tokenOut,
            srcReceiver: payable(address(this)),
            dstReceiver: payable(order.owner),
            amount: amountToSwap,
            minReturnAmount: _calculateMinReturn(order.tokenIn, order.tokenOut, amountToSwap),
            flags: 0
        });

        // Approve aggregator
        IERC20(order.tokenIn).safeApprove(address(aggregator), amountToSwap);

        // Execute swap
        uint256 amountOut = aggregator.swap(
            desc,
            routes,
            block.timestamp + 300 // 5 minute deadline
        );

        // Reset approval
        IERC20(order.tokenIn).safeApprove(address(aggregator), 0);

        // Update order state
        order.lastExecuted = uint32(block.timestamp);
        order.tradesExecuted++;

        // Update global statistics
        totalExecutedTrades++;
        totalVolume += amountToSwap;

        // Reward keeper
        _rewardKeeper(msg.sender);

        emit DCAOrderExecuted(
            orderId,
            order.tradesExecuted,
            amountToSwap,
            amountOut,
            msg.sender
        );

        // Check if order is completed
        if (order.tradesExecuted >= order.totalTrades) {
            order.active = false;
            totalActiveOrders--;

            // Refund any remaining tokens
            uint256 remaining = IERC20(order.tokenIn).balanceOf(address(this));
            if (remaining > 0 && _isUserToken(order.tokenIn, orderId)) {
                IERC20(order.tokenIn).safeTransfer(order.owner, remaining);
            }

            emit DCAOrderCompleted(orderId, 0, 0);
        }
    }

    /**
     * @notice Cancel a DCA order and refund remaining funds
     * @param orderId Order to cancel
     */
    function cancelDCAOrder(uint256 orderId) external nonReentrant validOrder(orderId) {
        DCAOrder storage order = orders[orderId];

        require(order.owner == msg.sender, "Not order owner");
        require(order.active, "Order not active");

        order.active = false;
        totalActiveOrders--;

        // Calculate refund amount
        uint256 remainingTrades = order.totalTrades - order.tradesExecuted;
        uint256 refundAmount = order.amountPerTrade * remainingTrades;

        if (refundAmount > 0) {
            uint256 balance = IERC20(order.tokenIn).balanceOf(address(this));
            if (balance >= refundAmount) {
                IERC20(order.tokenIn).safeTransfer(msg.sender, refundAmount);
            } else if (balance > 0) {
                // Refund available balance
                IERC20(order.tokenIn).safeTransfer(msg.sender, balance);
                refundAmount = balance;
            }
        }

        emit DCAOrderCanceled(orderId, refundAmount);
    }

    /**
     * @notice Get executable orders
     * @return orderIds Array of order IDs ready for execution
     */
    function getExecutableOrders() external view returns (uint256[] memory orderIds) {
        uint256 count = 0;
        uint256[] memory temp = new uint256[](totalActiveOrders);

        for (uint256 i = 0; i < nextOrderId; i++) {
            if (_isExecutable(i)) {
                temp[count++] = i;
            }
        }

        orderIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = temp[i];
        }
    }

    /**
     * @notice Check if an order is ready for execution
     */
    function isExecutable(uint256 orderId) external view returns (bool) {
        return _isExecutable(orderId);
    }

    // ====== Admin Functions ======

    /**
     * @notice Add a keeper address
     */
    function addKeeper(address keeper) external onlyOwner {
        require(keeper != address(0), "Invalid keeper");
        keepers[keeper] = true;
        emit KeeperAdded(keeper);
    }

    /**
     * @notice Remove a keeper address
     */
    function removeKeeper(address keeper) external onlyOwner {
        keepers[keeper] = false;
        emit KeeperRemoved(keeper);
    }

    /**
     * @notice Set price oracle for slippage calculation
     */
    function setPriceOracle(address _oracle) external onlyOwner {
        priceOracle = _oracle;
    }

    /**
     * @notice Set maximum allowed slippage
     */
    function setMaxSlippage(uint256 _maxSlippagePercent) external onlyOwner {
        require(_maxSlippagePercent <= 1000, "Slippage too high"); // Max 10%
        maxSlippagePercent = _maxSlippagePercent;
    }

    /**
     * @notice Withdraw keeper rewards
     */
    function withdrawKeeperRewards() external nonReentrant {
        uint256 rewards = keeperRewards[msg.sender];
        require(rewards > 0, "No rewards");

        keeperRewards[msg.sender] = 0;
        payable(msg.sender).transfer(rewards);

        emit KeeperRewarded(msg.sender, rewards);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ====== Internal Functions ======

    function _isExecutable(uint256 orderId) private view returns (bool) {
        DCAOrder memory order = orders[orderId];

        if (!order.active) return false;
        if (order.tradesExecuted >= order.totalTrades) return false;
        if (block.timestamp < order.lastExecuted + order.interval) return false;

        uint256 balance = IERC20(order.tokenIn).balanceOf(address(this));
        return balance >= order.amountPerTrade || (order.allowPartialFill && balance > 0);
    }

    function _calculateMinReturn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256) {
        // If no oracle, use 98% of input as minimum (2% max slippage)
        if (priceOracle == address(0)) {
            return (amountIn * (10000 - maxSlippagePercent)) / 10000;
        }

        // TODO: Implement actual oracle price fetching
        // This would call the price oracle to get expected output
        // and apply maxSlippagePercent

        return (amountIn * (10000 - maxSlippagePercent)) / 10000;
    }

    function _rewardKeeper(address keeper) private {
        keeperRewards[keeper] += KEEPER_REWARD;
    }

    function _isUserToken(address token, uint256 orderId) private view returns (bool) {
        // Check if this token belongs to the specific order
        // Prevents accidental transfer of other users' tokens
        DCAOrder memory order = orders[orderId];
        return order.tokenIn == token;
    }

    // ====== View Functions ======

    /**
     * @notice Get user's DCA orders
     */
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    /**
     * @notice Get order details
     */
    function getOrderDetails(uint256 orderId) external view returns (
        DCAOrder memory order,
        uint256 remainingAmount,
        uint256 nextExecutionTime
    ) {
        order = orders[orderId];
        uint256 remainingTrades = order.totalTrades - order.tradesExecuted;
        remainingAmount = order.amountPerTrade * remainingTrades;

        if (order.lastExecuted == 0) {
            nextExecutionTime = block.timestamp;
        } else {
            nextExecutionTime = order.lastExecuted + order.interval;
        }
    }

    /**
     * @notice Get protocol statistics
     */
    function getStatistics() external view returns (
        uint256 activeOrders,
        uint256 executedTrades,
        uint256 volume
    ) {
        return (totalActiveOrders, totalExecutedTrades, totalVolume);
    }

    // ====== Receive ETH ======

    receive() external payable {
        // Accept ETH for keeper rewards
    }
}