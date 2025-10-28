# DCA管理器(Dollar-Cost Averaging Manager)架构设计

## 服务概述

DCA（定投）管理器是实现自动化定期投资策略的核心服务。它允许用户设定周期性的买入/卖出计划，自动执行交易，实现成本平均化投资策略，降低市场波动风险。

## 核心功能

1. **策略管理** - 创建、修改、暂停DCA计划
2. **自动执行** - 定时触发交易执行
3. **智能调度** - 优化执行时机
4. **资金管理** - 自动资金划转和管理
5. **风控管理** - 价格保护和执行条件
6. **通知服务** - 执行状态实时通知
7. **报告分析** - DCA执行效果分析
8. **Gas优化** - 批量执行降低成本

## 系统架构

### 整体架构图

```mermaid
graph TB
    subgraph "DCA核心"
        API[DCA API]
        MANAGER[策略管理器]
        SCHEDULER[调度器]
        EXECUTOR[执行器]
        MONITOR[监控器]
    end

    subgraph "策略类型"
        FIXED[固定金额]
        PERCENT[百分比]
        DYNAMIC[动态策略]
        GRID[网格DCA]
    end

    subgraph "执行引擎"
        TRIGGER[触发器]
        VALIDATOR[验证器]
        TRADER[交易执行]
        SETTLER[结算器]
    end

    subgraph "调度系统"
        CRON[定时任务]
        QUEUE[执行队列]
        WORKER[工作线程]
        RETRY[重试机制]
    end

    subgraph "数据存储"
        STRATEGYDB[(策略库)]
        EXECUTIONDB[(执行记录)]
        BALANCEDB[(余额快照)]
        METRICSDB[(指标数据)]
    end

    API --> MANAGER
    MANAGER --> FIXED
    MANAGER --> PERCENT
    MANAGER --> DYNAMIC
    MANAGER --> GRID

    SCHEDULER --> TRIGGER
    TRIGGER --> VALIDATOR
    VALIDATOR --> TRADER
    TRADER --> SETTLER

    SCHEDULER --> CRON
    CRON --> QUEUE
    QUEUE --> WORKER
    WORKER --> RETRY

    MANAGER --> STRATEGYDB
    EXECUTOR --> EXECUTIONDB
    MONITOR --> BALANCEDB
    MONITOR --> METRICSDB
```

### 核心组件设计

```mermaid
classDiagram
    class DCAManager {
        -StrategyStore strategies
        -Scheduler scheduler
        -Executor executor
        -Monitor monitor
        -NotificationService notifier
        +createStrategy(params) StrategyId
        +updateStrategy(id, changes) bool
        +pauseStrategy(id) bool
        +resumeStrategy(id) bool
        +executeStrategy(id) Result
    }

    class StrategyScheduler {
        -CronJob cronJob
        -ExecutionQueue queue
        -PriorityCalculator priority
        +scheduleStrategy(strategy) JobId
        +cancelSchedule(jobId) bool
        +getNextExecution(strategyId) Time
        +rebalanceSchedule() void
    }

    class ExecutionEngine {
        -PriceChecker priceChecker
        -BalanceValidator balanceValidator
        -SwapExecutor swapExecutor
        -GasOptimizer gasOptimizer
        +validateExecution(strategy) bool
        +executeSwap(params) TxHash
        +batchExecute(strategies) Results
        +handleFailure(error) Recovery
    }

    class Monitor {
        -MetricsCollector metrics
        -AlertManager alerts
        -ReportGenerator reporter
        +trackExecution(execution) void
        +calculatePerformance(strategyId) Metrics
        +generateReport(strategyId) Report
        +checkAlerts(strategyId) Alerts
    }

    class NotificationService {
        -EmailSender email
        -WebSocketPusher websocket
        -WebhookCaller webhook
        +notifyExecution(event) void
        +notifyError(error) void
        +notifyCompletion(strategyId) void
    }

    DCAManager --> StrategyScheduler
    DCAManager --> ExecutionEngine
    DCAManager --> Monitor
    DCAManager --> NotificationService
```

## DCA策略生命周期

### 策略状态机

```mermaid
stateDiagram-v2
    [*] --> 草稿: 创建策略

    草稿 --> 待激活: 配置完成
    待激活 --> 活跃: 激活策略
    待激活 --> 已取消: 用户取消

    活跃 --> 执行中: 触发执行
    执行中 --> 活跃: 执行完成
    执行中 --> 暂停: 执行失败

    活跃 --> 暂停: 用户暂停
    暂停 --> 活跃: 恢复执行
    暂停 --> 已取消: 用户取消

    活跃 --> 已完成: 达到目标
    活跃 --> 已过期: 超过结束时间

    已完成 --> [*]
    已过期 --> [*]
    已取消 --> [*]
```

### 执行流程

```mermaid
sequenceDiagram
    participant Scheduler
    participant Validator
    participant PriceOracle
    participant BalanceChecker
    participant Executor
    participant Blockchain
    participant Monitor
    participant User

    Scheduler->>Scheduler: 定时触发
    Scheduler->>Validator: 验证执行条件

    Validator->>PriceOracle: 获取当前价格
    PriceOracle-->>Validator: 价格数据

    Validator->>BalanceChecker: 检查余额
    BalanceChecker-->>Validator: 余额信息

    alt 条件满足
        Validator-->>Scheduler: 可以执行

        Scheduler->>Executor: 执行交易
        Executor->>Blockchain: 提交交易
        Blockchain-->>Executor: 交易确认

        Executor->>Monitor: 记录执行
        Monitor->>User: 发送通知

    else 条件不满足
        Validator-->>Scheduler: 跳过本次
        Scheduler->>Scheduler: 等待下次
    end
```

## 策略类型设计

### 1. 固定金额DCA

```mermaid
graph LR
    subgraph "固定金额策略"
        AMOUNT[投资金额: $100]
        FREQ[频率: 每天]
        DURATION[持续: 30天]
    end

    subgraph "执行计划"
        DAY1[Day1: $100]
        DAY2[Day2: $100]
        DAY3[Day3: $100]
        DAYN[Day30: $100]
    end

    AMOUNT --> DAY1
    FREQ --> DAY2
    DURATION --> DAYN

    subgraph "结果"
        TOTAL[总投资: $3000]
        AVG[平均成本: 动态]
    end
```

### 2. 百分比DCA

```mermaid
graph TB
    subgraph "百分比策略"
        BALANCE[账户余额]
        PERCENT[投资比例: 10%]
        MINMAX[最小/最大限制]
    end

    subgraph "动态计算"
        CALC[计算金额 = 余额 × 10%]
        CHECK[检查限制]
        ADJUST[调整金额]
    end

    BALANCE --> CALC
    PERCENT --> CALC
    CALC --> CHECK
    MINMAX --> CHECK
    CHECK --> ADJUST

    subgraph "执行"
        EXECUTE[执行交易]
    end

    ADJUST --> EXECUTE
```

### 3. 网格DCA

```mermaid
graph TB
    subgraph "网格设置"
        RANGE[价格区间: $100-200]
        GRIDS[网格数: 10]
        AMOUNT[每格金额: $50]
    end

    subgraph "价格网格"
        G1[网格1: $100]
        G2[网格2: $110]
        G3[网格3: $120]
        GN[网格10: $200]
    end

    subgraph "触发逻辑"
        PRICE[当前价格]
        TRIGGER[触发买入/卖出]
    end

    RANGE --> G1
    RANGE --> GN
    GRIDS --> G2
    GRIDS --> G3

    PRICE --> TRIGGER
    G1 --> TRIGGER
    G2 --> TRIGGER
    G3 --> TRIGGER
    GN --> TRIGGER
```

### 4. 智能DCA

```mermaid
flowchart TD
    A[市场数据] --> B[AI分析]
    B --> C{市场状态}

    C -->|上涨趋势| D[减少投资]
    C -->|下跌趋势| E[增加投资]
    C -->|震荡市场| F[标准投资]

    D --> G[动态调整金额]
    E --> G
    F --> G

    G --> H[技术指标检查]
    H --> I{RSI}

    I -->|超买 >70| J[暂停买入]
    I -->|超卖 <30| K[加倍买入]
    I -->|正常 30-70| L[正常买入]

    J --> M[执行决策]
    K --> M
    L --> M
```

## 调度系统设计

### 分布式调度架构

```mermaid
graph TB
    subgraph "调度集群"
        MASTER[主调度器]
        SLAVE1[从调度器1]
        SLAVE2[从调度器2]
        SLAVEN[从调度器N]
    end

    subgraph "任务分配"
        HASH[一致性哈希]
        PARTITION[分区策略]
        BALANCE[负载均衡]
    end

    subgraph "任务队列"
        HIGH[高优先级]
        NORMAL[普通优先级]
        LOW[低优先级]
    end

    MASTER --> HASH
    HASH --> PARTITION
    PARTITION --> BALANCE

    BALANCE --> SLAVE1
    BALANCE --> SLAVE2
    BALANCE --> SLAVEN

    SLAVE1 --> HIGH
    SLAVE1 --> NORMAL
    SLAVE1 --> LOW
```

### 执行时机优化

```mermaid
graph LR
    subgraph "时机选择"
        TIME[预定时间]
        PRICE[价格条件]
        VOLUME[成交量]
        VOLATILITY[波动率]
    end

    subgraph "优化算法"
        TWAP[时间加权]
        VWAP[成交量加权]
        SMART[智能路由]
    end

    subgraph "执行窗口"
        WINDOW[执行时间窗]
        RANDOM[随机延迟]
        BATCH[批量合并]
    end

    TIME --> TWAP
    PRICE --> VWAP
    VOLUME --> SMART
    VOLATILITY --> SMART

    TWAP --> WINDOW
    VWAP --> WINDOW
    SMART --> RANDOM

    WINDOW --> BATCH
    RANDOM --> BATCH
```

## 风险控制

### 价格保护机制

```mermaid
flowchart TD
    A[获取实时价格] --> B{价格检查}

    B -->|价格正常| C[继续执行]
    B -->|价格异常| D[触发保护]

    D --> E{偏离程度}
    E -->|<5%| F[警告但执行]
    E -->|5-10%| G[需要确认]
    E -->|>10%| H[自动取消]

    F --> I[记录日志]
    G --> J{用户确认}
    J -->|确认| C
    J -->|拒绝| H

    H --> K[暂停策略]
    K --> L[通知用户]

    C --> M[执行交易]
    I --> M
```

### 资金安全

```mermaid
graph TB
    subgraph "资金隔离"
        MAIN[主账户]
        DCA_POOL[DCA资金池]
        RESERVE[保证金]
    end

    subgraph "权限控制"
        LIMIT[单次限额]
        DAILY[日限额]
        TOTAL[总限额]
    end

    subgraph "审计追踪"
        LOG[操作日志]
        SNAPSHOT[余额快照]
        AUDIT[审计报告]
    end

    MAIN --> |划转| DCA_POOL
    DCA_POOL --> |预留| RESERVE

    DCA_POOL --> LIMIT
    LIMIT --> DAILY
    DAILY --> TOTAL

    DCA_POOL --> LOG
    DCA_POOL --> SNAPSHOT
    LOG --> AUDIT
    SNAPSHOT --> AUDIT
```

## 性能优化

### 批量执行优化

```mermaid
sequenceDiagram
    participant Scheduler
    participant Aggregator
    participant BatchExecutor
    participant SmartContract
    participant Blockchain

    loop 收集待执行策略
        Scheduler->>Aggregator: 添加策略
    end

    Aggregator->>Aggregator: 达到批量阈值

    Aggregator->>BatchExecutor: 批量执行请求
    BatchExecutor->>BatchExecutor: 合并相同交易对
    BatchExecutor->>BatchExecutor: 优化Gas使用

    BatchExecutor->>SmartContract: 批量交易调用
    SmartContract->>Blockchain: 单笔交易多个DCA
    Blockchain-->>SmartContract: 确认
    SmartContract-->>BatchExecutor: 执行结果

    BatchExecutor->>BatchExecutor: 分配结果
    BatchExecutor-->>Aggregator: 批量完成
```

## 监控和分析

### 性能指标仪表板

```mermaid
graph TB
    subgraph "实时监控"
        subgraph "执行指标"
            SUCCESS[成功率: 98.5%]
            FAILED[失败率: 1.5%]
            PENDING[待执行: 234]
        end

        subgraph "性能指标"
            AVG_TIME[平均执行: 2.3s]
            GAS_SAVED[Gas节省: 45%]
            BATCH_SIZE[批量大小: 25]
        end

        subgraph "业务指标"
            ACTIVE[活跃策略: 1,234]
            VOLUME[日交易量: $2.5M]
            USERS[活跃用户: 456]
        end
    end

    subgraph "历史分析"
        TREND[趋势图表]
        COMPARE[对比分析]
        REPORT[定期报告]
    end
```

### 策略效果分析

```mermaid
graph LR
    subgraph "投资分析"
        COST[成本基础]
        CURRENT[当前价值]
        PNL[盈亏计算]
    end

    subgraph "对比分析"
        DCA_PERF[DCA表现]
        LUMP_SUM[一次性投资]
        BENCHMARK[基准对比]
    end

    subgraph "报告输出"
        CHART[图表展示]
        TABLE[数据表格]
        EXPORT[导出报告]
    end

    COST --> PNL
    CURRENT --> PNL
    PNL --> DCA_PERF

    DCA_PERF --> BENCHMARK
    LUMP_SUM --> BENCHMARK

    BENCHMARK --> CHART
    BENCHMARK --> TABLE
    CHART --> EXPORT
    TABLE --> EXPORT
```

## API接口定义

### 创建DCA策略

```typescript
interface CreateDCAStrategyRequest {
  name: string;                  // 策略名称
  tokenIn: string;              // 买入使用的代币
  tokenOut: string;             // 买入目标代币
  strategyType: DCAType;        // 策略类型

  // 金额配置
  amountPerExecution?: string;  // 固定金额
  percentagePerExecution?: number; // 百分比
  minAmount?: string;           // 最小金额
  maxAmount?: string;           // 最大金额

  // 时间配置
  frequency: Frequency;         // 执行频率
  startTime: number;           // 开始时间
  endTime?: number;            // 结束时间
  totalExecutions?: number;     // 总执行次数

  // 条件配置
  priceCondition?: PriceCondition; // 价格条件
  slippageTolerance: number;   // 滑点容差
  gasStrategy: GasStrategy;    // Gas策略
}

interface DCAStrategyResponse {
  strategyId: string;          // 策略ID
  status: StrategyStatus;      // 策略状态
  nextExecution: number;       // 下次执行时间
  executedCount: number;       // 已执行次数
  remainingCount: number;      // 剩余次数
  totalInvested: string;       // 总投资金额
  averagePrice: string;        // 平均成本
  currentValue: string;        // 当前价值
  pnl: string;                // 盈亏
  pnlPercentage: number;      // 盈亏百分比
}

enum DCAType {
  FIXED_AMOUNT = "fixed_amount",
  PERCENTAGE = "percentage",
  DYNAMIC = "dynamic",
  GRID = "grid"
}

enum Frequency {
  HOURLY = "hourly",
  DAILY = "daily",
  WEEKLY = "weekly",
  MONTHLY = "monthly",
  CUSTOM = "custom"
}

enum StrategyStatus {
  DRAFT = "draft",
  ACTIVE = "active",
  PAUSED = "paused",
  COMPLETED = "completed",
  CANCELLED = "cancelled",
  EXPIRED = "expired"
}
```

### 执行记录查询

```typescript
interface DCAExecutionRecord {
  executionId: string;         // 执行ID
  strategyId: string;         // 策略ID
  executionTime: number;      // 执行时间
  status: ExecutionStatus;    // 执行状态

  // 交易详情
  amountIn: string;           // 投入金额
  amountOut: string;          // 获得金额
  executionPrice: string;     // 执行价格
  marketPrice: string;        // 市场价格
  slippage: number;          // 实际滑点

  // Gas信息
  gasUsed: string;           // Gas消耗
  gasPrice: string;          // Gas价格
  transactionHash?: string;  // 交易哈希

  // 错误信息
  error?: string;            // 错误信息
  retryCount?: number;       // 重试次数
}
```

## 实现要点

1. **可靠执行**
   - 分布式锁防重复
   - 事务性保证
   - 自动重试机制

2. **成本优化**
   - 批量执行节省Gas
   - 智能时机选择
   - 路径优化

3. **用户体验**
   - 灵活的策略配置
   - 实时状态通知
   - 详细的分析报告

4. **安全保障**
   - 资金隔离
   - 价格保护
   - 审计日志