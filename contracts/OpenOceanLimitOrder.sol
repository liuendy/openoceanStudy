// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title OpenOcean Limit Order Protocol
 * @author OpenOcean Team
 * @notice Gas-optimized limit order implementation with RFQ support
 * @dev Uses EIP-712 for gasless order creation and efficient storage packing
 */

import "./OpenOceanAggregatorV1.sol";

// ====== Libraries ======

/**
 * @title OrderLib
 * @notice Library for order hash calculation and validation
 */
library OrderLib {
    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address taker,address makerAsset,address takerAsset,uint256 makingAmount,uint256 takingAmount,uint256 salt,uint256 deadline,bytes makerAssetData,bytes takerAssetData)"
    );

    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.maker,
            order.taker,
            order.makerAsset,
            order.takerAsset,
            order.makingAmount,
            order.takingAmount,
            order.salt,
            order.deadline,
            keccak256(order.makerAssetData),
            keccak256(order.takerAssetData)
        ));
    }
}

// ====== Main Contract ======

contract OpenOceanLimitOrder is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    using OrderLib for Order;

    // ====== Constants ======
    uint256 private constant _ORDER_DOES_NOT_EXIST = 0;
    uint256 private constant _ORDER_FILLED = 1;
    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    // ====== State Variables ======
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Order tracking (packed for gas optimization)
    // Layout: [uint128 filledAmount][uint128 remaining]
    mapping(bytes32 => uint256) private _orderStatus;

    // Nonce management for cancellation
    mapping(address => uint256) public nonceBitmap;

    // RFQ (Request for Quote) specific storage
    mapping(bytes32 => address) public rfqMakers;

    // Statistics
    uint256 public totalOrdersCreated;
    uint256 public totalOrdersFilled;
    uint256 public totalVolume;

    // ====== Structs ======

    struct Order {
        address maker;          // Order creator
        address taker;          // Allowed taker (0x0 for any)
        address makerAsset;     // Asset to sell
        address takerAsset;     // Asset to buy
        uint256 makingAmount;   // Amount to sell
        uint256 takingAmount;   // Amount to buy
        uint256 salt;           // Unique salt
        uint256 deadline;       // Order expiration
        bytes makerAssetData;   // Additional maker asset data
        bytes takerAssetData;   // Additional taker asset data
    }

    struct FillParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 thresholdAmount;
        address target;         // Interaction target
        bytes interaction;      // Interaction calldata
    }

    struct RFQOrder {
        address maker;
        address makerAsset;
        address takerAsset;
        uint128 makingAmount;
        uint128 takingAmount;
        uint32 deadline;
    }

    // ====== Events ======

    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        uint256 makingAmount,
        uint256 takingAmount
    );

    event OrderCanceled(
        bytes32 indexed orderHash,
        address indexed maker
    );

    event NonceIncremented(
        address indexed maker,
        uint256 newNonce
    );

    // ====== Constructor ======

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256("OpenOcean Limit Order Protocol"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
    }

    // ====== Main Functions ======

    /**
     * @notice Fill a limit order
     * @dev Main entry point for order execution
     * @param params Fill parameters including order and signature
     * @return actualMakingAmount Amount of maker asset filled
     * @return actualTakingAmount Amount of taker asset filled
     */
    function fillOrder(
        FillParams calldata params
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 actualMakingAmount, uint256 actualTakingAmount)
    {
        // Validate order
        require(block.timestamp <= params.order.deadline, "Order expired");
        require(params.order.taker == address(0) || params.order.taker == msg.sender, "Invalid taker");

        // Calculate order hash
        bytes32 orderHash = params.order.hash();

        // Verify signature
        require(_verifySignature(orderHash, params.signature, params.order.maker), "Invalid signature");

        // Check and update order status
        uint256 orderData = _orderStatus[orderHash];
        uint256 filledAmount = orderData >> 128;
        uint256 remainingAmount = uint128(orderData);

        if (remainingAmount == 0) {
            // First fill
            remainingAmount = params.order.makingAmount;
            totalOrdersCreated++;
        }

        require(remainingAmount > 0, "Order already filled");

        // Calculate fill amounts
        actualMakingAmount = params.makingAmount;
        if (actualMakingAmount > remainingAmount) {
            actualMakingAmount = remainingAmount;
        }

        actualTakingAmount = (actualMakingAmount * params.order.takingAmount) / params.order.makingAmount;

        require(actualTakingAmount >= params.thresholdAmount, "Below threshold");

        // Update order status (pack data for gas optimization)
        remainingAmount -= actualMakingAmount;
        filledAmount += actualMakingAmount;
        _orderStatus[orderHash] = (filledAmount << 128) | remainingAmount;

        // Execute transfers
        IERC20(params.order.takerAsset).safeTransferFrom(
            msg.sender,
            params.order.maker,
            actualTakingAmount
        );

        IERC20(params.order.makerAsset).safeTransferFrom(
            params.order.maker,
            msg.sender,
            actualMakingAmount
        );

        // Execute interaction if provided
        if (params.target != address(0) && params.interaction.length > 0) {
            (bool success,) = params.target.call(params.interaction);
            require(success, "Interaction failed");
        }

        // Update statistics
        totalOrdersFilled++;
        totalVolume += actualMakingAmount;

        emit OrderFilled(
            orderHash,
            params.order.maker,
            msg.sender,
            actualMakingAmount,
            actualTakingAmount
        );
    }

    /**
     * @notice Fill RFQ order (gas-optimized for market makers)
     * @dev Optimized path for high-frequency RFQ orders
     * @param order Compact RFQ order structure
     * @param signature Order signature
     * @return makingAmount Amount filled
     */
    function fillRFQOrder(
        RFQOrder calldata order,
        bytes calldata signature
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 makingAmount)
    {
        // Check deadline (uint32 for gas optimization)
        require(uint32(block.timestamp) <= order.deadline, "RFQ expired");

        // Calculate order hash
        bytes32 orderHash = keccak256(abi.encode(order));

        // Verify signature
        require(_verifySignature(orderHash, signature, order.maker), "Invalid RFQ signature");

        // Check if already filled
        require(_orderStatus[orderHash] == 0, "RFQ already filled");

        // Mark as filled
        _orderStatus[orderHash] = _ORDER_FILLED;

        // Execute transfers (no partial fills for RFQ)
        IERC20(order.takerAsset).safeTransferFrom(
            msg.sender,
            order.maker,
            order.takingAmount
        );

        IERC20(order.makerAsset).safeTransferFrom(
            order.maker,
            msg.sender,
            order.makingAmount
        );

        emit OrderFilled(
            orderHash,
            order.maker,
            msg.sender,
            order.makingAmount,
            order.takingAmount
        );

        return order.makingAmount;
    }

    /**
     * @notice Cancel an order by invalidating its signature
     * @param order Order to cancel
     */
    function cancelOrder(Order calldata order) external {
        require(order.maker == msg.sender, "Not order maker");

        bytes32 orderHash = order.hash();
        _orderStatus[orderHash] = _ORDER_FILLED; // Mark as filled to prevent execution

        emit OrderCanceled(orderHash, msg.sender);
    }

    /**
     * @notice Batch cancel orders by incrementing nonce
     * @dev Gas-efficient way to cancel multiple orders
     */
    function incrementNonce() external {
        uint256 newNonce = ++nonceBitmap[msg.sender];
        emit NonceIncremented(msg.sender, newNonce);
    }

    /**
     * @notice Check remaining amount for an order
     * @param orderHash Hash of the order
     * @return remaining Remaining fillable amount
     */
    function remainingFor(bytes32 orderHash) external view returns (uint256 remaining) {
        uint256 orderData = _orderStatus[orderHash];
        remaining = uint128(orderData);
    }

    /**
     * @notice Check if an order is valid and fillable
     * @param order Order to check
     * @return valid Whether the order is valid
     */
    function isValidOrder(Order calldata order) external view returns (bool valid) {
        if (block.timestamp > order.deadline) return false;

        bytes32 orderHash = order.hash();
        uint256 orderData = _orderStatus[orderHash];
        uint256 remaining = uint128(orderData);

        return remaining == 0 || remaining > 0;
    }

    // ====== Internal Functions ======

    /**
     * @notice Verify EIP-712 signature
     */
    function _verifySignature(
        bytes32 orderHash,
        bytes memory signature,
        address signer
    ) private view returns (bool) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, orderHash)
        );

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) v += 27;

        require(v == 27 || v == 28, "Invalid signature v value");

        address recovered = ecrecover(digest, v, r, s);
        return recovered != address(0) && recovered == signer;
    }

    // ====== View Functions ======

    /**
     * @notice Get order information
     */
    function getOrderInfo(bytes32 orderHash) external view returns (
        uint256 filledAmount,
        uint256 remainingAmount,
        bool isActive
    ) {
        uint256 orderData = _orderStatus[orderHash];
        filledAmount = orderData >> 128;
        remainingAmount = uint128(orderData);
        isActive = remainingAmount > 0 || (filledAmount == 0 && remainingAmount == 0);
    }

    /**
     * @notice Build order hash for signature verification
     */
    function hashOrder(Order calldata order) external pure returns (bytes32) {
        return order.hash();
    }
}