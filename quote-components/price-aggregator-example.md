# 价格聚合器(Price Aggregator)实例详解

## 一、真实场景说明

假设用户想要用 **1000 USDT** 兑换 **ETH**，价格聚合器需要从多个来源获取价格，并计算出最优兑换方案。

## 二、数据源真实数据示例

### 1. DEX数据源 - Uniswap V3 返回数据

```json
{
  "source": "uniswap_v3",
  "timestamp": 1703145600,
  "data": {
    "pools": [
      {
        "id": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
        "token0": "USDC",
        "token1": "ETH",
        "fee": 500,  // 0.05%手续费
        "liquidity": "245678901234567890",
        "sqrtPriceX96": "1961969880806565721922586931275",
        "tick": 202162,
        "reserves": {
          "token0": "198765432100000",  // 198,765,432.1 USDC
          "token1": "56789012345678901234567"  // 56,789.012 ETH
        },
        "tvl_usd": 397530864.20
      },
      {
        "id": "0x11b815efb8f581194ae79006d24e0d814b7697f6",
        "token0": "WETH",
        "token1": "USDT",
        "fee": 3000,  // 0.3%手续费
        "liquidity": "34567890123456789",
        "reserves": {
          "token0": "12345678901234567890123",  // 12,345.678 ETH
          "token1": "27654321000000"  // 27,654,321 USDT
        },
        "tvl_usd": 55308642.00
      }
    ]
  }
}
```

### 2. DEX数据源 - SushiSwap 返回数据

```json
{
  "source": "sushiswap",
  "timestamp": 1703145601,
  "data": {
    "pairs": [
      {
        "id": "0x06da0fd433c1a5d7a4faa01111c044910a184553",
        "token0": {
          "symbol": "WETH",
          "decimals": 18,
          "reserve": "8765.432109876543210987"
        },
        "token1": {
          "symbol": "USDT",
          "decimals": 6,
          "reserve": "19654321.654321"
        },
        "totalSupply": "456789.123456789",
        "reserveUSD": "39308643.31",
        "volumeUSD": "1234567.89"
      }
    ]
  }
}
```

### 3. 聚合器数据源 - 1inch 返回数据

```json
{
  "source": "1inch",
  "timestamp": 1703145599,
  "quote": {
    "fromToken": {
      "symbol": "USDT",
      "address": "0xdac17f958d2ee523a2206206994597c13d831ec7",
      "decimals": 6
    },
    "toToken": {
      "symbol": "ETH",
      "address": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "decimals": 18
    },
    "toAmount": "445566778899001122",  // 0.445566778899 ETH
    "fromAmount": "1000000000",  // 1000 USDT
    "protocols": [
      {
        "name": "UNISWAP_V3",
        "part": 70,  // 70%通过Uniswap V3
        "fromTokenAddress": "0xdac17f958d2ee523a2206206994597c13d831ec7",
        "toTokenAddress": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
      },
      {
        "name": "CURVE",
        "part": 30,  // 30%通过Curve
        "fromTokenAddress": "0xdac17f958d2ee523a2206206994597c13d831ec7",
        "toTokenAddress": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      }
    ],
    "estimatedGas": 185000
  }
}
```

### 4. 预言机数据源 - Chainlink 返回数据

```json
{
  "source": "chainlink",
  "timestamp": 1703145602,
  "prices": [
    {
      "pair": "ETH/USD",
      "price": 2245.67890123,
      "decimals": 8,
      "roundId": "18446744073709551915",
      "answeredInRound": "18446744073709551915",
      "updatedAt": 1703145598
    },
    {
      "pair": "USDT/USD",
      "price": 0.99985,
      "decimals": 8,
      "roundId": "18446744073709551914",
      "updatedAt": 1703145597
    }
  ]
}
```

## 三、价格聚合器的处理流程

### Step 1: 数据标准化

价格聚合器首先将所有不同格式的数据标准化为统一格式：

```typescript
interface StandardizedPrice {
  source: string;           // 数据源名称
  price: BigNumber;         // ETH/USDT价格
  liquidity: BigNumber;     // 可用流动性(USDT)
  fee: number;             // 手续费(基点)
  gasEstimate: number;      // Gas估算
  confidence: number;       // 置信度(0-1)
  timestamp: number;        // 时间戳
  route?: any[];           // 路由路径(可选)
}
```

**标准化后的数据示例：**

```javascript
const standardizedPrices = [
  {
    source: "uniswap_v3_pool_1",
    price: BigNumber.from("2243.56"),  // 1 ETH = 2243.56 USDT
    liquidity: BigNumber.from("198765432100000"),  // 可交易198M USDT
    fee: 5,  // 0.05% = 5基点
    gasEstimate: 120000,
    confidence: 0.98,
    timestamp: 1703145600
  },
  {
    source: "uniswap_v3_pool_2",
    price: BigNumber.from("2240.12"),  // 1 ETH = 2240.12 USDT
    liquidity: BigNumber.from("27654321000000"),  // 可交易27M USDT
    fee: 30,  // 0.3% = 30基点
    gasEstimate: 120000,
    confidence: 0.95,
    timestamp: 1703145600
  },
  {
    source: "sushiswap",
    price: BigNumber.from("2242.89"),  // 计算得出: 19654321.654321 / 8765.432109876543210987
    liquidity: BigNumber.from("19654321654321"),  // 可交易19M USDT
    fee: 30,  // 0.3%
    gasEstimate: 110000,
    confidence: 0.93,
    timestamp: 1703145601
  },
  {
    source: "1inch_aggregated",
    price: BigNumber.from("2244.23"),  // 计算得出: 1000 / 0.445566778899
    liquidity: BigNumber.from("1000000000000000"),  // 1inch聚合流动性
    fee: 0,  // 1inch已包含手续费
    gasEstimate: 185000,
    confidence: 0.96,
    timestamp: 1703145599
  },
  {
    source: "chainlink_oracle",
    price: BigNumber.from("2246.01"),  // 计算得出: 2245.67890123 / 0.99985
    liquidity: BigNumber.from("999999999999999"),  // 预言机价格,流动性设为最大
    fee: 0,  // 预言机参考价格无手续费
    gasEstimate: 0,
    confidence: 1.0,  // 预言机最高置信度
    timestamp: 1703145602
  }
];
```

### Step 2: 异常值检测与过滤

```javascript
// 计算价格中位数
const prices = standardizedPrices.map(p => p.price.toNumber()).sort((a,b) => a-b);
const median = prices[Math.floor(prices.length / 2)]; // 2243.56

// 计算标准差
const mean = prices.reduce((a,b) => a+b, 0) / prices.length; // 2243.36
const variance = prices.reduce((sum, price) => sum + Math.pow(price - mean, 2), 0) / prices.length;
const stdDev = Math.sqrt(variance); // 2.15

// 过滤异常值（超过2个标准差）
const filteredPrices = standardizedPrices.filter(p => {
  const deviation = Math.abs(p.price.toNumber() - median);
  return deviation <= stdDev * 2;
});

// 所有价格都在正常范围内，无需过滤
```

### Step 3: 流动性加权计算

```javascript
// 计算每个源的权重
function calculateWeight(price, totalAmount) {
  const liquidity = price.liquidity.toNumber();
  const confidence = price.confidence;
  const feeMultiplier = 1 - (price.fee / 10000); // 手续费影响
  const gasImpact = 1 - (price.gasEstimate / 10000000); // Gas影响(简化)

  // 综合权重 = 流动性权重 * 置信度 * 手续费影响 * Gas影响
  const weight = Math.min(liquidity, totalAmount) * confidence * feeMultiplier * gasImpact;
  return weight;
}

// 用户要交易1000 USDT
const tradeAmount = 1000;

const weights = filteredPrices.map(p => ({
  ...p,
  weight: calculateWeight(p, tradeAmount)
}));

// 权重计算结果示例：
/*
weights = [
  { source: "uniswap_v3_pool_1", weight: 1000 * 0.98 * 0.9995 * 0.988 = 968.11 },
  { source: "uniswap_v3_pool_2", weight: 1000 * 0.95 * 0.997 * 0.988 = 936.33 },
  { source: "sushiswap", weight: 1000 * 0.93 * 0.997 * 0.989 = 917.37 },
  { source: "1inch_aggregated", weight: 1000 * 0.96 * 1.0 * 0.9815 = 942.24 },
  { source: "chainlink_oracle", weight: 1000 * 1.0 * 1.0 * 1.0 = 1000 }
]
*/

const totalWeight = weights.reduce((sum, w) => sum + w.weight, 0); // 4764.05
```

### Step 4: 计算最终聚合价格

```javascript
// 加权平均价格计算
const weightedPrice = weights.reduce((sum, w) => {
  return sum + (w.price.toNumber() * w.weight);
}, 0) / totalWeight;

console.log("最终聚合价格: ", weightedPrice); // 2244.18 USDT/ETH

// 计算用户可获得的ETH数量
const userUSDT = 1000;
const estimatedETH = userUSDT / weightedPrice;
console.log("预计获得ETH: ", estimatedETH); // 0.4456 ETH
```

### Step 5: 最优路径选择

```javascript
// 分析最优执行路径
function findOptimalPath(amount, prices) {
  // 单路径最优
  const singlePath = prices.map(p => {
    const outputAmount = amount / p.price.toNumber();
    const fee = amount * p.fee / 10000;
    const netOutput = outputAmount * (1 - p.fee / 10000);
    const gasCost = p.gasEstimate * 0.00003 * 2245; // Gas价格30Gwei, ETH价格2245

    return {
      source: p.source,
      outputAmount: netOutput,
      fee: fee,
      gasCost: gasCost,
      totalCost: fee + gasCost,
      effectivePrice: amount / netOutput
    };
  }).sort((a, b) => b.outputAmount - a.outputAmount);

  // 分割路径最优（将订单分割到多个池子）
  const splitPath = {
    routes: [
      { source: "uniswap_v3_pool_1", amount: 500, percentage: 50 },
      { source: "1inch_aggregated", amount: 300, percentage: 30 },
      { source: "sushiswap", amount: 200, percentage: 20 }
    ],
    totalOutput: 0.4461, // ETH
    totalFee: 0.85,     // USDT
    totalGas: 0.45,     // USDT
    effectivePrice: 2241.56
  };

  return {
    single: singlePath[0],
    split: splitPath,
    recommendation: splitPath.totalOutput > singlePath[0].outputAmount ? 'split' : 'single'
  };
}

const optimalPath = findOptimalPath(1000, weights);
```

## 四、实际执行示例

### 场景：用户执行1000 USDT → ETH兑换

#### 1. 用户请求
```json
{
  "from": "USDT",
  "to": "ETH",
  "amount": "1000",
  "slippage": 0.5,  // 0.5%滑点容忍度
  "gasPrice": "auto"
}
```

#### 2. 价格聚合器处理过程

```javascript
class PriceAggregator {
  async getQuote(request) {
    // 步骤1: 并行获取所有数据源价格
    const rawPrices = await Promise.all([
      this.fetchUniswapV3Price(request),
      this.fetchSushiswapPrice(request),
      this.fetch1inchPrice(request),
      this.fetchChainlinkPrice(request)
    ]);

    // 步骤2: 标准化数据
    const standardized = this.standardizePrices(rawPrices);

    // 步骤3: 过滤异常值
    const filtered = this.filterOutliers(standardized);

    // 步骤4: 计算权重
    const weighted = this.calculateWeights(filtered, request.amount);

    // 步骤5: 生成最优报价
    const quote = this.generateQuote(weighted, request);

    return quote;
  }
}
```

#### 3. 返回给用户的报价

```json
{
  "id": "quote_1703145603_abc123",
  "timestamp": 1703145603,
  "request": {
    "from": "USDT",
    "to": "ETH",
    "amount": "1000"
  },
  "quote": {
    "estimatedOutput": "0.4461",
    "minimumOutput": "0.4439",  // 考虑0.5%滑点
    "effectivePrice": "2241.56",
    "priceImpact": "0.12%",
    "route": {
      "type": "split",
      "paths": [
        {
          "protocol": "Uniswap V3",
          "pool": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
          "amount": "500",
          "percentage": 50,
          "output": "0.2228"
        },
        {
          "protocol": "1inch",
          "amount": "300",
          "percentage": 30,
          "output": "0.1337"
        },
        {
          "protocol": "SushiSwap",
          "pool": "0x06da0fd433c1a5d7a4faa01111c044910a184553",
          "amount": "200",
          "percentage": 20,
          "output": "0.0896"
        }
      ]
    },
    "fees": {
      "swapFee": "0.85",
      "gasFee": "0.45",
      "totalFee": "1.30"
    },
    "execution": {
      "estimatedGas": "285000",
      "gasPrice": "30000000000",  // 30 Gwei
      "executionTime": "15"  // 秒
    },
    "metadata": {
      "sources": 5,
      "confidence": 0.96,
      "priceDeviation": "0.08%",
      "liquidityDepth": "245M"
    }
  },
  "expiry": 1703145633  // 30秒后过期
}
```

## 五、核心数据结构详解

### 1. 流动性池数据结构

```typescript
interface LiquidityPool {
  // 基础信息
  id: string;                    // 池子唯一标识
  protocol: string;              // 协议名称(Uniswap, Sushi等)
  version: string;               // 协议版本(V2, V3等)

  // 代币信息
  token0: {
    address: string;             // 代币合约地址
    symbol: string;              // 代币符号
    decimals: number;            // 小数位数
    reserve: BigNumber;          // 储备量
    weight?: number;             // 权重(Balancer池)
  };
  token1: {
    address: string;
    symbol: string;
    decimals: number;
    reserve: BigNumber;
    weight?: number;
  };

  // 流动性信息
  liquidity: BigNumber;          // 总流动性
  sqrtPriceX96?: BigNumber;     // V3价格(Q64.96格式)
  tick?: number;                 // V3当前tick
  fee: number;                   // 手续费(基点)

  // 统计信息
  volume24h: BigNumber;          // 24小时交易量
  tvlUSD: number;                // 总锁仓价值(USD)
  apy?: number;                  // 年化收益率
}
```

### 2. 价格数据结构

```typescript
interface PriceData {
  // 价格信息
  spotPrice: BigNumber;          // 即时价格
  executionPrice: BigNumber;     // 执行价格(含滑点)
  impactPrice: BigNumber;        // 价格影响后的价格
  oraclePrice?: BigNumber;       // 预言机价格(参考)

  // 深度信息
  bids: Array<{
    price: BigNumber;
    amount: BigNumber;
    total: BigNumber;
  }>;
  asks: Array<{
    price: BigNumber;
    amount: BigNumber;
    total: BigNumber;
  }>;

  // 统计信息
  spread: BigNumber;             // 买卖价差
  depth2Percent: BigNumber;      // 2%深度
  depth5Percent: BigNumber;      // 5%深度
}
```

### 3. 路由数据结构

```typescript
interface Route {
  // 路由基础信息
  id: string;
  type: 'single' | 'split' | 'multi-hop';

  // 路径信息
  paths: Array<{
    pools: LiquidityPool[];      // 经过的池子
    tokens: string[];            // 代币路径
    amounts: BigNumber[];        // 每步金额
    fees: number[];              // 每步手续费
    percentage: number;          // 该路径占比
  }>;

  // 执行信息
  inputAmount: BigNumber;        // 输入金额
  outputAmount: BigNumber;       // 输出金额
  minimumOutput: BigNumber;      // 最小输出(含滑点)
  priceImpact: number;           // 价格影响

  // Gas信息
  estimatedGas: number;          // 预估Gas
  gasPrice: BigNumber;          // Gas价格
  maxPriorityFee?: BigNumber;   // EIP-1559优先费

  // 元数据
  confidence: number;            // 路由置信度
  complexity: number;            // 复杂度评分
  profitability: number;         // 收益评分
}
```

## 六、实时更新机制

### WebSocket推送示例

```javascript
// 价格更新推送
ws.on('price_update', (data) => {
  /*
  {
    "type": "price_update",
    "pair": "ETH/USDT",
    "source": "uniswap_v3",
    "price": "2245.89",
    "volume": "12345.67",
    "timestamp": 1703145610,
    "change_24h": "+2.15%"
  }
  */
  priceAggregator.updatePrice(data);
});

// 流动性变化推送
ws.on('liquidity_change', (data) => {
  /*
  {
    "type": "liquidity_change",
    "pool": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
    "event": "add",  // add/remove
    "amount0": "1000000",
    "amount1": "445.67",
    "newTotalLiquidity": "245679901234567890"
  }
  */
  priceAggregator.updateLiquidity(data);
});

// 大额交易警报
ws.on('large_swap', (data) => {
  /*
  {
    "type": "large_swap",
    "pool": "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
    "from": "USDT",
    "to": "ETH",
    "amount": "5000000",
    "priceImpact": "1.25%",
    "newPrice": "2251.34"
  }
  */
  priceAggregator.handleLargeSwap(data);
});
```

## 七、故障处理实例

### 1. 数据源超时处理

```javascript
async fetchWithTimeout(source, timeout = 3000) {
  try {
    const result = await Promise.race([
      source.fetchPrice(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Timeout')), timeout)
      )
    ]);
    return result;
  } catch (error) {
    // 使用缓存价格
    const cachedPrice = this.cache.get(source.name);
    if (cachedPrice && Date.now() - cachedPrice.timestamp < 30000) {
      console.log(`Using cached price for ${source.name}`);
      return { ...cachedPrice, stale: true };
    }
    // 标记数据源不可用
    return { source: source.name, available: false };
  }
}
```

### 2. 价格异常处理

```javascript
// 检测价格操纵
function detectPriceManipulation(prices) {
  const deviations = prices.map(p => {
    const others = prices.filter(x => x.source !== p.source);
    const avgOthers = others.reduce((sum, x) => sum + x.price, 0) / others.length;
    return {
      source: p.source,
      deviation: Math.abs(p.price - avgOthers) / avgOthers
    };
  });

  // 偏差超过5%视为异常
  const suspicious = deviations.filter(d => d.deviation > 0.05);
  if (suspicious.length > 0) {
    console.warn('Potential price manipulation detected:', suspicious);
    // 触发警报
    this.alert.send({
      type: 'PRICE_MANIPULATION',
      sources: suspicious,
      timestamp: Date.now()
    });
  }
}
```

## 八、性能优化实例

### 1. 缓存策略

```javascript
class PriceCache {
  constructor() {
    this.cache = new Map();
    this.hotCache = new Map();  // 热点数据缓存
  }

  get(key) {
    // 优先从热点缓存获取
    if (this.hotCache.has(key)) {
      const hot = this.hotCache.get(key);
      if (Date.now() - hot.timestamp < 1000) {  // 1秒内有效
        return hot.data;
      }
    }

    // 从主缓存获取
    if (this.cache.has(key)) {
      const cached = this.cache.get(key);
      if (Date.now() - cached.timestamp < 5000) {  // 5秒内有效
        // 热点数据提升
        if (cached.hits > 10) {
          this.hotCache.set(key, cached);
        }
        cached.hits++;
        return cached.data;
      }
    }

    return null;
  }
}
```

### 2. 批量请求优化

```javascript
class BatchPriceRequest {
  constructor() {
    this.pendingRequests = [];
    this.batchTimer = null;
  }

  async request(params) {
    return new Promise((resolve, reject) => {
      this.pendingRequests.push({ params, resolve, reject });

      if (!this.batchTimer) {
        this.batchTimer = setTimeout(() => this.executeBatch(), 10);
      }
    });
  }

  async executeBatch() {
    const batch = this.pendingRequests.splice(0, 100);  // 最多100个
    this.batchTimer = null;

    try {
      // 合并请求
      const results = await this.batchFetch(batch.map(r => r.params));

      // 分发结果
      batch.forEach((req, i) => {
        req.resolve(results[i]);
      });
    } catch (error) {
      batch.forEach(req => req.reject(error));
    }
  }
}
```

## 总结

价格聚合器通过以下关键步骤实现最优价格发现：

1. **多源数据采集** - 并行从DEX、聚合器、预言机获取数据
2. **数据标准化** - 统一不同格式的价格数据
3. **异常值过滤** - 使用统计方法过滤异常价格
4. **权重计算** - 基于流动性、置信度、手续费等因素计算权重
5. **价格聚合** - 加权平均得出最终价格
6. **路径优化** - 找出最优执行路径（单路径或分割路径）
7. **实时更新** - WebSocket推送价格变化
8. **故障处理** - 超时、异常检测、降级策略
9. **性能优化** - 多级缓存、批量请求

通过这些机制，价格聚合器能为用户提供最优的兑换价格和执行路径。