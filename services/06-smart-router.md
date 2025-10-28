# 智能路由器(Smart Router)架构设计

## 服务概述

智能路由器是DEX系统的核心决策引擎，负责为每笔交易找到最优执行路径。它通过机器学习、图算法和实时数据分析，在复杂的流动性网络中计算出成本最低、滑点最小的交易路径。

## 核心功能

1. **路径发现** - 多跳路径搜索和优化
2. **流动性聚合** - 聚合多个DEX和流动性源
3. **智能分单** - 大单拆分优化执行
4. **ML预测** - 机器学习价格和滑点预测
5. **动态优化** - 实时调整路由策略
6. **Gas优化** - 最小化交易成本
7. **MEV保护** - 抗三明治攻击路由
8. **回测分析** - 路由效果分析和优化

## 系统架构

### 整体架构图

```mermaid
graph TB
    subgraph "路由器核心"
        API[路由API]
        ENGINE[路由引擎]
        OPTIMIZER[优化器]
        SIMULATOR[模拟器]
        ANALYZER[分析器]
    end

    subgraph "算法层"
        PATHFIND[路径搜索]
        MLMODEL[ML模型]
        GRAPH[图算法]
        HEURISTIC[启发式算法]
    end

    subgraph "数据源"
        DEX_AGGREGATOR[DEX聚合器]
        LIQUIDITY_MONITOR[流动性监控]
        PRICE_FEED[价格源]
        GAS_ORACLE[Gas预言机]
    end

    subgraph "执行层"
        SPLITTER[分单器]
        SEQUENCER[排序器]
        EXECUTOR[执行器]
        VALIDATOR[验证器]
    end

    subgraph "缓存层"
        ROUTE_CACHE[(路由缓存)]
        POOL_CACHE[(池子缓存)]
        PRICE_CACHE[(价格缓存)]
        GRAPH_CACHE[(图缓存)]
    end

    API --> ENGINE
    ENGINE --> PATHFIND
    ENGINE --> MLMODEL
    ENGINE --> GRAPH
    ENGINE --> HEURISTIC

    PATHFIND --> OPTIMIZER
    MLMODEL --> OPTIMIZER
    GRAPH --> OPTIMIZER

    OPTIMIZER --> SIMULATOR
    SIMULATOR --> ANALYZER

    DEX_AGGREGATOR --> ENGINE
    LIQUIDITY_MONITOR --> ENGINE
    PRICE_FEED --> ENGINE
    GAS_ORACLE --> ENGINE

    OPTIMIZER --> SPLITTER
    SPLITTER --> SEQUENCER
    SEQUENCER --> EXECUTOR
    EXECUTOR --> VALIDATOR

    ENGINE --> ROUTE_CACHE
    DEX_AGGREGATOR --> POOL_CACHE
    PRICE_FEED --> PRICE_CACHE
    GRAPH --> GRAPH_CACHE
```

### 核心组件设计

```mermaid
classDiagram
    class SmartRouter {
        -PathFinder pathFinder
        -MLPredictor predictor
        -Optimizer optimizer
        -Simulator simulator
        -CacheManager cache
        +findBestRoute(tokenIn, tokenOut, amount) Route
        +splitOrder(amount, routes) SplitStrategy
        +predictSlippage(route, amount) Slippage
        +optimizeGas(routes) OptimizedRoute
        +simulateTrade(route) SimResult
    }

    class PathFinder {
        -GraphBuilder graphBuilder
        -DijkstraAlgorithm dijkstra
        -AStarAlgorithm aStar
        -KShortestPaths kPaths
        +buildLiquidityGraph() Graph
        +findShortestPath(start, end) Path
        +findKPaths(start, end, k) Paths
        +findMultiHopPath(constraints) Path
    }

    class MLPredictor {
        -PricePredictor priceModel
        -SlippagePredictor slippageModel
        -VolumePredictor volumeModel
        -ModelTrainer trainer
        +predictPrice(token, time) Price
        +predictSlippage(pool, amount) Slippage
        +predictVolume(pair) Volume
        +updateModels(data) void
    }

    class Optimizer {
        -LinearProgramming lpSolver
        -GeneticAlgorithm gaSolver
        -SimulatedAnnealing saSolver
        -ConstraintSolver constraints
        +optimizeRoute(paths, objective) Route
        +minimizeCost(routes) Route
        +maximizeOutput(routes) Route
        +balanceTradeoffs(params) Route
    }

    class Simulator {
        -StateManager state
        -TransactionSimulator txSim
        -ImpactCalculator impact
        -RiskAssessor risk
        +simulateSwap(route, amount) Result
        +calculateImpact(trade) Impact
        +assessRisk(route) RiskScore
        +compareRoutes(routes) Comparison
    }

    SmartRouter --> PathFinder
    SmartRouter --> MLPredictor
    SmartRouter --> Optimizer
    SmartRouter --> Simulator
```

## 路径搜索算法

### 多跳路径发现

```mermaid
graph TD
    subgraph "流动性图构建"
        POOLS[流动性池]
        TOKENS[代币节点]
        EDGES[流动性边]
        WEIGHTS[权重计算]
    end

    subgraph "搜索算法"
        BFS[广度优先]
        DFS[深度优先]
        DIJKSTRA[Dijkstra]
        ASTAR[A*算法]
    end

    subgraph "路径优化"
        PRUNE[剪枝]
        MERGE[合并]
        FILTER[过滤]
        RANK[排序]
    end

    POOLS --> TOKENS
    TOKENS --> EDGES
    EDGES --> WEIGHTS

    WEIGHTS --> BFS
    WEIGHTS --> DFS
    WEIGHTS --> DIJKSTRA
    WEIGHTS --> ASTAR

    BFS --> PRUNE
    DFS --> PRUNE
    DIJKSTRA --> MERGE
    ASTAR --> FILTER

    PRUNE --> RANK
    MERGE --> RANK
    FILTER --> RANK
```

### K最短路径算法

```mermaid
flowchart TD
    A[输入: 源Token, 目标Token] --> B[构建流动性图]
    B --> C[Dijkstra找最短路径]

    C --> D[初始化路径集合]
    D --> E[计算偏离路径]

    E --> F{路径数 < K?}
    F -->|是| G[生成候选路径]
    F -->|否| H[返回K条路径]

    G --> I[计算路径成本]
    I --> J[加入优先队列]

    J --> K[选择最优候选]
    K --> L[添加到结果集]
    L --> E

    H --> M[路径评分]
    M --> N[返回最优K条路径]
```

## 智能分单策略

### 大单拆分算法

```mermaid
graph TB
    subgraph "分单决策"
        ORDER[大额订单]
        ANALYSIS[影响分析]
        DECISION[是否拆分]
    end

    subgraph "拆分策略"
        EQUAL[均等拆分]
        OPTIMAL[最优拆分]
        DYNAMIC[动态拆分]
        ADAPTIVE[自适应拆分]
    end

    subgraph "执行方案"
        PARALLEL[并行执行]
        SEQUENTIAL[顺序执行]
        MIXED[混合执行]
    end

    ORDER --> ANALYSIS
    ANALYSIS --> |滑点 > 阈值| DECISION
    DECISION --> |需要拆分| OPTIMAL

    EQUAL --> PARALLEL
    OPTIMAL --> MIXED
    DYNAMIC --> SEQUENTIAL
    ADAPTIVE --> MIXED

    subgraph "优化目标"
        MIN_SLIPPAGE[最小滑点]
        MIN_GAS[最小Gas]
        MAX_SPEED[最快执行]
    end
```

### 分单执行时序

```mermaid
sequenceDiagram
    participant Router
    participant Splitter
    participant Optimizer
    participant Executor
    participant Pools

    Router->>Splitter: 大额订单(1000 ETH)
    Splitter->>Splitter: 计算价格影响

    alt 需要拆分
        Splitter->>Optimizer: 请求最优拆分方案

        Optimizer->>Optimizer: 分析流动性分布
        Optimizer->>Optimizer: 计算最优分配
        Optimizer-->>Splitter: [300, 250, 200, 150, 100]

        par 并行执行
            Splitter->>Executor: 子订单1 (300 ETH)
            and
            Splitter->>Executor: 子订单2 (250 ETH)
            and
            Splitter->>Executor: 子订单3 (200 ETH)
        end

        Executor->>Pools: 执行交易
        Pools-->>Executor: 执行结果

        Executor-->>Router: 汇总结果
    else 不需要拆分
        Splitter->>Executor: 整单执行
        Executor->>Pools: 单笔交易
        Pools-->>Executor: 执行结果
        Executor-->>Router: 返回结果
    end
```

## 机器学习模型

### ML预测架构

```mermaid
graph TB
    subgraph "特征工程"
        PRICE[历史价格]
        VOLUME[成交量]
        LIQUIDITY[流动性]
        VOLATILITY[波动率]
        TIME[时间特征]
    end

    subgraph "模型架构"
        LSTM[LSTM网络<br/>价格预测]
        GBM[梯度提升<br/>滑点预测]
        RF[随机森林<br/>路径评分]
        DNN[深度网络<br/>综合预测]
    end

    subgraph "模型训练"
        TRAIN[训练集]
        VALID[验证集]
        TEST[测试集]
        ONLINE[在线学习]
    end

    subgraph "预测输出"
        PRICE_PRED[价格预测]
        SLIPPAGE_PRED[滑点预测]
        GAS_PRED[Gas预测]
        SUCCESS_PRED[成功率预测]
    end

    PRICE --> LSTM
    VOLUME --> GBM
    LIQUIDITY --> RF
    VOLATILITY --> DNN
    TIME --> DNN

    TRAIN --> LSTM
    VALID --> GBM
    TEST --> RF
    ONLINE --> DNN

    LSTM --> PRICE_PRED
    GBM --> SLIPPAGE_PRED
    RF --> GAS_PRED
    DNN --> SUCCESS_PRED
```

### 实时学习流程

```mermaid
flowchart LR
    A[实时数据流] --> B[特征提取]
    B --> C[模型推理]
    C --> D[路由决策]
    D --> E[执行交易]

    E --> F[结果收集]
    F --> G[性能评估]
    G --> H{需要更新?}

    H -->|是| I[增量训练]
    H -->|否| J[继续监控]

    I --> K[模型更新]
    K --> L[A/B测试]
    L --> M[部署新模型]
    M --> C

    J --> F
```

## 流动性聚合

### 多源聚合架构

```mermaid
graph TB
    subgraph "流动性源"
        subgraph "AMM DEX"
            UNI[Uniswap]
            SUSHI[SushiSwap]
            CURVE[Curve]
            BALANCER[Balancer]
        end

        subgraph "订单簿"
            DYDX[dYdX]
            SERUM[Serum]
        end

        subgraph "聚合器"
            ONEINCH[1inch]
            MATCHA[Matcha]
        end

        subgraph "私有池"
            RFQ[RFQ系统]
            PMM[PMM做市商]
        end
    end

    subgraph "聚合引擎"
        COLLECTOR[数据收集]
        NORMALIZER[标准化]
        AGGREGATOR[聚合计算]
        RANKER[路径排序]
    end

    UNI --> COLLECTOR
    SUSHI --> COLLECTOR
    CURVE --> COLLECTOR
    BALANCER --> COLLECTOR
    DYDX --> COLLECTOR
    SERUM --> COLLECTOR
    ONEINCH --> COLLECTOR
    MATCHA --> COLLECTOR
    RFQ --> COLLECTOR
    PMM --> COLLECTOR

    COLLECTOR --> NORMALIZER
    NORMALIZER --> AGGREGATOR
    AGGREGATOR --> RANKER
```

### 流动性深度分析

```mermaid
graph LR
    subgraph "深度数据"
        BID[买单深度]
        ASK[卖单深度]
        SPREAD[价差]
    end

    subgraph "分析指标"
        DEPTH[深度评分]
        IMPACT[影响评估]
        STABILITY[稳定性]
    end

    subgraph "可视化"
        HEATMAP[热力图]
        ORDERBOOK[订单簿]
        CHART[深度图表]
    end

    BID --> DEPTH
    ASK --> DEPTH
    SPREAD --> IMPACT

    DEPTH --> STABILITY
    IMPACT --> STABILITY

    STABILITY --> HEATMAP
    STABILITY --> ORDERBOOK
    STABILITY --> CHART
```

## Gas优化策略

### 多链Gas优化

```mermaid
graph TB
    subgraph "Gas分析"
        BASE_FEE[基础费用]
        PRIORITY_FEE[优先费]
        COMPLEXITY[复杂度]
        CONGESTION[拥堵度]
    end

    subgraph "优化策略"
        ROUTE_OPT[路径优化<br/>减少跳数]
        BATCH_OPT[批量优化<br/>合并交易]
        TIME_OPT[时机优化<br/>避开高峰]
        CONTRACT_OPT[合约优化<br/>简化调用]
    end

    subgraph "链特定优化"
        ETH_OPT[以太坊<br/>EIP-1559]
        BSC_OPT[BSC<br/>固定Gas]
        POLY_OPT[Polygon<br/>低费用]
        ARB_OPT[Arbitrum<br/>批量提交]
    end

    BASE_FEE --> ROUTE_OPT
    PRIORITY_FEE --> TIME_OPT
    COMPLEXITY --> CONTRACT_OPT
    CONGESTION --> BATCH_OPT

    ROUTE_OPT --> ETH_OPT
    BATCH_OPT --> ARB_OPT
    TIME_OPT --> BSC_OPT
    CONTRACT_OPT --> POLY_OPT
```

## MEV保护路由

### 抗MEV策略

```mermaid
flowchart TD
    A[检测MEV风险] --> B{风险等级}

    B -->|高风险| C[私有内存池路由]
    B -->|中风险| D[拆分路由]
    B -->|低风险| E[正常路由]

    C --> F[Flashbots]
    C --> G[私有节点]

    D --> H[多路径执行]
    D --> I[时间延迟]

    E --> J[公开执行]

    F --> K[提交Bundle]
    G --> L[直接发送]
    H --> M[分散执行]
    I --> N[随机延迟]
    J --> O[标准广播]

    K --> P[MEV保护执行]
    L --> P
    M --> P
    N --> P
    O --> P
```

## 性能优化

### 缓存策略

```mermaid
graph TB
    subgraph "多级缓存"
        L1[L1缓存<br/>热点路由<br/>TTL: 1s]
        L2[L2缓存<br/>常用路径<br/>TTL: 10s]
        L3[L3缓存<br/>流动性图<br/>TTL: 60s]
    end

    subgraph "缓存更新"
        INVALIDATE[失效策略]
        REFRESH[刷新策略]
        PREDICT[预测加载]
    end

    subgraph "缓存命中率"
        HOT[热数据: 95%]
        WARM[温数据: 80%]
        COLD[冷数据: 30%]
    end

    L1 --> HOT
    L2 --> WARM
    L3 --> COLD

    INVALIDATE --> L1
    REFRESH --> L2
    PREDICT --> L3
```

## 监控和分析

### 路由效果分析

```mermaid
graph LR
    subgraph "性能指标"
        LATENCY[延迟分布]
        SUCCESS[成功率]
        SLIPPAGE[实际滑点]
        SAVINGS[节省成本]
    end

    subgraph "对比分析"
        PREDICTED[预测值]
        ACTUAL[实际值]
        DEVIATION[偏差]
    end

    subgraph "优化建议"
        IMPROVE[改进点]
        BOTTLENECK[瓶颈]
        RECOMMEND[建议]
    end

    LATENCY --> DEVIATION
    SUCCESS --> DEVIATION
    SLIPPAGE --> DEVIATION
    SAVINGS --> DEVIATION

    PREDICTED --> DEVIATION
    ACTUAL --> DEVIATION

    DEVIATION --> IMPROVE
    DEVIATION --> BOTTLENECK
    IMPROVE --> RECOMMEND
    BOTTLENECK --> RECOMMEND
```

## API接口定义

### 路由请求接口

```typescript
interface RouteRequest {
  tokenIn: string;           // 输入代币
  tokenOut: string;          // 输出代币
  amountIn?: string;         // 输入数量
  amountOut?: string;        // 输出数量(二选一)

  // 路由参数
  maxHops?: number;          // 最大跳数(默认3)
  maxSplits?: number;        // 最大拆分数(默认3)
  protocols?: Protocol[];    // 指定协议

  // 优化目标
  objective?: Objective;     // 优化目标
  slippageTolerance: number; // 滑点容差
  deadline?: number;         // 截止时间

  // 高级选项
  mevProtection?: boolean;   // MEV保护
  simulateFirst?: boolean;   // 预先模拟
  excludePools?: string[];   // 排除池子
}

interface RouteResponse {
  // 最优路由
  route: Route;              // 路由详情
  alternativeRoutes?: Route[]; // 备选路由

  // 预期结果
  expectedOutput: string;    // 预期输出
  priceImpact: number;      // 价格影响
  minimumOutput: string;    // 最小输出

  // 成本分析
  estimatedGas: string;     // 预估Gas
  totalFee: string;        // 总费用
  savings: string;         // 节省金额

  // 路径详情
  swaps: SwapStep[];       // 交换步骤
  splits?: SplitDetail[];  // 拆分详情

  // 风险评估
  confidenceScore: number; // 置信度
  riskLevel: RiskLevel;   // 风险等级
}

interface SwapStep {
  protocol: string;        // 协议名称
  pool: string;           // 池子地址
  tokenIn: string;        // 输入代币
  tokenOut: string;       // 输出代币
  amountIn: string;       // 输入数量
  expectedOut: string;    // 预期输出
  fee: number;           // 手续费率
  poolLiquidity: string; // 池子流动性
}

enum Objective {
  BEST_PRICE = "best_price",
  LOWEST_GAS = "lowest_gas",
  FASTEST = "fastest",
  BALANCED = "balanced"
}

enum RiskLevel {
  LOW = "low",
  MEDIUM = "medium",
  HIGH = "high"
}
```

### 路由模拟接口

```typescript
interface SimulateRequest {
  route: Route;            // 待模拟路由
  amountIn: string;       // 输入数量
  sender: string;         // 发送者地址
  blockNumber?: number;   // 指定区块

  // 模拟选项
  includeRevert?: boolean; // 包含失败情况
  checkMEV?: boolean;     // 检查MEV风险
  compareAlternatives?: boolean; // 对比其他路由
}

interface SimulateResponse {
  success: boolean;       // 是否成功
  outputAmount: string;   // 输出数量
  gasUsed: string;       // Gas使用

  // 详细信息
  traces: TransactionTrace[]; // 交易追踪
  stateChanges: StateChange[]; // 状态变化
  events: Event[];       // 事件日志

  // 风险分析
  mevRisk?: MEVRisk;    // MEV风险
  slippageRisk?: number; // 滑点风险

  // 对比结果
  alternatives?: SimulateResult[]; // 其他路由结果
}
```

## 实现要点

1. **高性能计算**
   - 并行路径搜索
   - GPU加速ML推理
   - 内存图数据库

2. **实时性保证**
   - 流式数据处理
   - 增量图更新
   - 预测性缓存

3. **准确性提升**
   - 持续模型训练
   - A/B测试验证
   - 回测分析

4. **可扩展性**
   - 插件式协议适配
   - 动态算法选择
   - 水平扩展支持