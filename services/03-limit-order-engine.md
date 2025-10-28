# 限价订单引擎(Limit Order Engine)架构设计

## 服务概述

限价订单引擎是DEX系统中实现订单簿功能的核心组件，支持用户以指定价格挂单交易。该引擎实现了无Gas费挂单、自动撮合、部分成交等高级功能，为用户提供类似中心化交易所的交易体验。

## 核心功能

1. **订单管理** - 创建、修改、取消订单
2. **订单撮合** - 高性能撮合引擎
3. **无Gas挂单** - EIP-712签名订单
4. **部分成交** - 支持订单部分执行
5. **订单簿维护** - 实时订单簿更新
6. **价格发现** - 基于订单簿的价格形成
7. **止损止盈** - 条件单支持
8. **订单聚合** - 跨协议订单聚合

## 系统架构

### 整体架构图

```mermaid
graph TB
    subgraph "订单引擎核心"
        API[订单API]
        MANAGER[订单管理器]
        MATCHER[撮合引擎]
        BOOK[订单簿]
        SETTLER[结算器]
    end

    subgraph "订单类型"
        LIMIT[限价单]
        MARKET[市价单]
        STOP[止损单]
        OCO[OCO订单]
        ICEBERG[冰山订单]
    end

    subgraph "撮合系统"
        ENGINE[撮合核心]
        QUEUE[撮合队列]
        EXECUTOR[执行器]
        VALIDATOR[验证器]
    end

    subgraph "数据层"
        ORDERDB[(订单数据库)]
        BOOKDB[(订单簿缓存)]
        HISTORY[(成交历史)]
        INDEX[(索引服务)]
    end

    subgraph "链上交互"
        CONTRACT[限价单合约]
        RELAYER[中继器]
        WATCHER[事件监听器]
    end

    API --> MANAGER
    MANAGER --> LIMIT
    MANAGER --> MARKET
    MANAGER --> STOP
    MANAGER --> OCO
    MANAGER --> ICEBERG

    MANAGER --> BOOK
    BOOK --> MATCHER
    MATCHER --> ENGINE
    ENGINE --> QUEUE
    QUEUE --> EXECUTOR
    EXECUTOR --> VALIDATOR

    EXECUTOR --> SETTLER
    SETTLER --> CONTRACT
    CONTRACT --> RELAYER

    MANAGER --> ORDERDB
    BOOK --> BOOKDB
    SETTLER --> HISTORY
    WATCHER --> INDEX
```

### 核心组件设计

```mermaid
classDiagram
    class LimitOrderEngine {
        -OrderManager orderManager
        -MatchingEngine matcher
        -OrderBook orderBook
        -SettlementEngine settler
        -PriceOracle oracle
        +createOrder(order) OrderId
        +cancelOrder(orderId) bool
        +modifyOrder(orderId, changes) bool
        +getOrderStatus(orderId) Status
        +matchOrders() Matches
    }

    class OrderManager {
        -OrderValidator validator
        -OrderStore store
        -SignatureVerifier verifier
        +validateOrder(order) bool
        +storeOrder(order) OrderId
        +updateOrderStatus(orderId, status) void
        +getActiveOrders(user) Orders
    }

    class MatchingEngine {
        -PriceTimePriority algorithm
        -MatchQueue queue
        -MatchValidator validator
        +addToQueue(order) void
        +processQueue() Matches
        +findMatches(order) Orders
        +calculateMatchPrice(buy, sell) Price
    }

    class OrderBook {
        -BidTree bids
        -AskTree asks
        -DepthCalculator depth
        +addOrder(order) void
        +removeOrder(orderId) void
        +getBestBid() Order
        +getBestAsk() Order
        +getDepth(levels) Depth
    }

    class SettlementEngine {
        -SmartContract contract
        -TransactionBuilder txBuilder
        -GasOptimizer optimizer
        +settleMatch(match) Transaction
        +batchSettle(matches) Transaction
        +verifySettlement(txHash) bool
    }

    LimitOrderEngine --> OrderManager
    LimitOrderEngine --> MatchingEngine
    LimitOrderEngine --> OrderBook
    LimitOrderEngine --> SettlementEngine
```

## 订单生命周期

### 订单状态机

```mermaid
stateDiagram-v2
    [*] --> 创建中: 提交订单

    创建中 --> 验证中: 开始验证
    验证中 --> 待撮合: 验证通过
    验证中 --> 已拒绝: 验证失败

    待撮合 --> 撮合中: 找到匹配
    待撮合 --> 已取消: 用户取消
    待撮合 --> 已过期: 超过有效期

    撮合中 --> 部分成交: 部分匹配
    撮合中 --> 完全成交: 完全匹配
    撮合中 --> 撮合失败: 执行失败

    部分成交 --> 待撮合: 继续挂单
    部分成交 --> 已取消: 用户取消
    部分成交 --> 完全成交: 剩余成交

    撮合失败 --> 待撮合: 重新挂单
    撮合失败 --> 已取消: 放弃重试

    完全成交 --> 结算中: 链上结算
    结算中 --> 已完成: 结算成功
    结算中 --> 结算失败: 结算失败

    结算失败 --> 待撮合: 回滚订单

    已拒绝 --> [*]
    已取消 --> [*]
    已过期 --> [*]
    已完成 --> [*]
```

### 订单处理流程

```mermaid
sequenceDiagram
    participant User
    participant API
    participant Validator
    participant OrderBook
    participant Matcher
    participant Settlement
    participant Blockchain

    User->>API: 创建限价订单
    API->>Validator: 验证订单

    Validator->>Validator: 检查签名
    Validator->>Validator: 验证余额
    Validator->>Validator: 检查价格

    alt 验证通过
        Validator-->>API: 订单有效
        API->>OrderBook: 添加到订单簿

        OrderBook->>Matcher: 触发撮合
        Matcher->>Matcher: 查找匹配订单

        alt 找到匹配
            Matcher->>Settlement: 执行结算
            Settlement->>Blockchain: 提交交易
            Blockchain-->>Settlement: 交易确认
            Settlement-->>OrderBook: 更新订单状态
        else 无匹配
            Matcher-->>OrderBook: 保持挂单
        end

        OrderBook-->>API: 订单状态
        API-->>User: 订单创建成功
    else 验证失败
        Validator-->>API: 拒绝原因
        API-->>User: 订单创建失败
    end
```

## 撮合引擎设计

### 价格-时间优先算法

```mermaid
graph TB
    subgraph "买单簿(Bids)"
        B1[价格: 100<br/>时间: T1<br/>数量: 10]
        B2[价格: 100<br/>时间: T2<br/>数量: 5]
        B3[价格: 99<br/>时间: T3<br/>数量: 20]
        B4[价格: 98<br/>时间: T4<br/>数量: 15]
    end

    subgraph "卖单簿(Asks)"
        A1[价格: 101<br/>时间: T5<br/>数量: 8]
        A2[价格: 101<br/>时间: T6<br/>数量: 12]
        A3[价格: 102<br/>时间: T7<br/>数量: 25]
        A4[价格: 103<br/>时间: T8<br/>数量: 30]
    end

    subgraph "撮合顺序"
        MATCH[撮合引擎]
        PRIORITY[优先级:<br/>1. 价格优先<br/>2. 时间优先]
    end

    B1 -.->|最高买价| MATCH
    A1 -.->|最低卖价| MATCH
    MATCH --> PRIORITY
```

### 撮合流程

```mermaid
flowchart TD
    A[新订单到达] --> B{订单类型}

    B -->|限价单| C[加入订单簿]
    B -->|市价单| D[立即撮合]

    C --> E[获取对手方最优价格]
    D --> E

    E --> F{价格匹配?}
    F -->|是| G[计算成交量]
    F -->|否| H[挂单等待]

    G --> I{完全成交?}
    I -->|是| J[移除订单]
    I -->|否| K[更新剩余量]

    K --> L[继续撮合]
    L --> E

    J --> M[生成成交记录]
    H --> N[更新订单簿]

    M --> O[触发结算]
    N --> P[推送深度更新]
```

## 高级功能

### 1. 无Gas订单(Gasless Orders)

```mermaid
graph TB
    subgraph "EIP-712签名流程"
        USER[用户]
        SIGN[签名订单数据]
        STORE[链下存储]
        RELAYER[中继器]
        CONTRACT[智能合约]
    end

    USER --> |1. 构造订单| SIGN
    SIGN --> |2. EIP-712签名| STORE
    STORE --> |3. 保存订单| RELAYER
    RELAYER --> |4. 提交执行| CONTRACT
    CONTRACT --> |5. 验证并执行| SETTLE[结算]

    subgraph "数据结构"
        ORDER[订单数据<br/>maker: address<br/>taker: address<br/>makerAsset: token<br/>takerAsset: token<br/>makerAmount: uint<br/>takerAmount: uint<br/>expiry: uint<br/>nonce: uint]
    end
```

### 2. 条件单(Stop Orders)

```mermaid
stateDiagram-v2
    [*] --> 待触发: 创建条件单

    待触发 --> 监控中: 开始监控
    监控中 --> 条件满足: 价格达到触发价

    条件满足 --> 转换订单: 转为限价单/市价单
    转换订单 --> 执行中: 提交执行

    执行中 --> 成交: 执行成功
    执行中 --> 失败: 执行失败

    监控中 --> 已取消: 用户取消
    监控中 --> 已过期: 超过有效期

    成交 --> [*]
    失败 --> [*]
    已取消 --> [*]
    已过期 --> [*]
```

### 3. 冰山订单(Iceberg Orders)

```mermaid
graph LR
    subgraph "冰山订单结构"
        TOTAL[总量: 1000]
        VISIBLE[可见量: 100]
        HIDDEN[隐藏量: 900]
    end

    subgraph "执行策略"
        SHOW[显示部分]
        EXECUTE[执行100]
        REFILL[补充100]
        REPEAT[重复直到完成]
    end

    TOTAL --> VISIBLE
    TOTAL --> HIDDEN

    VISIBLE --> SHOW
    SHOW --> EXECUTE
    EXECUTE --> REFILL
    HIDDEN --> REFILL
    REFILL --> REPEAT
    REPEAT --> SHOW
```

## 订单簿数据结构

### 红黑树实现

```mermaid
graph TD
    subgraph "买单树(Bid Tree)"
        B_ROOT[100.5<br/>根节点]
        B_L1[99.8<br/>左子]
        B_R1[101.2<br/>右子]
        B_L2[99.5]
        B_L3[99.9]
        B_R2[101.0]
        B_R3[101.5]

        B_ROOT --> B_L1
        B_ROOT --> B_R1
        B_L1 --> B_L2
        B_L1 --> B_L3
        B_R1 --> B_R2
        B_R1 --> B_R3
    end

    subgraph "卖单树(Ask Tree)"
        A_ROOT[102.0<br/>根节点]
        A_L1[101.5<br/>左子]
        A_R1[103.0<br/>右子]
        A_L2[101.3]
        A_L3[101.8]
        A_R2[102.8]
        A_R3[103.5]

        A_ROOT --> A_L1
        A_ROOT --> A_R1
        A_L1 --> A_L2
        A_L1 --> A_L3
        A_R1 --> A_R2
        A_R1 --> A_R3
    end

    B_ROOT -.->|最高买价| SPREAD[价差]
    A_ROOT -.->|最低卖价| SPREAD
```

## 性能优化

### 1. 批量结算

```mermaid
sequenceDiagram
    participant Matcher
    participant Aggregator
    participant Optimizer
    participant Contract
    participant Blockchain

    loop 收集成交
        Matcher->>Aggregator: 添加成交记录
    end

    Aggregator->>Aggregator: 达到批量阈值

    Aggregator->>Optimizer: 优化批量交易
    Optimizer->>Optimizer: 合并相同交易对
    Optimizer->>Optimizer: 计算最优Gas
    Optimizer-->>Aggregator: 优化后批量

    Aggregator->>Contract: 批量结算调用
    Contract->>Blockchain: 单笔交易执行多个结算
    Blockchain-->>Contract: 确认
    Contract-->>Aggregator: 批量结算成功
```

### 2. 内存池优化

```mermaid
graph TB
    subgraph "内存池结构"
        HOT[热数据<br/>活跃订单<br/>L1 Cache]
        WARM[温数据<br/>待撮合订单<br/>L2 Cache]
        COLD[冷数据<br/>历史订单<br/>Database]
    end

    subgraph "访问模式"
        FREQUENT[高频访问]
        MODERATE[中频访问]
        RARE[低频访问]
    end

    FREQUENT --> HOT
    MODERATE --> WARM
    RARE --> COLD

    HOT -.->|老化| WARM
    WARM -.->|归档| COLD
    COLD -.->|激活| WARM
    WARM -.->|预热| HOT
```

## 安全机制

### 订单验证流程

```mermaid
flowchart TD
    A[订单提交] --> B[签名验证]
    B --> C{签名有效?}
    C -->|否| REJECT[拒绝订单]
    C -->|是| D[余额检查]

    D --> E{余额充足?}
    E -->|否| REJECT
    E -->|是| F[授权检查]

    F --> G{授权有效?}
    G -->|否| REJECT
    G -->|是| H[价格验证]

    H --> I{价格合理?}
    I -->|否| REJECT
    I -->|是| J[防重放检查]

    J --> K{Nonce有效?}
    K -->|否| REJECT
    K -->|是| ACCEPT[接受订单]

    REJECT --> END[结束]
    ACCEPT --> END
```

## 监控指标

```yaml
性能指标:
  - 撮合延迟: < 10ms
  - 订单处理量: > 10000 orders/s
  - 订单簿深度: > 1000 levels
  - 内存使用: < 8GB

业务指标:
  - 订单成交率: > 60%
  - 平均成交时间: < 30s
  - 部分成交比例: < 20%
  - 取消率: < 30%

系统指标:
  - API响应时间: < 50ms (P99)
  - 数据库查询: < 5ms
  - WebSocket延迟: < 100ms
  - 系统可用性: 99.99%
```

## API接口定义

### 创建限价订单

```typescript
interface CreateLimitOrderRequest {
  maker: string;              // Maker地址
  makerAsset: string;        // Maker代币
  takerAsset: string;        // Taker代币
  makerAmount: string;       // Maker数量
  takerAmount: string;       // Taker数量
  orderType: OrderType;      // 订单类型
  expiry: number;            // 过期时间
  signature: string;         // EIP-712签名
  permitData?: PermitData;   // Permit数据
}

interface LimitOrderResponse {
  orderId: string;           // 订单ID
  status: OrderStatus;       // 订单状态
  createdAt: number;         // 创建时间
  orderHash: string;         // 订单哈希
}

enum OrderType {
  LIMIT = "limit",
  STOP_LOSS = "stop_loss",
  TAKE_PROFIT = "take_profit",
  ICEBERG = "iceberg",
  OCO = "oco"
}

enum OrderStatus {
  PENDING = "pending",
  OPEN = "open",
  PARTIALLY_FILLED = "partially_filled",
  FILLED = "filled",
  CANCELLED = "cancelled",
  EXPIRED = "expired"
}
```

### WebSocket订阅

```typescript
// 订阅订单簿
interface OrderBookSubscription {
  action: "subscribe";
  channel: "orderbook";
  pair: string;              // 交易对
  depth: number;             // 深度层级
}

// 订单簿更新
interface OrderBookUpdate {
  type: "snapshot" | "update";
  pair: string;
  bids: PriceLevel[];
  asks: PriceLevel[];
  timestamp: number;
}

interface PriceLevel {
  price: string;
  amount: string;
  count: number;             // 该价位订单数
}
```

## 实现要点

1. **高性能撮合**
   - 内存撮合引擎
   - 多线程并发处理
   - 零拷贝优化

2. **数据一致性**
   - 事务性操作
   - 乐观锁机制
   - 最终一致性保证

3. **可扩展性**
   - 水平分片
   - 读写分离
   - 订单簿分区

4. **用户体验**
   - 实时推送
   - 订单历史查询
   - 丰富的订单类型