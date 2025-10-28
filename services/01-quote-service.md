# 报价服务(Quote Service)架构设计

## 服务概述

报价服务是DEX系统的核心组件，负责为用户提供实时、准确的交易报价。它通过聚合多个流动性来源、计算最优路径，并考虑Gas费用、滑点等因素，为用户提供最佳交易方案。

## 核心功能

1. **实时价格聚合** - 从多个DEX和流动性池获取价格
2. **路径优化** - 计算最优交易路径
3. **滑点计算** - 预估交易滑点
4. **Gas费估算** - 计算交易成本
5. **价格缓存** - 高性能价格缓存机制
6. **报价验证** - 确保报价准确性和有效性

## 系统架构

### 整体架构图

```mermaid
graph TB
    subgraph "报价服务核心"
        API[报价API接口]
        CORE[报价核心引擎]
        CACHE[报价缓存层]
        VALIDATOR[报价验证器]
    end

    subgraph "价格源"
        DEX1[Uniswap V2/V3]
        DEX2[SushiSwap]
        DEX3[Curve]
        DEX4[Balancer]
        ORACLE[价格预言机]
    end

    subgraph "计算模块"
        ROUTER[路径计算器]
        SLIPPAGE[滑点计算器]
        GAS[Gas估算器]
        OPTIMIZER[优化器]
    end

    subgraph "数据存储"
        REDIS[(Redis缓存)]
        POSTGRES[(PostgreSQL)]
        TIMESCALE[(时序数据库)]
    end

    API --> CORE
    CORE --> CACHE
    CACHE --> VALIDATOR

    CORE --> ROUTER
    ROUTER --> SLIPPAGE
    ROUTER --> GAS
    ROUTER --> OPTIMIZER

    CORE --> DEX1
    CORE --> DEX2
    CORE --> DEX3
    CORE --> DEX4
    CORE --> ORACLE

    CACHE --> REDIS
    VALIDATOR --> POSTGRES
    OPTIMIZER --> TIMESCALE
```

### 详细组件设计

```mermaid
classDiagram
    class QuoteService {
        -PriceAggregator aggregator
        -PathFinder pathFinder
        -SlippageCalculator slippageCalc
        -GasEstimator gasEstimator
        -QuoteCache cache
        +getQuote(request) Quote
        +getBestPath(tokenIn, tokenOut, amount) Path
        +validateQuote(quote) bool
        +refreshPrices() void
    }

    class PriceAggregator {
        -List~PriceSource~ sources
        -PriceOracle oracle
        +fetchPrices(token) Prices
        +aggregatePrices(prices) Price
        +validatePrice(price) bool
        +subscribeToPriceFeeds() void
    }

    class PathFinder {
        -Graph liquidityGraph
        -PathOptimizer optimizer
        +findAllPaths(tokenIn, tokenOut) List~Path~
        +findOptimalPath(paths, amount) Path
        +calculatePathCost(path) Cost
        +validatePath(path) bool
    }

    class SlippageCalculator {
        -LiquidityDepth depth
        -PriceImpactModel model
        +calculateSlippage(path, amount) Slippage
        +estimatePriceImpact(trade) Impact
        +getMaxSlippage(pool) Percentage
    }

    class GasEstimator {
        -GasOracle oracle
        -ContractSimulator simulator
        +estimateGas(path) GasAmount
        +getGasPrice(chain) Price
        +simulateTransaction(tx) Gas
        +optimizeGasUsage(path) Path
    }

    QuoteService --> PriceAggregator
    QuoteService --> PathFinder
    QuoteService --> SlippageCalculator
    QuoteService --> GasEstimator
```

## 核心算法

### 1. 路径寻找算法

```mermaid
graph LR
    subgraph "路径寻找流程"
        START[开始]
        BUILD[构建流动性图]
        BFS[广度优先搜索]
        FILTER[过滤路径]
        OPTIMIZE[优化路径]
        END[返回最优路径]
    end

    START --> BUILD
    BUILD --> BFS
    BFS --> FILTER
    FILTER --> OPTIMIZE
    OPTIMIZE --> END
```

### 2. 价格聚合算法

```mermaid
flowchart TD
    A[收集价格数据] --> B{数据完整?}
    B -->|是| C[加权平均计算]
    B -->|否| D[请求缺失数据]
    D --> A
    C --> E[异常值检测]
    E --> F{存在异常?}
    F -->|是| G[剔除异常值]
    F -->|否| H[价格验证]
    G --> C
    H --> I{验证通过?}
    I -->|是| J[返回聚合价格]
    I -->|否| K[使用预言机价格]
    K --> J
```

## 数据流设计

### 报价请求处理流程

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant Core
    participant Cache
    participant PriceAgg
    participant PathFinder
    participant Validator

    Client->>API: 请求报价(tokenIn, tokenOut, amount)
    API->>Core: 处理报价请求

    Core->>Cache: 检查缓存
    alt 缓存命中
        Cache-->>Core: 返回缓存报价
    else 缓存未命中
        Core->>PriceAgg: 获取价格数据
        PriceAgg->>PriceAgg: 聚合多源价格
        PriceAgg-->>Core: 返回价格

        Core->>PathFinder: 寻找最优路径
        PathFinder->>PathFinder: 计算所有可能路径
        PathFinder->>PathFinder: 评估路径成本
        PathFinder-->>Core: 返回最优路径

        Core->>Core: 计算滑点
        Core->>Core: 估算Gas

        Core->>Validator: 验证报价
        Validator-->>Core: 验证结果

        Core->>Cache: 更新缓存
    end

    Core-->>API: 返回报价
    API-->>Client: 报价响应
```

### 实时价格更新机制

```mermaid
sequenceDiagram
    participant PriceSource
    participant WebSocket
    participant PriceAgg
    participant Cache
    participant Subscribers

    loop 价格更新循环
        PriceSource->>WebSocket: 推送价格更新
        WebSocket->>PriceAgg: 接收价格数据
        PriceAgg->>PriceAgg: 验证价格
        PriceAgg->>PriceAgg: 聚合计算
        PriceAgg->>Cache: 更新缓存
        PriceAgg->>Subscribers: 广播价格更新
    end
```

## 性能优化策略

### 1. 多级缓存架构

```mermaid
graph TB
    subgraph "缓存层级"
        L1[L1: 内存缓存<br/>热点数据<br/>TTL: 1s]
        L2[L2: Redis缓存<br/>常用数据<br/>TTL: 10s]
        L3[L3: 数据库<br/>历史数据<br/>永久存储]
    end

    REQUEST[报价请求] --> L1
    L1 -->|未命中| L2
    L2 -->|未命中| L3
    L3 --> COMPUTE[重新计算]
    COMPUTE --> UPDATE[更新所有层级]
```

### 2. 并发处理模型

```mermaid
graph LR
    subgraph "并发处理"
        QUEUE[请求队列]
        WORKER1[Worker 1]
        WORKER2[Worker 2]
        WORKER3[Worker N]
        POOL[结果池]
    end

    REQUEST[批量请求] --> QUEUE
    QUEUE --> WORKER1
    QUEUE --> WORKER2
    QUEUE --> WORKER3

    WORKER1 --> POOL
    WORKER2 --> POOL
    WORKER3 --> POOL

    POOL --> RESPONSE[批量响应]
```

## 高可用设计

### 服务部署架构

```mermaid
graph TB
    subgraph "负载均衡层"
        LB[负载均衡器]
    end

    subgraph "服务实例"
        SVC1[报价服务1<br/>主节点]
        SVC2[报价服务2<br/>备节点]
        SVC3[报价服务3<br/>备节点]
    end

    subgraph "数据同步"
        SYNC[数据同步服务]
    end

    subgraph "监控"
        MONITOR[健康检查]
        METRICS[性能指标]
    end

    LB --> SVC1
    LB --> SVC2
    LB --> SVC3

    SVC1 <--> SYNC
    SVC2 <--> SYNC
    SVC3 <--> SYNC

    SVC1 --> MONITOR
    SVC2 --> MONITOR
    SVC3 --> MONITOR

    MONITOR --> METRICS
```

## 错误处理机制

```mermaid
stateDiagram-v2
    [*] --> 接收请求
    接收请求 --> 参数验证

    参数验证 --> 获取价格: 验证通过
    参数验证 --> 参数错误: 验证失败

    获取价格 --> 计算路径: 成功
    获取价格 --> 价格异常: 失败

    计算路径 --> 生成报价: 找到路径
    计算路径 --> 无流动性: 未找到路径

    生成报价 --> 验证报价
    验证报价 --> 返回报价: 验证通过
    验证报价 --> 报价异常: 验证失败

    参数错误 --> 错误响应
    价格异常 --> 降级处理
    无流动性 --> 错误响应
    报价异常 --> 重试机制

    降级处理 --> 使用备用源
    使用备用源 --> 计算路径
    重试机制 --> 获取价格: 重试
    重试机制 --> 错误响应: 超过重试次数

    返回报价 --> [*]
    错误响应 --> [*]
```

## 监控指标

### 关键性能指标(KPI)

```yaml
性能指标:
  - 报价延迟: < 100ms (P99)
  - 吞吐量: > 10000 QPS
  - 缓存命中率: > 90%
  - 错误率: < 0.1%

业务指标:
  - 报价准确率: > 99.9%
  - 价格偏差: < 0.1%
  - 路径优化率: > 95%
  - Gas估算准确率: > 95%

可用性指标:
  - 服务可用性: 99.99%
  - 价格源可用性: > 99%
  - 故障恢复时间: < 30s
```

### 监控仪表板

```mermaid
graph TB
    subgraph "监控仪表板"
        subgraph "实时指标"
            QPS[QPS: 8543]
            LATENCY[延迟: 45ms]
            ERROR[错误率: 0.05%]
        end

        subgraph "价格源状态"
            DEX_STATUS[DEX状态<br/>Uniswap: ✓<br/>Sushi: ✓<br/>Curve: ✓]
            ORACLE_STATUS[预言机状态<br/>Chainlink: ✓<br/>Band: ✓]
        end

        subgraph "缓存状态"
            CACHE_HIT[命中率: 92%]
            CACHE_SIZE[缓存大小: 2.3GB]
            CACHE_EVICT[驱逐率: 5%]
        end

        subgraph "告警"
            ALERT1[⚠️ 价格偏差 > 1%]
            ALERT2[⚠️ 延迟 > 200ms]
        end
    end
```

## API接口定义

### 获取报价

```typescript
// 请求
interface QuoteRequest {
  chainId: number;          // 链ID
  tokenIn: string;          // 输入代币地址
  tokenOut: string;         // 输出代币地址
  amountIn?: string;        // 输入数量
  amountOut?: string;       // 输出数量(与amountIn二选一)
  slippageTolerance: number; // 滑点容差(基点)
  recipient?: string;       // 接收地址
  deadline?: number;        // 交易截止时间
}

// 响应
interface QuoteResponse {
  quoteId: string;          // 报价ID
  tokenIn: TokenInfo;       // 输入代币信息
  tokenOut: TokenInfo;      // 输出代币信息
  amountIn: string;         // 输入数量
  amountOut: string;        // 输出数量
  amountOutMin: string;     // 最小输出数量
  path: TradePath[];        // 交易路径
  priceImpact: number;      // 价格影响
  executionPrice: string;   // 执行价格
  fee: FeeInfo;             // 费用信息
  gasEstimate: string;      // Gas估算
  validUntil: number;       // 报价有效期
}

interface TradePath {
  pool: string;             // 流动性池地址
  tokenIn: string;          // 输入代币
  tokenOut: string;         // 输出代币
  fee: number;              // 手续费率
  protocol: string;         // 协议名称
}
```

## 技术实现要点

1. **高性能要求**
   - 使用Rust/Go实现核心计算逻辑
   - 采用零拷贝技术减少内存开销
   - 实现无锁并发数据结构

2. **准确性保证**
   - 多源价格交叉验证
   - 实时监控价格偏差
   - 自动降级和熔断机制

3. **可扩展性**
   - 插件化的DEX适配器
   - 动态路由算法配置
   - 水平扩展支持

4. **安全考虑**
   - 防止价格操纵攻击
   - 限制单次查询复杂度
   - 实施访问频率控制