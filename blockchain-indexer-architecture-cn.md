# 区块链索引器架构设计

## 1. 概述

### 1.1 什么是区块链索引器？

```
【定义】
区块链索引器 = 从区块链上「抓取」数据 → 「解析」→ 「存储」→ 「提供查询」

【类比】
区块链就像一本不断增长的流水账，每一页（区块）记录着交易
索引器就像「会计」，把流水账整理成：
├── 按用户分类的账单
├── 按代币分类的价格走势
├── 按池子分类的流动性数据
└── 方便快速查询和分析

【为什么需要索引器？】
直接查区块链很慢！
├── 查一个用户的所有交易 → 要遍历所有区块 → 几小时
├── 查一个代币的价格历史 → 要解析所有相关事件 → 非常慢
└── 用索引器 → 已经整理好了 → 毫秒级响应
```

### 1.2 在 DEX 架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        DEX 系统架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐                 │
│   │ 报价服务  │    │ 路由引擎  │    │ 分析引擎  │                 │
│   └────┬─────┘    └────┬─────┘    └────┬─────┘                 │
│        │               │               │                        │
│        └───────────────┼───────────────┘                        │
│                        ↓                                        │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                   数据层                                  │   │
│   │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐│   │
│   │  │ 价格聚合器  │  │ 流动性监控  │  │ 【区块链索引器】    ││   │
│   │  └──────┬─────┘  └──────┬─────┘  └─────────┬──────────┘│   │
│   │         └───────────────┼──────────────────┘           │   │
│   └─────────────────────────┼───────────────────────────────┘   │
│                             ↓                                   │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    区块链层                               │   │
│   │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────────┐  │   │
│   │  │ ETH │ │ BSC │ │ ARB │ │ POLY│ │ SOL │ │ 40+条链  │  │   │
│   │  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────────┘  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 索引器的核心职责

| 职责 | 说明 | 下游消费者 |
|------|------|-----------|
| **代币数据索引** | 代币地址、精度、符号、总供应量 | 报价服务、前端 |
| **价格数据索引** | 从 DEX 池子计算实时价格 | 价格聚合器、路由引擎 |
| **流动性数据索引** | 池子 TVL、储备量、费率 | 流动性监控、路由引擎 |
| **交易数据索引** | Swap 事件、交易量统计 | 分析引擎、前端 |
| **用户数据索引** | 用户的交易历史、持仓 | 用户服务、前端 |

---

## 2. 整体架构

### 2.1 高层架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          区块链索引器系统                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        数据采集层                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │   │
│  │  │ 区块监听器   │  │ 事件订阅器  │  │ RPC 轮询器（回填用）      │ │   │
│  │  │ (WebSocket) │  │ (Logs)      │  │ (eth_getLogs)           │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘ │   │
│  │         └────────────────┼──────────────────────┘              │   │
│  └──────────────────────────┼─────────────────────────────────────┘   │
│                             ↓                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        数据处理层                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │   │
│  │  │ 事件解码器   │  │ 数据转换器  │  │ 业务逻辑处理器            │ │   │
│  │  │ (ABI解析)   │  │ (标准化)    │  │ (价格计算/TVL统计)       │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘ │   │
│  │         └────────────────┼──────────────────────┘              │   │
│  └──────────────────────────┼─────────────────────────────────────┘   │
│                             ↓                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        数据存储层                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │   │
│  │  │ PostgreSQL  │  │ TimescaleDB │  │ Redis                   │ │   │
│  │  │ (结构化数据) │  │ (时序数据)   │  │ (实时缓存)              │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                             ↓                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        数据服务层                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │   │
│  │  │ REST API    │  │ GraphQL     │  │ WebSocket 推送           │ │   │
│  │  │ (查询接口)   │  │ (灵活查询)  │  │ (实时订阅)              │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 多链索引架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          多链索引器架构                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                    ┌─────────────────────┐                              │
│                    │   链管理器           │                              │
│                    │   Chain Manager     │                              │
│                    └──────────┬──────────┘                              │
│                               │                                         │
│           ┌───────────────────┼───────────────────┐                     │
│           ↓                   ↓                   ↓                     │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐           │
│  │  EVM 索引器      │ │  EVM 索引器      │ │  非EVM 索引器    │           │
│  │  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │           │
│  │  │ Ethereum  │  │ │  │ BSC       │  │ │  │ Solana    │  │           │
│  │  │ Arbitrum  │  │ │  │ Polygon   │  │ │  │ Sui       │  │           │
│  │  │ Optimism  │  │ │  │ Avalanche │  │ │  │ Aptos     │  │           │
│  │  │ Base      │  │ │  │ Fantom    │  │ │  │ Ton       │  │           │
│  │  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │           │
│  └────────┬────────┘ └────────┬────────┘ └────────┬────────┘           │
│           │                   │                   │                     │
│           └───────────────────┼───────────────────┘                     │
│                               ↓                                         │
│                    ┌─────────────────────┐                              │
│                    │   统一数据模型       │                              │
│                    │   Unified Schema    │                              │
│                    └─────────────────────┘                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心模块设计

### 3.1 数据采集模块

#### 3.1.1 区块监听器（Block Listener）

```
【功能】
实时监听新区块，触发数据索引流程

【实现方式】
├── WebSocket 订阅：eth_subscribe("newHeads")
├── 轮询备份：每 N 秒调用 eth_blockNumber
└── 多 RPC 冗余：主节点挂了自动切换

【代码示例】
```

```javascript
// 区块监听器
class BlockListener {
  constructor(config) {
    this.chainId = config.chainId;
    this.rpcUrls = config.rpcUrls;  // 多个 RPC 节点
    this.currentRpcIndex = 0;
    this.lastBlockNumber = 0;
  }

  // 启动监听
  async start() {
    // 1. WebSocket 订阅新区块
    this.ws = new WebSocket(this.getWsUrl());

    this.ws.on('open', () => {
      this.ws.send(JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'eth_subscribe',
        params: ['newHeads']
      }));
    });

    this.ws.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.params?.result) {
        const blockNumber = parseInt(msg.params.result.number, 16);
        this.onNewBlock(blockNumber, msg.params.result);
      }
    });

    // 2. 轮询备份（防止 WebSocket 断连丢块）
    this.pollInterval = setInterval(() => this.pollBlocks(), 3000);
  }

  // 处理新区块
  async onNewBlock(blockNumber, blockHeader) {
    // 检查是否漏块
    if (blockNumber > this.lastBlockNumber + 1) {
      // 有漏块，需要回填
      for (let i = this.lastBlockNumber + 1; i < blockNumber; i++) {
        await this.indexBlock(i);
      }
    }

    this.lastBlockNumber = blockNumber;

    // 发送到处理队列
    await this.queue.push({
      type: 'NEW_BLOCK',
      chainId: this.chainId,
      blockNumber,
      blockHeader
    });
  }
}
```

#### 3.1.2 事件订阅器（Event Subscriber）

```
【功能】
订阅特定合约的特定事件（如 Swap、Mint、Burn）

【为什么用事件而不是交易？】
├── 事件是合约「主动广播」的，更结构化
├── 一笔交易可能触发多个事件
├── 事件带有 indexed 字段，便于过滤
└── 比解析交易 input data 更简单可靠

【核心事件类型】
```

| 协议 | 事件名 | 用途 |
|------|--------|------|
| Uniswap V2 | `Swap(sender, amount0In, amount1In, amount0Out, amount1Out, to)` | 交易记录、价格计算 |
| Uniswap V2 | `Sync(reserve0, reserve1)` | 池子储备更新 |
| Uniswap V2 | `Mint(sender, amount0, amount1)` | 添加流动性 |
| Uniswap V2 | `Burn(sender, amount0, amount1, to)` | 移除流动性 |
| Uniswap V3 | `Swap(sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick)` | 交易 + 价格 |
| ERC20 | `Transfer(from, to, value)` | 代币转账 |
| ERC20 | `Approval(owner, spender, value)` | 授权 |

```javascript
// 事件订阅器
class EventSubscriber {
  constructor(config) {
    this.chainId = config.chainId;
    this.provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);

    // 定义要监听的事件签名
    this.eventSignatures = {
      // Uniswap V2
      'UniswapV2Swap': 'Swap(address,uint256,uint256,uint256,uint256,address)',
      'UniswapV2Sync': 'Sync(uint112,uint112)',

      // Uniswap V3
      'UniswapV3Swap': 'Swap(address,address,int256,int256,uint160,uint128,int24)',

      // ERC20
      'Transfer': 'Transfer(address,address,uint256)',
    };

    // 计算事件 topic
    this.topics = {};
    for (const [name, sig] of Object.entries(this.eventSignatures)) {
      this.topics[name] = ethers.utils.id(sig);
    }
  }

  // 订阅 DEX 池子事件
  async subscribePools(poolAddresses) {
    // 构建过滤器
    const filter = {
      address: poolAddresses,  // 只监听这些池子
      topics: [
        [
          this.topics['UniswapV2Swap'],
          this.topics['UniswapV2Sync'],
          this.topics['UniswapV3Swap']
        ]
      ]
    };

    // 监听事件
    this.provider.on(filter, (log) => {
      this.onEvent(log);
    });
  }

  // 处理事件
  async onEvent(log) {
    const eventType = this.identifyEventType(log.topics[0]);

    const event = {
      chainId: this.chainId,
      blockNumber: log.blockNumber,
      transactionHash: log.transactionHash,
      logIndex: log.logIndex,
      address: log.address,  // 池子地址
      eventType,
      rawData: log.data,
      topics: log.topics
    };

    // 发送到处理队列
    await this.queue.push(event);
  }
}
```

#### 3.1.3 历史数据回填器（Backfiller）

```
【功能】
索引历史区块数据，用于：
├── 新链接入时的历史数据导入
├── 漏块补齐
├── 新增代币/池子的历史数据回填
└── 数据修复

【挑战】
├── 数据量巨大（以太坊 1800万+ 区块）
├── RPC 请求有限制（rate limit）
├── 需要断点续传（中断后能继续）
└── 要处理区块重组（reorg）
```

```javascript
// 历史数据回填器
class Backfiller {
  constructor(config) {
    this.chainId = config.chainId;
    this.provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
    this.batchSize = config.batchSize || 1000;  // 每批处理的区块数
    this.concurrency = config.concurrency || 5;  // 并发数
  }

  // 回填指定范围的区块
  async backfill(fromBlock, toBlock, options = {}) {
    const {
      poolAddresses,  // 只索引特定池子
      eventTypes,     // 只索引特定事件
      onProgress      // 进度回调
    } = options;

    let currentBlock = fromBlock;

    while (currentBlock <= toBlock) {
      const endBlock = Math.min(currentBlock + this.batchSize - 1, toBlock);

      // 批量获取事件日志
      const logs = await this.provider.getLogs({
        fromBlock: currentBlock,
        toBlock: endBlock,
        address: poolAddresses,
        topics: eventTypes ? [eventTypes.map(e => this.topics[e])] : undefined
      });

      // 处理日志
      for (const log of logs) {
        await this.processLog(log);
      }

      // 保存进度（断点续传）
      await this.saveProgress(this.chainId, endBlock);

      // 进度回调
      if (onProgress) {
        onProgress({
          current: endBlock,
          total: toBlock,
          percentage: ((endBlock - fromBlock) / (toBlock - fromBlock) * 100).toFixed(2)
        });
      }

      currentBlock = endBlock + 1;

      // 限流：避免触发 RPC 限制
      await this.sleep(100);
    }
  }

  // 获取回填进度
  async getProgress(chainId) {
    return await this.db.query(
      'SELECT last_indexed_block FROM indexer_progress WHERE chain_id = $1',
      [chainId]
    );
  }

  // 保存回填进度
  async saveProgress(chainId, blockNumber) {
    await this.db.query(`
      INSERT INTO indexer_progress (chain_id, last_indexed_block, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (chain_id) DO UPDATE SET
        last_indexed_block = $2,
        updated_at = NOW()
    `, [chainId, blockNumber]);
  }
}
```

---

### 3.2 数据处理模块

#### 3.2.1 事件解码器（Event Decoder）

```
【功能】
把链上的原始十六进制数据 → 解码成 → 人类可读的结构化数据

【流程】
原始日志:
{
  topics: ['0xd78ad95f...', '0x000...router', '0x000...user'],
  data: '0x0000...00001234...00005678...'
}
    ↓ ABI 解码
结构化数据:
{
  event: 'Swap',
  sender: '0x7a250d56...',    // Uniswap Router
  amount0In: 10000000000n,    // 10000 USDT
  amount1In: 0n,
  amount0Out: 0n,
  amount1Out: 4445667788n,    // ~4.445 ETH
  to: '0x742d35Cc...'         // 用户地址
}
```

```javascript
// 事件解码器
class EventDecoder {
  constructor() {
    // 加载各协议的 ABI
    this.abis = {
      uniswapV2Pair: require('./abis/UniswapV2Pair.json'),
      uniswapV3Pool: require('./abis/UniswapV3Pool.json'),
      erc20: require('./abis/ERC20.json'),
      curvePool: require('./abis/CurvePool.json'),
      balancerVault: require('./abis/BalancerVault.json')
    };

    // 创建解码接口
    this.interfaces = {
      uniswapV2: new ethers.utils.Interface(this.abis.uniswapV2Pair),
      uniswapV3: new ethers.utils.Interface(this.abis.uniswapV3Pool),
      erc20: new ethers.utils.Interface(this.abis.erc20),
      curve: new ethers.utils.Interface(this.abis.curvePool),
      balancer: new ethers.utils.Interface(this.abis.balancerVault)
    };
  }

  // 解码事件
  decode(log, protocol) {
    const iface = this.interfaces[protocol];
    if (!iface) {
      throw new Error(`Unknown protocol: ${protocol}`);
    }

    try {
      const parsed = iface.parseLog(log);
      return {
        name: parsed.name,           // 事件名: 'Swap'
        signature: parsed.signature, // 完整签名
        args: this.formatArgs(parsed.args)  // 解码后的参数
      };
    } catch (e) {
      // 解码失败，可能是未知事件
      return null;
    }
  }

  // 格式化参数（BigNumber → string）
  formatArgs(args) {
    const result = {};
    for (const key of Object.keys(args)) {
      if (isNaN(parseInt(key))) {  // 跳过数字索引
        const value = args[key];
        if (ethers.BigNumber.isBigNumber(value)) {
          result[key] = value.toString();
        } else {
          result[key] = value;
        }
      }
    }
    return result;
  }

  // 根据池子地址判断协议
  async identifyProtocol(poolAddress) {
    // 可以通过查询池子的特定方法来判断
    // 例如 Uniswap V2 有 getReserves()
    // Uniswap V3 有 slot0()
    // Curve 有 get_virtual_price()
    // ...
  }
}
```

#### 3.2.2 价格计算器（Price Calculator）

```
【功能】
从池子储备数据计算代币价格

【不同 DEX 的价格计算方式】
```

```javascript
// 价格计算器
class PriceCalculator {

  // Uniswap V2 价格计算
  // 公式：price = reserve1 / reserve0
  calculateUniswapV2Price(reserve0, reserve1, token0Decimals, token1Decimals) {
    // 考虑精度差异
    const adjusted0 = BigInt(reserve0) * BigInt(10 ** (18 - token0Decimals));
    const adjusted1 = BigInt(reserve1) * BigInt(10 ** (18 - token1Decimals));

    // token0 相对于 token1 的价格
    const price = Number(adjusted1) / Number(adjusted0);
    return price;
  }

  // Uniswap V3 价格计算
  // 公式：price = (sqrtPriceX96 / 2^96)^2
  calculateUniswapV3Price(sqrtPriceX96, token0Decimals, token1Decimals) {
    const Q96 = BigInt(2) ** BigInt(96);
    const sqrtPrice = BigInt(sqrtPriceX96);

    // price = (sqrtPriceX96 / 2^96)^2
    // 为避免精度丢失，先计算 sqrtPrice^2，再除以 Q96^2
    const priceX192 = sqrtPrice * sqrtPrice;
    const Q192 = Q96 * Q96;

    // 调整精度
    const decimalAdjustment = 10 ** (token1Decimals - token0Decimals);
    const price = Number(priceX192) / Number(Q192) * decimalAdjustment;

    return price;
  }

  // Curve 价格计算（StableSwap）
  // Curve 使用不同的定价曲线，需要调用合约方法
  async calculateCurvePrice(poolAddress, tokenInIndex, tokenOutIndex, provider) {
    const pool = new ethers.Contract(poolAddress, curveAbi, provider);

    // 使用 get_dy 模拟交易获取价格
    const amountIn = ethers.utils.parseUnits('1', 18);  // 1 个代币
    const amountOut = await pool.get_dy(tokenInIndex, tokenOutIndex, amountIn);

    const price = Number(amountOut) / Number(amountIn);
    return price;
  }

  // Balancer 价格计算（加权池）
  // 公式：spotPrice = (Bi / Wi) / (Bo / Wo)
  calculateBalancerPrice(balanceIn, weightIn, balanceOut, weightOut) {
    // Bi = balance of token in
    // Wi = weight of token in
    // Bo = balance of token out
    // Wo = weight of token out
    const spotPrice = (balanceIn / weightIn) / (balanceOut / weightOut);
    return spotPrice;
  }
}
```

```
【价格计算可视化】

┌─────────────────────────────────────────────────────────────────┐
│                    Uniswap V2 价格计算                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   池子状态：                                                     │
│   ┌─────────────────────────────────────────────────┐          │
│   │  USDT: 10,000,000    │    ETH: 4,444           │          │
│   │  (reserve0)          │    (reserve1)           │          │
│   └─────────────────────────────────────────────────┘          │
│                                                                 │
│   计算 ETH 价格（以 USDT 计）：                                  │
│   price = reserve0 / reserve1                                   │
│         = 10,000,000 / 4,444                                   │
│         = 2250.45 USDT/ETH                                     │
│                                                                 │
│   计算 USDT 价格（以 ETH 计）：                                  │
│   price = reserve1 / reserve0                                   │
│         = 4,444 / 10,000,000                                   │
│         = 0.0004444 ETH/USDT                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.2.3 流动性计算器（Liquidity Calculator）

```javascript
// 流动性计算器
class LiquidityCalculator {

  // 计算池子 TVL（总锁仓价值）
  async calculateTVL(pool, priceService) {
    const { token0, token1, reserve0, reserve1 } = pool;

    // 获取代币的 USD 价格
    const price0 = await priceService.getUsdPrice(token0.address);
    const price1 = await priceService.getUsdPrice(token1.address);

    // 计算各代币的 USD 价值
    const value0 = (Number(reserve0) / 10 ** token0.decimals) * price0;
    const value1 = (Number(reserve1) / 10 ** token1.decimals) * price1;

    // TVL = 两边价值之和
    const tvl = value0 + value1;

    return {
      tvl,
      value0,
      value1,
      composition: {
        [token0.symbol]: (value0 / tvl * 100).toFixed(2) + '%',
        [token1.symbol]: (value1 / tvl * 100).toFixed(2) + '%'
      }
    };
  }

  // 计算 24 小时交易量
  async calculate24hVolume(poolAddress, fromTimestamp) {
    const swaps = await this.db.query(`
      SELECT
        SUM(amount_usd) as volume
      FROM swaps
      WHERE pool_address = $1
        AND timestamp >= $2
    `, [poolAddress, fromTimestamp]);

    return swaps.rows[0].volume || 0;
  }

  // 计算 APR（年化收益率）
  // APR = (24h 手续费 × 365 / TVL) × 100%
  async calculateAPR(poolAddress, feeRate) {
    const tvl = await this.getTVL(poolAddress);
    const volume24h = await this.calculate24hVolume(poolAddress);

    const fee24h = volume24h * feeRate;  // 24h 手续费收入
    const apr = (fee24h * 365 / tvl) * 100;

    return apr;
  }
}
```

---

### 3.3 数据存储模块

#### 3.3.1 数据库 Schema 设计

```sql
-- ============================================
-- 1. 链配置表
-- ============================================
CREATE TABLE chains (
    chain_id        INTEGER PRIMARY KEY,
    name            VARCHAR(50) NOT NULL,      -- 'Ethereum', 'BSC'
    short_name      VARCHAR(10) NOT NULL,      -- 'ETH', 'BSC'
    chain_type      VARCHAR(20) NOT NULL,      -- 'EVM', 'Solana', 'Sui'
    rpc_urls        JSONB NOT NULL,            -- RPC 节点列表
    ws_urls         JSONB,                     -- WebSocket 节点列表
    block_time      INTEGER NOT NULL,          -- 平均出块时间（毫秒）
    native_token    VARCHAR(10) NOT NULL,      -- 'ETH', 'BNB'
    explorer_url    VARCHAR(255),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- 2. 代币表
-- ============================================
CREATE TABLE tokens (
    id              SERIAL PRIMARY KEY,
    chain_id        INTEGER NOT NULL REFERENCES chains(chain_id),
    address         VARCHAR(66) NOT NULL,      -- 合约地址
    symbol          VARCHAR(20) NOT NULL,
    name            VARCHAR(100),
    decimals        INTEGER NOT NULL,
    logo_url        VARCHAR(255),
    coingecko_id    VARCHAR(100),              -- CoinGecko ID，用于获取价格
    is_verified     BOOLEAN DEFAULT FALSE,     -- 是否经过验证
    total_supply    NUMERIC(78),
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),

    UNIQUE(chain_id, address)
);

CREATE INDEX idx_tokens_chain_address ON tokens(chain_id, address);
CREATE INDEX idx_tokens_symbol ON tokens(symbol);

-- ============================================
-- 3. DEX 协议表
-- ============================================
CREATE TABLE dex_protocols (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(50) NOT NULL,      -- 'Uniswap V2', 'Curve'
    version         VARCHAR(10),               -- 'V2', 'V3'
    chain_id        INTEGER NOT NULL REFERENCES chains(chain_id),
    factory_address VARCHAR(66),               -- 工厂合约地址
    router_address  VARCHAR(66),               -- 路由合约地址
    fee_rate        NUMERIC(10, 6),            -- 默认费率
    protocol_type   VARCHAR(20) NOT NULL,      -- 'AMM', 'StableSwap', 'Concentrated'
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- 4. 流动性池表
-- ============================================
CREATE TABLE liquidity_pools (
    id              SERIAL PRIMARY KEY,
    chain_id        INTEGER NOT NULL REFERENCES chains(chain_id),
    protocol_id     INTEGER NOT NULL REFERENCES dex_protocols(id),
    address         VARCHAR(66) NOT NULL,      -- 池子合约地址
    token0_id       INTEGER NOT NULL REFERENCES tokens(id),
    token1_id       INTEGER NOT NULL REFERENCES tokens(id),
    fee_rate        NUMERIC(10, 6),            -- 手续费率（V3 每个池子不同）

    -- Uniswap V3 特有
    tick_spacing    INTEGER,

    -- Balancer 特有
    pool_id         VARCHAR(66),               -- Balancer poolId
    weights         JSONB,                     -- 权重配置

    created_at_block INTEGER,
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),

    UNIQUE(chain_id, address)
);

CREATE INDEX idx_pools_chain_address ON liquidity_pools(chain_id, address);
CREATE INDEX idx_pools_tokens ON liquidity_pools(token0_id, token1_id);

-- ============================================
-- 5. 池子储备表（最新状态）
-- ============================================
CREATE TABLE pool_reserves (
    pool_id         INTEGER PRIMARY KEY REFERENCES liquidity_pools(id),
    reserve0        NUMERIC(78) NOT NULL,
    reserve1        NUMERIC(78) NOT NULL,

    -- Uniswap V3 特有
    sqrt_price_x96  NUMERIC(78),
    liquidity       NUMERIC(78),
    tick            INTEGER,

    -- 统计数据
    tvl_usd         NUMERIC(20, 2),
    volume_24h_usd  NUMERIC(20, 2),

    block_number    INTEGER NOT NULL,
    updated_at      TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- 6. Swap 交易表
-- ============================================
CREATE TABLE swaps (
    id              BIGSERIAL PRIMARY KEY,
    chain_id        INTEGER NOT NULL,
    pool_id         INTEGER NOT NULL REFERENCES liquidity_pools(id),
    transaction_hash VARCHAR(66) NOT NULL,
    log_index       INTEGER NOT NULL,
    block_number    INTEGER NOT NULL,
    timestamp       TIMESTAMP NOT NULL,

    -- 交易数据
    sender          VARCHAR(66) NOT NULL,
    recipient       VARCHAR(66) NOT NULL,
    amount0_in      NUMERIC(78),
    amount1_in      NUMERIC(78),
    amount0_out     NUMERIC(78),
    amount1_out     NUMERIC(78),
    amount_usd      NUMERIC(20, 2),           -- USD 价值

    -- 价格数据
    price           NUMERIC(40, 18),           -- 成交价格

    created_at      TIMESTAMP DEFAULT NOW(),

    UNIQUE(chain_id, transaction_hash, log_index)
);

-- 按时间分区，提高查询性能
CREATE INDEX idx_swaps_pool_time ON swaps(pool_id, timestamp DESC);
CREATE INDEX idx_swaps_block ON swaps(chain_id, block_number);

-- ============================================
-- 7. 价格历史表（时序数据）
-- 使用 TimescaleDB 扩展
-- ============================================
CREATE TABLE token_prices (
    time            TIMESTAMPTZ NOT NULL,
    chain_id        INTEGER NOT NULL,
    token_address   VARCHAR(66) NOT NULL,
    price_usd       NUMERIC(40, 18) NOT NULL,
    volume_24h      NUMERIC(20, 2),
    market_cap      NUMERIC(20, 2),
    source          VARCHAR(20)                -- 'dex', 'coingecko', 'chainlink'
);

-- 转换为 TimescaleDB 超表
SELECT create_hypertable('token_prices', 'time');

-- 创建连续聚合（自动计算 OHLCV）
CREATE MATERIALIZED VIEW token_prices_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    chain_id,
    token_address,
    first(price_usd, time) AS open,
    max(price_usd) AS high,
    min(price_usd) AS low,
    last(price_usd, time) AS close,
    sum(volume_24h) AS volume
FROM token_prices
GROUP BY bucket, chain_id, token_address;

-- ============================================
-- 8. 索引进度表
-- ============================================
CREATE TABLE indexer_progress (
    chain_id            INTEGER PRIMARY KEY REFERENCES chains(chain_id),
    last_indexed_block  INTEGER NOT NULL,
    last_indexed_time   TIMESTAMP,
    status              VARCHAR(20) DEFAULT 'running',  -- 'running', 'paused', 'error'
    error_message       TEXT,
    updated_at          TIMESTAMP DEFAULT NOW()
);
```

#### 3.3.2 缓存策略

```
┌─────────────────────────────────────────────────────────────────┐
│                        三级缓存架构                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  L1: 本地内存缓存（Node.js LRU Cache）                    │   │
│  │  ├── 热点代币信息（ETH, USDT, USDC...）                  │   │
│  │  ├── 常用池子储备                                        │   │
│  │  ├── 最近价格数据                                        │   │
│  │  └── TTL: 1-5 秒                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             ↓ miss                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  L2: Redis 集群缓存                                       │   │
│  │  ├── 所有代币信息                                        │   │
│  │  ├── 所有池子当前状态                                    │   │
│  │  ├── 价格数据（多时间粒度）                              │   │
│  │  ├── 用户查询结果                                        │   │
│  │  └── TTL: 10-60 秒                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             ↓ miss                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  L3: PostgreSQL / TimescaleDB                           │   │
│  │  ├── 完整历史数据                                        │   │
│  │  ├── 复杂聚合查询                                        │   │
│  │  └── 持久化存储                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

```javascript
// Redis 缓存 Key 设计
const CacheKeys = {
  // 代币信息
  TOKEN_INFO: (chainId, address) => `token:${chainId}:${address}`,

  // 池子储备
  POOL_RESERVES: (chainId, poolAddress) => `pool:reserves:${chainId}:${poolAddress}`,

  // 代币价格
  TOKEN_PRICE: (chainId, address) => `price:${chainId}:${address}`,

  // 价格历史（K线）
  PRICE_OHLCV: (chainId, address, interval) => `ohlcv:${chainId}:${address}:${interval}`,

  // 池子列表（按代币对）
  POOLS_BY_PAIR: (chainId, token0, token1) => `pools:pair:${chainId}:${token0}:${token1}`,

  // 热门代币排行
  TOP_TOKENS: (chainId, metric) => `ranking:tokens:${chainId}:${metric}`,

  // 索引进度
  INDEXER_PROGRESS: (chainId) => `indexer:progress:${chainId}`
};

// 缓存服务
class CacheService {
  constructor(redis) {
    this.redis = redis;
    this.localCache = new LRU({ max: 10000, ttl: 5000 });  // 5秒本地缓存
  }

  async get(key, fetchFn, ttl = 30) {
    // L1: 本地缓存
    let value = this.localCache.get(key);
    if (value) return value;

    // L2: Redis
    value = await this.redis.get(key);
    if (value) {
      value = JSON.parse(value);
      this.localCache.set(key, value);
      return value;
    }

    // L3: 数据库（通过 fetchFn）
    value = await fetchFn();
    if (value) {
      await this.redis.setex(key, ttl, JSON.stringify(value));
      this.localCache.set(key, value);
    }

    return value;
  }

  // 批量获取（减少网络往返）
  async mget(keys, fetchFn) {
    const values = await this.redis.mget(keys);
    const missing = [];
    const result = {};

    keys.forEach((key, i) => {
      if (values[i]) {
        result[key] = JSON.parse(values[i]);
      } else {
        missing.push(key);
      }
    });

    if (missing.length > 0) {
      const fetched = await fetchFn(missing);
      // 写入缓存并合并结果
      // ...
    }

    return result;
  }
}
```

---

## 4. 实时数据流设计

### 4.1 数据流水线架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          实时数据流水线                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────────────────┐ │
│   │ 区块链  │    │ Kafka   │    │ Flink/  │    │ 存储 + 推送         │ │
│   │ 节点    │───>│ 消息队列│───>│ Spark   │───>│ PostgreSQL/Redis/WS│ │
│   │         │    │         │    │ 流处理   │    │                     │ │
│   └─────────┘    └─────────┘    └─────────┘    └─────────────────────┘ │
│       │              │              │                    │              │
│       │              │              │                    │              │
│   ┌───┴───┐      ┌───┴───┐      ┌───┴───┐          ┌────┴────┐        │
│   │新区块 │      │ topic │      │ 事件  │          │ 实时    │        │
│   │新事件 │      │ 分区  │      │ 聚合  │          │ 价格    │        │
│   │       │      │ 有序  │      │ 计算  │          │ 推送    │        │
│   └───────┘      └───────┘      └───────┘          └─────────┘        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Kafka Topic 设计

```javascript
// Kafka Topic 结构
const KafkaTopics = {
  // 原始事件（按链分 topic）
  RAW_EVENTS: {
    pattern: 'indexer.{chainId}.raw-events',
    partitions: 32,
    replication: 3,
    retention: '7d'
  },

  // 解码后的 Swap 事件
  SWAPS: {
    pattern: 'indexer.swaps',
    partitions: 64,
    key: 'chainId:poolAddress',  // 按池子分区，保证同一池子事件有序
    retention: '30d'
  },

  // 价格更新
  PRICE_UPDATES: {
    pattern: 'indexer.prices',
    partitions: 32,
    key: 'chainId:tokenAddress',
    retention: '1d'
  },

  // 流动性更新
  LIQUIDITY_UPDATES: {
    pattern: 'indexer.liquidity',
    partitions: 32,
    key: 'chainId:poolAddress',
    retention: '1d'
  }
};
```

### 4.3 实时价格更新流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        实时价格更新流程                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   1. 链上事件产生                                                        │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │  Uniswap V2 池子触发 Sync 事件                           │          │
│   │  Sync(reserve0: 10001000000, reserve1: 4443000000000)   │          │
│   └───────────────────────────┬─────────────────────────────┘          │
│                               ↓                                         │
│   2. 索引器捕获事件                                                      │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │  EventSubscriber 收到事件，解码后发送到 Kafka            │          │
│   │  Topic: indexer.liquidity                               │          │
│   │  Key: 1:0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640     │          │
│   └───────────────────────────┬─────────────────────────────┘          │
│                               ↓                                         │
│   3. 流处理器计算新价格                                                  │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │  PriceCalculator.calculateUniswapV2Price()              │          │
│   │  新价格: 2251.23 USDT/ETH                               │          │
│   └───────────────────────────┬─────────────────────────────┘          │
│                               ↓                                         │
│   4. 更新存储 + 推送                                                     │
│   ┌─────────────────────────────────────────────────────────┐          │
│   │  a. 更新 Redis 缓存: SET price:1:0xC02a... 2251.23      │          │
│   │  b. 写入 TimescaleDB: INSERT INTO token_prices ...      │          │
│   │  c. WebSocket 推送: ws.broadcast({ eth: 2251.23 })      │          │
│   └─────────────────────────────────────────────────────────┘          │
│                                                                         │
│   延迟目标: 事件产生 → 前端收到价格更新 < 500ms                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 5. 多链适配设计

### 5.1 链抽象层

```javascript
// 链适配器接口
interface ChainAdapter {
  // 基础信息
  chainId: number;
  chainType: 'EVM' | 'Solana' | 'Sui' | 'Aptos';

  // 连接管理
  connect(): Promise<void>;
  disconnect(): Promise<void>;

  // 区块操作
  getLatestBlockNumber(): Promise<number>;
  getBlock(blockNumber: number): Promise<Block>;

  // 事件订阅
  subscribeLogs(filter: LogFilter): EventEmitter;
  getLogs(filter: LogFilter): Promise<Log[]>;

  // 合约调用
  call(contract: string, method: string, params: any[]): Promise<any>;
}

// EVM 链适配器
class EVMChainAdapter implements ChainAdapter {
  chainType = 'EVM';

  constructor(config: EVMChainConfig) {
    this.chainId = config.chainId;
    this.provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
  }

  async getLatestBlockNumber() {
    return await this.provider.getBlockNumber();
  }

  async getLogs(filter) {
    return await this.provider.getLogs(filter);
  }

  // ... 其他方法实现
}

// Solana 链适配器
class SolanaChainAdapter implements ChainAdapter {
  chainType = 'Solana';

  constructor(config: SolanaChainConfig) {
    this.chainId = config.chainId;
    this.connection = new Connection(config.rpcUrl);
  }

  async getLatestBlockNumber() {
    return await this.connection.getSlot();
  }

  async getLogs(filter) {
    // Solana 使用不同的日志查询方式
    return await this.connection.getSignaturesForAddress(
      filter.address,
      { limit: filter.limit }
    );
  }

  // ... 其他方法实现
}
```

### 5.2 DEX 协议适配器

```javascript
// DEX 协议适配器接口
interface DexProtocolAdapter {
  protocolName: string;

  // 池子发现
  discoverPools(fromBlock: number, toBlock: number): Promise<Pool[]>;

  // 事件解析
  parseSwapEvent(log: Log): SwapEvent;
  parseSyncEvent(log: Log): SyncEvent;

  // 价格计算
  calculatePrice(poolState: PoolState): number;

  // 获取池子状态
  getPoolState(poolAddress: string): Promise<PoolState>;
}

// Uniswap V2 适配器
class UniswapV2Adapter implements DexProtocolAdapter {
  protocolName = 'UniswapV2';

  async discoverPools(fromBlock, toBlock) {
    // 监听 PairCreated 事件
    const logs = await this.provider.getLogs({
      address: this.factoryAddress,
      topics: [this.PAIR_CREATED_TOPIC],
      fromBlock,
      toBlock
    });

    return logs.map(log => this.parsePairCreatedEvent(log));
  }

  parseSwapEvent(log) {
    const decoded = this.interface.parseLog(log);
    return {
      sender: decoded.args.sender,
      amount0In: decoded.args.amount0In.toString(),
      amount1In: decoded.args.amount1In.toString(),
      amount0Out: decoded.args.amount0Out.toString(),
      amount1Out: decoded.args.amount1Out.toString(),
      to: decoded.args.to
    };
  }

  calculatePrice(poolState) {
    return Number(poolState.reserve1) / Number(poolState.reserve0);
  }
}

// Uniswap V3 适配器
class UniswapV3Adapter implements DexProtocolAdapter {
  protocolName = 'UniswapV3';

  parseSwapEvent(log) {
    const decoded = this.interface.parseLog(log);
    return {
      sender: decoded.args.sender,
      recipient: decoded.args.recipient,
      amount0: decoded.args.amount0.toString(),
      amount1: decoded.args.amount1.toString(),
      sqrtPriceX96: decoded.args.sqrtPriceX96.toString(),
      liquidity: decoded.args.liquidity.toString(),
      tick: decoded.args.tick
    };
  }

  calculatePrice(poolState) {
    const sqrtPriceX96 = BigInt(poolState.sqrtPriceX96);
    const Q96 = BigInt(2) ** BigInt(96);
    const price = Number((sqrtPriceX96 * sqrtPriceX96) / (Q96 * Q96));
    return price;
  }
}

// Curve 适配器
class CurveAdapter implements DexProtocolAdapter {
  protocolName = 'Curve';

  // Curve 的事件和计算逻辑不同
  parseSwapEvent(log) {
    // TokenExchange / TokenExchangeUnderlying 事件
    const decoded = this.interface.parseLog(log);
    return {
      buyer: decoded.args.buyer,
      soldId: decoded.args.sold_id.toNumber(),
      tokensSold: decoded.args.tokens_sold.toString(),
      boughtId: decoded.args.bought_id.toNumber(),
      tokensBought: decoded.args.tokens_bought.toString()
    };
  }

  async calculatePrice(poolState) {
    // Curve 需要调用合约的 get_dy 方法
    const dy = await this.pool.get_dy(0, 1, ethers.utils.parseUnits('1', 18));
    return Number(ethers.utils.formatUnits(dy, 18));
  }
}
```

---

## 6. 高可用与容错设计

### 6.1 架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          高可用架构                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                       负载均衡器                                  │   │
│   │                       (HAProxy)                                  │   │
│   └─────────────────────────────┬───────────────────────────────────┘   │
│                                 │                                       │
│           ┌─────────────────────┼─────────────────────┐                 │
│           ↓                     ↓                     ↓                 │
│   ┌───────────────┐     ┌───────────────┐     ┌───────────────┐        │
│   │  索引器实例1   │     │  索引器实例2   │     │  索引器实例3   │        │
│   │  (主-ETH)     │     │  (主-BSC)     │     │  (主-ARB)     │        │
│   │  (备-BSC)     │     │  (备-ARB)     │     │  (备-ETH)     │        │
│   └───────┬───────┘     └───────┬───────┘     └───────┬───────┘        │
│           │                     │                     │                 │
│           └─────────────────────┼─────────────────────┘                 │
│                                 ↓                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                     Kafka 集群（3节点）                           │   │
│   │  ┌─────────┐       ┌─────────┐       ┌─────────┐                │   │
│   │  │ Broker1 │ ←───→ │ Broker2 │ ←───→ │ Broker3 │                │   │
│   │  └─────────┘       └─────────┘       └─────────┘                │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                 ↓                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                   PostgreSQL 主从集群                            │   │
│   │  ┌─────────┐       ┌─────────┐       ┌─────────┐                │   │
│   │  │ Primary │ ────→ │ Replica1│       │ Replica2│                │   │
│   │  │ (写)    │       │ (读)    │       │ (读)    │                │   │
│   │  └─────────┘       └─────────┘       └─────────┘                │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.2 故障处理策略

```javascript
// 故障处理管理器
class FaultToleranceManager {

  // RPC 节点故障转移
  async rpcFailover(chainId, error) {
    const chain = this.chains.get(chainId);

    // 标记当前节点为不可用
    chain.rpcNodes[chain.currentRpcIndex].status = 'unhealthy';
    chain.rpcNodes[chain.currentRpcIndex].lastError = error;
    chain.rpcNodes[chain.currentRpcIndex].failedAt = Date.now();

    // 切换到下一个健康节点
    const healthyNodes = chain.rpcNodes.filter(n => n.status === 'healthy');
    if (healthyNodes.length === 0) {
      // 所有节点都不可用，触发告警
      await this.alertService.critical(`Chain ${chainId} all RPC nodes down`);
      return null;
    }

    chain.currentRpcIndex = chain.rpcNodes.indexOf(healthyNodes[0]);
    return healthyNodes[0];
  }

  // 区块重组处理
  async handleReorg(chainId, reorgDepth) {
    console.log(`Detected reorg on chain ${chainId}, depth: ${reorgDepth}`);

    // 1. 标记受影响的数据
    const affectedBlocks = await this.db.query(`
      UPDATE swaps
      SET status = 'pending_reorg'
      WHERE chain_id = $1
        AND block_number >= (SELECT last_indexed_block - $2 FROM indexer_progress WHERE chain_id = $1)
      RETURNING block_number
    `, [chainId, reorgDepth]);

    // 2. 回滚索引进度
    await this.db.query(`
      UPDATE indexer_progress
      SET last_indexed_block = last_indexed_block - $2
      WHERE chain_id = $1
    `, [chainId, reorgDepth]);

    // 3. 重新索引受影响的区块
    await this.reindexBlocks(chainId, affectedBlocks);

    // 4. 清理无效数据
    await this.db.query(`
      DELETE FROM swaps
      WHERE chain_id = $1 AND status = 'pending_reorg'
    `, [chainId]);
  }

  // 消息积压处理
  async handleBackpressure(topic, lag) {
    if (lag > 10000) {  // 积压超过 1 万条
      console.warn(`High lag detected on topic ${topic}: ${lag}`);

      // 1. 增加消费者实例
      await this.scaleConsumers(topic, Math.ceil(lag / 5000));

      // 2. 降低非关键数据的处理优先级
      await this.adjustPriority(topic, 'low');

      // 3. 触发告警
      await this.alertService.warning(`Kafka lag on ${topic}: ${lag}`);
    }
  }
}
```

### 6.3 数据一致性保证

```javascript
// 数据一致性检查器
class ConsistencyChecker {

  // 定期检查索引数据与链上数据是否一致
  async verifyConsistency(chainId, sampleSize = 100) {
    const results = {
      checked: 0,
      passed: 0,
      failed: [],
      timestamp: Date.now()
    };

    // 随机抽取最近的交易进行验证
    const swaps = await this.db.query(`
      SELECT * FROM swaps
      WHERE chain_id = $1
      ORDER BY RANDOM()
      LIMIT $2
    `, [chainId, sampleSize]);

    for (const swap of swaps.rows) {
      results.checked++;

      // 从链上获取原始交易数据
      const receipt = await this.provider.getTransactionReceipt(swap.transaction_hash);

      // 找到对应的日志
      const log = receipt.logs.find(l => l.logIndex === swap.log_index);

      if (!log) {
        results.failed.push({
          txHash: swap.transaction_hash,
          reason: 'Log not found'
        });
        continue;
      }

      // 解码并比较
      const decoded = this.decoder.decode(log);
      if (this.compareSwapData(swap, decoded)) {
        results.passed++;
      } else {
        results.failed.push({
          txHash: swap.transaction_hash,
          reason: 'Data mismatch',
          indexed: swap,
          onchain: decoded
        });
      }
    }

    // 一致性低于阈值则告警
    const consistency = results.passed / results.checked;
    if (consistency < 0.99) {
      await this.alertService.critical(
        `Low consistency on chain ${chainId}: ${(consistency * 100).toFixed(2)}%`
      );
    }

    return results;
  }
}
```

---

## 7. 监控与运维

### 7.1 关键指标

```yaml
# Prometheus 监控指标

# 索引进度指标
indexer_latest_block:
  type: gauge
  labels: [chain_id]
  description: "最新索引的区块号"

indexer_chain_head_block:
  type: gauge
  labels: [chain_id]
  description: "链上最新区块号"

indexer_block_lag:
  type: gauge
  labels: [chain_id]
  description: "索引延迟（区块数）"

# 事件处理指标
indexer_events_processed_total:
  type: counter
  labels: [chain_id, event_type]
  description: "处理的事件总数"

indexer_events_processing_duration_seconds:
  type: histogram
  labels: [chain_id, event_type]
  description: "事件处理耗时"

# RPC 健康指标
indexer_rpc_requests_total:
  type: counter
  labels: [chain_id, method, status]
  description: "RPC 请求总数"

indexer_rpc_latency_seconds:
  type: histogram
  labels: [chain_id, method]
  description: "RPC 请求延迟"

# 数据质量指标
indexer_consistency_ratio:
  type: gauge
  labels: [chain_id]
  description: "数据一致性比率"

indexer_reorg_count:
  type: counter
  labels: [chain_id]
  description: "区块重组次数"
```

### 7.2 告警规则

```yaml
# Alertmanager 告警规则

groups:
  - name: indexer_alerts
    rules:
      # 索引延迟告警
      - alert: IndexerHighLag
        expr: indexer_block_lag > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "索引器延迟过高"
          description: "链 {{ $labels.chain_id }} 索引延迟 {{ $value }} 个区块"

      # 索引停止告警
      - alert: IndexerStopped
        expr: increase(indexer_latest_block[5m]) == 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "索引器停止工作"
          description: "链 {{ $labels.chain_id }} 索引器 10 分钟内没有新区块"

      # RPC 节点不可用
      - alert: RPCNodeDown
        expr: indexer_rpc_health == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "RPC 节点不可用"
          description: "链 {{ $labels.chain_id }} RPC 节点 {{ $labels.endpoint }} 不可用"

      # 数据一致性告警
      - alert: LowConsistency
        expr: indexer_consistency_ratio < 0.99
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "数据一致性过低"
          description: "链 {{ $labels.chain_id }} 数据一致性 {{ $value | humanizePercentage }}"
```

### 7.3 Grafana 仪表板

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     区块链索引器监控仪表板                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────┐│
│  │ 索引延迟（区块数）     │  │ 事件处理速率         │  │ RPC 可用率     ││
│  │                      │  │                      │  │                ││
│  │  ETH: 2 ✓           │  │  12,345 events/s    │  │  99.9% ✓       ││
│  │  BSC: 5 ✓           │  │  ████████████       │  │  ████████████  ││
│  │  ARB: 1 ✓           │  │                      │  │                ││
│  │  POLY: 3 ✓          │  │                      │  │                ││
│  └──────────────────────┘  └──────────────────────┘  └────────────────┘│
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                     索引进度趋势图                                    ││
│  │  区块号 ▲                                                           ││
│  │        │    ╱────────────────── 链上最新                            ││
│  │        │   ╱                                                        ││
│  │        │  ╱─────────────────── 已索引                              ││
│  │        │ ╱                                                          ││
│  │        └──────────────────────────────────────────────────────▶ 时间││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                         │
│  ┌──────────────────────────────┐  ┌──────────────────────────────────┐│
│  │ 各链事件分布                  │  │ 处理延迟分布                      ││
│  │                              │  │                                  ││
│  │  ETH ████████████ 45%       │  │  p50: 12ms                       ││
│  │  BSC ████████ 30%           │  │  p90: 45ms                       ││
│  │  ARB ████ 15%               │  │  p99: 120ms                      ││
│  │  其他 ██ 10%                │  │                                  ││
│  └──────────────────────────────┘  └──────────────────────────────────┘│
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 8. API 设计

### 8.1 REST API

```yaml
# 代币 API
GET /api/v1/tokens
  params:
    chain_id: integer (required)
    limit: integer (default: 100)
    offset: integer (default: 0)
    search: string (symbol 或 name 模糊搜索)
  response:
    tokens: Token[]
    total: integer

GET /api/v1/tokens/{chain_id}/{address}
  response:
    token: Token
    price_usd: number
    volume_24h: number
    market_cap: number

# 价格 API
GET /api/v1/prices/{chain_id}/{token_address}
  response:
    price_usd: number
    price_change_24h: number
    updated_at: timestamp

GET /api/v1/prices/{chain_id}/{token_address}/history
  params:
    interval: string (1m, 5m, 1h, 1d)
    from: timestamp
    to: timestamp
  response:
    ohlcv: OHLCV[]

# 流动性池 API
GET /api/v1/pools
  params:
    chain_id: integer
    protocol: string
    token0: string
    token1: string
  response:
    pools: Pool[]

GET /api/v1/pools/{chain_id}/{address}
  response:
    pool: Pool
    reserves: Reserves
    tvl_usd: number
    volume_24h: number
    apr: number

# 交易历史 API
GET /api/v1/swaps
  params:
    chain_id: integer
    pool_address: string
    user_address: string
    from_time: timestamp
    to_time: timestamp
    limit: integer
  response:
    swaps: Swap[]
    total: integer
```

### 8.2 WebSocket API

```javascript
// WebSocket 订阅接口

// 订阅价格更新
{
  "action": "subscribe",
  "channel": "prices",
  "params": {
    "chain_id": 1,
    "tokens": ["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"]  // WETH
  }
}

// 价格推送
{
  "channel": "prices",
  "data": {
    "chain_id": 1,
    "token": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "price_usd": 2251.23,
    "timestamp": 1703145000
  }
}

// 订阅池子更新
{
  "action": "subscribe",
  "channel": "pools",
  "params": {
    "chain_id": 1,
    "pools": ["0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"]
  }
}

// 池子状态推送
{
  "channel": "pools",
  "data": {
    "chain_id": 1,
    "pool": "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640",
    "reserve0": "10001234567",
    "reserve1": "4443210987",
    "price": 2251.45,
    "tvl_usd": 22500000,
    "timestamp": 1703145000
  }
}

// 订阅新交易
{
  "action": "subscribe",
  "channel": "swaps",
  "params": {
    "chain_id": 1,
    "pools": ["0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"]
  }
}
```

---

## 9. 性能优化

### 9.1 性能目标

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 索引延迟 | < 3 个区块 | 正常情况下追上链头 |
| 事件处理吞吐 | > 10,000 events/s | 单链峰值处理能力 |
| 价格查询延迟 | < 10ms (p99) | 热点数据走缓存 |
| 历史查询延迟 | < 100ms (p99) | 走 TimescaleDB |
| WebSocket 推送延迟 | < 100ms | 从事件产生到客户端收到 |

### 9.2 优化策略

```javascript
// 1. 批量处理
class BatchProcessor {
  constructor(batchSize = 100, flushInterval = 100) {
    this.batch = [];
    this.batchSize = batchSize;

    // 定时刷新
    setInterval(() => this.flush(), flushInterval);
  }

  async add(item) {
    this.batch.push(item);
    if (this.batch.length >= this.batchSize) {
      await this.flush();
    }
  }

  async flush() {
    if (this.batch.length === 0) return;

    const items = this.batch;
    this.batch = [];

    // 批量写入数据库
    await this.db.query(`
      INSERT INTO swaps (chain_id, pool_id, transaction_hash, ...)
      VALUES ${items.map((_, i) => `($${i*5+1}, $${i*5+2}, ...)`).join(',')}
    `, items.flatMap(i => [i.chainId, i.poolId, i.txHash, ...]));
  }
}

// 2. 并行处理
class ParallelProcessor {
  constructor(concurrency = 10) {
    this.semaphore = new Semaphore(concurrency);
  }

  async processBlocks(blocks) {
    const promises = blocks.map(block =>
      this.semaphore.acquire().then(async () => {
        try {
          await this.processBlock(block);
        } finally {
          this.semaphore.release();
        }
      })
    );

    await Promise.all(promises);
  }
}

// 3. 预计算
class PrecomputeService {
  // 预计算常用聚合数据
  async precompute() {
    // 24h 交易量
    await this.db.query(`
      REFRESH MATERIALIZED VIEW CONCURRENTLY pool_volume_24h;
    `);

    // 代币排行榜
    await this.redis.set('ranking:tokens:1:volume',
      await this.computeTokenRanking(1, 'volume'));
  }
}
```

---

## 10. 总结

### 10.1 核心设计要点

```
┌─────────────────────────────────────────────────────────────────┐
│                    区块链索引器设计要点                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 数据采集层                                                   │
│     ├── WebSocket 实时监听 + RPC 轮询备份                        │
│     ├── 多 RPC 节点冗余，自动故障转移                            │
│     └── 支持历史数据回填，断点续传                               │
│                                                                 │
│  2. 数据处理层                                                   │
│     ├── ABI 解码器：原始日志 → 结构化数据                        │
│     ├── 价格计算器：支持多种 AMM 算法                            │
│     └── 流动性计算：TVL、交易量、APR                            │
│                                                                 │
│  3. 数据存储层                                                   │
│     ├── PostgreSQL：结构化业务数据                              │
│     ├── TimescaleDB：时序数据（价格历史、K线）                   │
│     └── Redis：实时缓存（三级缓存架构）                          │
│                                                                 │
│  4. 多链适配                                                     │
│     ├── 链抽象层：统一接口适配 EVM/Solana/Sui                    │
│     ├── DEX 协议适配器：Uniswap/Curve/Balancer                  │
│     └── 统一数据模型：跨链数据标准化                             │
│                                                                 │
│  5. 高可用设计                                                   │
│     ├── 主备实例：每条链多实例部署                               │
│     ├── 消息队列：Kafka 解耦 + 削峰                              │
│     ├── 区块重组处理：检测 + 回滚 + 重索引                       │
│     └── 数据一致性校验：定期抽样验证                             │
│                                                                 │
│  6. 性能优化                                                     │
│     ├── 批量处理：减少数据库往返                                 │
│     ├── 并行处理：多区块并发索引                                 │
│     ├── 预计算：物化视图 + 定时聚合                              │
│     └── 三级缓存：本地 → Redis → 数据库                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 技术栈推荐

| 组件 | 技术选型 | 理由 |
|------|----------|------|
| **后端语言** | Rust / Go | 高性能、低延迟 |
| **消息队列** | Apache Kafka | 高吞吐、持久化、有序 |
| **主数据库** | PostgreSQL | 成熟稳定、JSONB 支持 |
| **时序数据库** | TimescaleDB | PostgreSQL 扩展、自动分区 |
| **缓存** | Redis Cluster | 高性能、支持集群 |
| **流处理** | Apache Flink | 低延迟、精确一次语义 |
| **监控** | Prometheus + Grafana | 生态完善 |

### 10.3 扩展性考虑

```
新链接入流程：

1. 配置链信息
   └── chains 表添加记录（RPC、WebSocket、出块时间）

2. 实现链适配器（如果是新链类型）
   └── 继承 ChainAdapter 接口

3. 配置 DEX 协议
   └── dex_protocols 表添加记录
   └── 实现协议适配器（如需）

4. 部署索引器实例
   └── Kubernetes 部署新 Pod

5. 执行历史数据回填
   └── Backfiller 从创世区块开始

预计接入时间：< 1 周（EVM 链）/ < 2 周（非 EVM 链）
```
