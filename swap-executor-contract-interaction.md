# Swap Executor与智能合约交互详解

## 场景说明

用户小王要将 **10,000 USDT** 兑换成 **ETH**，系统判断这是一个复杂的聚合交易（需要通过3个DEX执行），因此需要使用自有合约。

让我们跟踪从用户点击"Swap"按钮到交易完成的**每一步数据变化**。

## 第一步：用户发起请求

### 1.1 前端收集的原始数据

```javascript
// 用户在界面上的输入
const userInput = {
  from: "USDT",
  to: "ETH",
  amount: "10000",  // 用户输入的是10000，不带精度
  slippage: "0.5%",
  wallet: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1"  // 小王的钱包地址
};
```

### 1.2 前端处理后的请求

```javascript
// 前端将用户输入转换为标准格式
const swapRequest = {
  // 用户信息
  user: {
    address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
    chainId: 1,  // Ethereum mainnet
    nonce: 127   // 用户的第127笔交易
  },

  // 交易参数
  swap: {
    fromToken: {
      symbol: "USDT",
      address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      decimals: 6,
      amount: "10000000000"  // 10000 * 10^6 (USDT是6位精度)
    },
    toToken: {
      symbol: "ETH",
      address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      decimals: 18
    },
    slippageTolerance: 50,  // 0.5%（基点单位，即万分之一）
    // 50 = 50/10,000 = 0.5%
    // 基点(Basis Point, bps)是金融行业标准单位，1基点 = 0.01%
    deadline: 1703145600     // Unix时间戳，10分钟后
  },

  // 时间戳
  timestamp: 1703145000
};
```

## 第二步：后端Quote服务计算路径

### 2.1 Quote服务返回的最优路径

```javascript
const quoteResponse = {
  // 报价ID（用于追踪）
  quoteId: "quote_20240110_abc123",

  // 预期输出
  expectedOutput: {
    amount: "4445667788990011223344",  // 约4.445 ETH（18位精度）
    amountUSD: 9978.50,
    priceImpact: 0.22  // 0.22%的价格影响
  },

  // 路径分割方案（需要通过3个DEX）
  routes: [
    {
      dex: "UniswapV3",
      protocol: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",  // Uniswap V3 Router
      percentage: 40,  // 40%通过Uniswap
      path: {
        tokens: ["USDT", "USDC", "ETH"],
        pools: [
          "0x3416cF6C708Da44DB2624D63ea0AAef7113527C6",  // USDT-USDC池
          "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"   // USDC-ETH池
        ],
        fees: [100, 500]  // Uniswap V3费率（百万分之一单位）
        // 100 = 100/1,000,000 = 0.01%
        // 500 = 500/1,000,000 = 0.05%
      },
      expectedOutput: "1778267115596004489337"  // 这条路径预期输出
    },
    {
      dex: "Curve",
      protocol: "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46",  // Curve Tricrypto2
      percentage: 35,  // 35%通过Curve
      path: {
        // Tricrypto2 池包含: USDT(0), WBTC(1), WETH(2)
        // 可以直接 USDT → WETH
        tokens: ["USDT", "ETH"],
        poolAddress: "0xD51a44d3FaE010294C616388b506AcdA1bfAAE46",
        tokenIndices: [0, 2]  // USDT是index 0, WETH是index 2
        // 注：3pool(0xbEbc...)只有DAI/USDC/USDT，不含ETH
        // 所以USDT→ETH要用Tricrypto2池
      },
      expectedOutput: "1556208444272759278670"
    },
    {
      dex: "Balancer",
      protocol: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",  // Balancer Vault
      percentage: 25,  // 25%通过Balancer
      poolId: "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
      expectedOutput: "1111192229121247455337"
    }
  ],

  // Gas估算
  gasEstimate: {
    units: 380000,  // 预计Gas用量
    price: 30,      // 30 Gwei
    totalETH: "0.0114",
    totalUSD: 25.65
  },

  // 执行模式判断
  executionMode: "AGGREGATED",  // 需要使用自有合约
  reason: "Multiple DEX splits required"
};
```

## 第三步：Swap Executor构建交易

### 3.1 判断执行模式并准备合约调用

```javascript
// SwapExecutor内部处理
class SwapExecutor {

  async prepareTransaction(quoteResponse, userRequest) {
    // Step 1: 确定目标合约
    const targetContract = this.selectContract(quoteResponse.executionMode);

    const contractSelection = {
      mode: "AGGREGATED",
      targetContract: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",  // OpenOcean Router合约
      methodName: "swap",
      requiresApproval: true
    };

    // Step 2: 检查授权
    const approvalCheck = await this.checkApproval(
      userRequest.user.address,
      userRequest.swap.fromToken.address,
      contractSelection.targetContract
    );

    const approvalStatus = {
      currentAllowance: "5000000000",  // 当前只授权了5000 USDT
      requiredAmount: "10000000000",   // 需要10000 USDT
      needsApproval: true,
      approvalData: {
        to: "0xdAC17F958D2ee523a2206206994597C13D831ec7",  // USDT合约
        data: "0x095ea7b30000000000000000000000006352a56caadc4f1e25cd6c75970fa768a3304e640000000000000000000000000000000000000000000000000000000002540be400",
        // approve(spender, amount) 其中spender是OpenOcean Router, amount是10000 USDT
        value: "0x0",
        gas: 46000
      }
    };

    return { contractSelection, approvalStatus };
  }
}
```

### 3.2 编码合约调用数据

```javascript
// 构建发送给OpenOcean Router的数据
const contractCallData = {
  // 合约地址
  to: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",  // OpenOcean Router

  // 编码后的函数调用
  data: buildSwapCalldata({
    // swap函数的参数
    caller: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",  // 用户地址
    desc: {
      srcToken: "0xdAC17F958D2ee523a2206206994597C13D831ec7",  // USDT
      dstToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",   // ETH
      srcAmount: "10000000000",  // 10000 USDT
      minReturnAmount: "4423589234567890123456",  // 考虑滑点后的最小输出
      recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1"
    },
    routes: [
      {
        // Uniswap V3路由数据
        target: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
        percentage: 4000,  // 40% = 4000/10000
        payload: "0x..." // Uniswap的multicall数据
      },
      {
        // Curve路由数据
        target: "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
        percentage: 3500,  // 35%
        payload: "0x..." // Curve的exchange数据
      },
      {
        // Balancer路由数据
        target: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        percentage: 2500,  // 25%
        payload: "0x..." // Balancer的swap数据
      }
    ]
  })
};

// 最终编码结果
const encodedData = "0x7c025200" +  // swap函数选择器
  // 函数参数的ABI编码
  "0000000000000000000000000742d35cc6634c0532925a3b844bc9e7595f0beb1" +  // caller
  "00000000000000000000000000000000000000000000000000000000000000a0" +  // desc偏移量
  "0000000000000000000000000000000000000000000000000000000000000200" +  // routes偏移量
  // ... 更多编码数据
  "000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7" +  // srcToken
  "000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" +  // dstToken
  "0000000000000000000000000000000000000000000000000000000002540be400" +  // srcAmount
  "0000000000000000000000000000000000000000000003b8e97d229a2d543c80" +  // minReturnAmount
  // ... 完整的编码数据会有2000+字符
```

## 第四步：用户签名交易

### 4.1 MetaMask显示的交易信息

```javascript
// 发送给MetaMask的交易对象
const transactionObject = {
  from: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
  to: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",  // OpenOcean Router
  data: encodedData,  // 上面编码的数据
  value: "0x0",  // 不发送ETH
  gas: "0x5cc60",  // 380000 in hex
  gasPrice: "0x6fc23ac00",  // 30 Gwei in hex
  nonce: "0x7f",  // 127 in hex
  chainId: "0x1"
};

// MetaMask解析后显示给用户
const metamaskDisplay = {
  "Transaction Type": "Contract Interaction",
  "Contract": "OpenOcean: Router (0x6352...4e64)",
  "Function": "swap",

  "Details": {
    "Sending": "10,000 USDT",
    "Receiving": "~4.445 ETH (estimated)",
    "Minimum Received": "4.423 ETH (after slippage)",
    "Route": "40% Uniswap + 35% Curve + 25% Balancer",
    "Max Slippage": "0.5%"
  },

  "Gas Fee": {
    "Gas Limit": "380,000",
    "Gas Price": "30 Gwei",
    "Max Fee": "0.0114 ETH ($25.65)"
  },

  "Total": "10,000 USDT + $25.65 gas"
};
```

### 4.2 用户签名后的数据

```javascript
// 签名后的原始交易
const signedTransaction = {
  raw: "0xf8aa7f8506fc23ac00835cc60946352a56caadc4f1e25cd6c75970fa768a3304e64880b844" +
       "7c025200" +  // 函数选择器
       "0000000000000000000000000742d35cc6634c0532925a3b844bc9e7595f0beb1" +
       // ... 省略中间数据
       "2aa06d5e97bb9b13cf2f0b1a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e" +  // r
       "2fa00e8f9a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e",   // s

  // 解析后的交易哈希
  hash: "0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d",

  // v, r, s 签名值
  v: "0x2a",
  r: "0x6d5e97bb9b13cf2f0b1a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e",
  s: "0x0e8f9a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e"
};
```

## 第五步：广播交易

### 5.1 发送到节点

```javascript
// 通过RPC发送交易
const broadcastRequest = {
  jsonrpc: "2.0",
  method: "eth_sendRawTransaction",
  params: [signedTransaction.raw],
  id: 1
};

// 节点响应
const broadcastResponse = {
  jsonrpc: "2.0",
  id: 1,
  result: "0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d"
  // 返回交易哈希
};
```

## 第六步：合约执行

### 6.1 OpenOcean Router合约内部执行

```solidity
// 合约接收到调用后的执行流程
contract OpenOceanRouter {

    function swap(
        address caller,
        SwapDescription desc,
        Route[] routes
    ) external {
        // 1. 验证调用者
        require(msg.sender == caller, "Invalid caller");

        // 2. 从用户转入USDT
        IERC20(desc.srcToken).transferFrom(
            caller,
            address(this),
            desc.srcAmount  // 10000000000
        );

        // 3. 分割执行
        uint256 totalOutput = 0;

        // 3.1 40%通过Uniswap (4000 USDT)
        uint256 uniswapInput = 10000000000 * 4000 / 10000;  // 4000000000
        IERC20(USDT).approve(UNISWAP_ROUTER, uniswapInput);
        uint256 uniswapOutput = IUniswapRouter(UNISWAP_ROUTER).exactInput(
            // Uniswap参数...
        );
        totalOutput += uniswapOutput;  // 1778267115596004489337

        // 3.2 35%通过Curve (3500 USDT)
        uint256 curveInput = 10000000000 * 3500 / 10000;  // 3500000000
        IERC20(USDT).approve(CURVE_POOL, curveInput);
        uint256 curveOutput = ICurvePool(CURVE_POOL).exchange(
            2, // USDT index
            0, // ETH index
            curveInput,
            0
        );
        totalOutput += curveOutput;  // 1556208444272759278670

        // 3.3 25%通过Balancer (2500 USDT)
        uint256 balancerInput = 10000000000 * 2500 / 10000;  // 2500000000
        // Balancer执行...
        totalOutput += balancerOutput;  // 1111192229121247455337

        // 4. 检查滑点
        require(
            totalOutput >= desc.minReturnAmount,  // 4445667788990011223344 >= 4423589234567890123456
            "Slippage check failed"
        );

        // 5. 转出ETH给用户
        payable(desc.recipient).transfer(totalOutput);

        // 6. 触发事件
        emit SwapExecuted(
            caller,
            desc.srcToken,
            desc.dstToken,
            desc.srcAmount,
            totalOutput
        );
    }
}
```

### 6.2 合约事件日志

```javascript
// 合约触发的事件
const emittedEvents = [
  {
    event: "SwapExecuted",
    logIndex: 145,
    transactionHash: "0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d",
    blockNumber: 18654321,
    address: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",  // OpenOcean Router
    data: {
      caller: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
      srcToken: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      dstToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      srcAmount: "10000000000",
      dstAmount: "4445667788990011223344"
    }
  },
  {
    event: "Transfer",  // USDT转移事件
    address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    data: {
      from: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
      to: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",
      value: "10000000000"
    }
  },
  {
    event: "Transfer",  // ETH转移事件（通过WETH）
    address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    data: {
      from: "0x6352a56caadC4F1E25CD6c75970Fa768A3304e64",
      to: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb1",
      value: "4445667788990011223344"
    }
  }
];
```

## 第七步：监控确认

### 7.1 交易状态追踪

```javascript
// Monitor服务持续查询交易状态
const transactionStatus = {
  // T+0秒：交易刚广播
  initial: {
    status: "pending",
    hash: "0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d",
    timestamp: 1703145010,
    gasPrice: 30000000000
  },

  // T+15秒：被打包进块
  mined: {
    status: "mined",
    blockNumber: 18654321,
    blockHash: "0x8f7d6e5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d",
    transactionIndex: 87,
    confirmations: 1,
    gasUsed: 352489,  // 实际使用的Gas
    effectiveGasPrice: 28000000000,  // 实际Gas价格
    timestamp: 1703145025
  },

  // T+180秒：完全确认
  confirmed: {
    status: "confirmed",
    confirmations: 12,
    timestamp: 1703145190,

    // 最终执行结果
    executionResult: {
      success: true,

      // 输入输出
      input: {
        token: "USDT",
        amount: "10000000000",
        amountInUSD: 10000
      },
      output: {
        token: "ETH",
        amount: "4445667788990011223344",
        amountInETH: 4.445667788990011,
        amountInUSD: 9990.25
      },

      // 费用汇总
      costs: {
        gasUsed: 352489,
        gasPrice: 28,  // Gwei
        gasCostETH: 0.009869692,
        gasCostUSD: 22.21,

        platformFee: 0,  // 这个例子中没收平台费
        totalCostUSD: 22.21
      },

      // 价格分析
      priceAnalysis: {
        expectedPrice: 2247.19,  // USDT/ETH
        executedPrice: 2249.71,  // 实际执行价格
        priceImpact: 0.11,      // 实际价格影响 0.11%
        slippage: -0.06         // 负滑点表示执行价格比预期更好
      },

      // 路径执行详情
      routeExecution: [
        {
          dex: "UniswapV3",
          inputAmount: "4000000000",
          outputAmount: "1778267115596004489337",
          gasUsed: 142000
        },
        {
          dex: "Curve",
          inputAmount: "3500000000",
          outputAmount: "1556208444272759278670",
          gasUsed: 125000
        },
        {
          dex: "Balancer",
          inputAmount: "2500000000",
          outputAmount: "1111192229121247455337",
          gasUsed: 85489
        }
      ]
    }
  }
};
```

### 7.2 返回给用户的最终结果

```javascript
// 发送给前端的执行结果
const finalResult = {
  success: true,
  transactionHash: "0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d",

  // 简洁的摘要信息
  summary: {
    sent: "10,000 USDT",
    received: "4.4457 ETH",
    rate: "2249.71 USDT/ETH",
    gasCost: "$22.21",
    totalTime: "3 minutes 10 seconds",
    savedAmount: "$12.50"  // 相比单一DEX节省的金额
  },

  // 详细信息（可展开查看）
  details: {
    blockNumber: 18654321,
    confirmations: 12,

    routes: [
      { dex: "Uniswap V3", percentage: "40%", output: "1.7783 ETH" },
      { dex: "Curve", percentage: "35%", output: "1.5562 ETH" },
      { dex: "Balancer", percentage: "25%", output: "1.1112 ETH" }
    ],

    gasDetails: {
      estimated: 380000,
      actual: 352489,
      saved: 27511,
      price: "28 Gwei"
    },

    priceImpact: {
      expected: "0.22%",
      actual: "0.11%",
      favorable: true
    }
  },

  // 区块链浏览器链接
  explorerUrl: "https://etherscan.io/tx/0x5d3c1f2e9a8b7c6d4e3f2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d"
};
```

## 数据流总结

### 完整的数据转换链

```
1. 用户输入（人类可读）
   "10000 USDT" → "ETH"
   ↓
2. 前端格式化（标准化）
   amount: "10000000000" (加精度)
   ↓
3. 后端计算（最优路径）
   routes: [40% Uni, 35% Curve, 25% Bal]
   ↓
4. 合约编码（ABI编码）
   0x7c025200... (2000+字符)
   ↓
5. 用户签名（加密）
   v, r, s 签名值
   ↓
6. 广播（RPC）
   eth_sendRawTransaction
   ↓
7. 合约执行（EVM）
   swap() 函数内部逻辑
   ↓
8. 事件触发（日志）
   SwapExecuted event
   ↓
9. 状态确认（监控）
   pending → mined → confirmed
   ↓
10. 结果返回（格式化）
    "You swapped 10,000 USDT for 4.4457 ETH"
```

### 关键数据大小

| 数据类型 | 大小 | 说明 |
|---------|------|------|
| 用户输入 | ~50 bytes | 简单的JSON |
| 标准请求 | ~500 bytes | 格式化的请求对象 |
| Quote响应 | ~2 KB | 包含所有路径信息 |
| 编码交易数据 | ~1 KB | ABI编码的函数调用 |
| 签名交易 | ~1.5 KB | 包含v,r,s的完整交易 |
| 事件日志 | ~800 bytes | 多个事件的总和 |
| 最终结果 | ~1 KB | 返回给用户的摘要 |

### 时间线

```
T+0s    用户点击Swap
T+0.5s  前端验证并格式化
T+1s    发送到后端Quote服务
T+1.5s  计算最优路径完成
T+2s    构建交易数据
T+2.5s  用户看到MetaMask弹窗
T+5s    用户确认签名（人工）
T+5.5s  广播到网络
T+15s   交易被打包进块
T+180s  获得12个确认
T+181s  显示成功消息
```

## 与直接调用的对比

### 如果是简单的单DEX交易（直接调用模式）

```javascript
// 直接调用Uniswap，不经过OpenOcean合约
const directSwap = {
  to: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",  // 直接调用Uniswap Router
  data: "0x...",  // Uniswap的exactInputSingle编码

  // 数据更简单，只有一跳
  // 不需要分割逻辑
  // Gas消耗更少（~150k vs 350k）
};
```

### 聚合模式的优势体现

1. **价格优势**：通过3个DEX获得更好的价格
2. **深度优势**：避免单一池子的大额滑点
3. **一次交易**：用户只需签名一次
4. **原子性**：要么全部成功，要么全部失败

这就是为什么复杂交易必须通过自有合约（OpenOcean Router）执行的原因。

---

## 附录：费率单位详解

### 为什么 `fees: [100, 500]` 是 0.01% 和 0.05%？

**Uniswap V3 使用百万分之一（1/1,000,000）作为费率单位：**

```javascript
// Uniswap V3 的四个标准费率档次
const UNISWAP_V3_FEE_TIERS = {
  100:   "0.01%",   // 100 / 1,000,000 = 0.0001 = 0.01%  （稳定币对）
  500:   "0.05%",   // 500 / 1,000,000 = 0.0005 = 0.05%  （稳定币对）
  3000:  "0.30%",   // 3000 / 1,000,000 = 0.003 = 0.30%  （主流币对）
  10000: "1.00%"    // 10000 / 1,000,000 = 0.01 = 1.00%  （长尾币对）
};

// 所以 fees: [100, 500] 表示：
// 第一跳 USDT → USDC：使用 0.01% 费率的池子
// 第二跳 USDC → ETH： 使用 0.05% 费率的池子
```

**为什么用百万分之一？**

1. **需要更高精度**：稳定币交易的利润极薄，需要 0.01% 这样的超低费率
2. **避免浮点数**：智能合约用整数运算，百万分之一可以精确表示各种费率
3. **协议设计选择**：这是 Uniswap V3 团队的设计决定

---

### 为什么 `slippageTolerance: 50` 是 0.5%？

**滑点使用基点（Basis Points, bps），即万分之一（1/10,000）：**

```javascript
// 基点换算
const BASIS_POINTS = {
  1:    "0.01%",   // 1 / 10,000 = 0.0001 = 0.01%
  10:   "0.10%",   // 10 / 10,000 = 0.001 = 0.10%
  50:   "0.50%",   // 50 / 10,000 = 0.005 = 0.50%  ← 常用设置
  100:  "1.00%",   // 100 / 10,000 = 0.01 = 1.00%
  500:  "5.00%"    // 500 / 10,000 = 0.05 = 5.00%
};

// slippageTolerance: 50 表示：
// 用户最多接受 0.5% 的价格偏差
```

**什么是基点（Basis Point）？**

- 金融行业的标准计量单位
- 1 基点 = 0.01% = 1/10,000
- 常用于表示利率、费率、收益率的微小变化
- 例如：央行加息 25 基点 = 加息 0.25%

---

### 两种单位的对比

| 对比项 | Uniswap V3 费率 | 滑点容忍度 |
|--------|----------------|-----------|
| **单位名称** | 百万分之一 | 基点（bps） |
| **除数** | 1,000,000 | 10,000 |
| **最小精度** | 0.0001% | 0.01% |
| **来源** | Uniswap 协议设计 | 传统金融惯例 |
| **使用场景** | DEX 交易费率 | 价格滑点、利率 |

---

### 换算公式

```javascript
// 从百分比转换为 Uniswap 费率
function percentToUniswapFee(percent) {
  return percent * 1_000_000 / 100;
}
// 0.01% → 0.01 * 1000000 / 100 = 100
// 0.05% → 0.05 * 1000000 / 100 = 500
// 0.30% → 0.30 * 1000000 / 100 = 3000

// 从百分比转换为基点
function percentToBasisPoints(percent) {
  return percent * 10_000 / 100;
}
// 0.5% → 0.5 * 10000 / 100 = 50
// 1.0% → 1.0 * 10000 / 100 = 100

// 同样表示 0.5%
// Uniswap 费率: 5000 (5000/1,000,000)
// 基点:         50   (50/10,000)
```

---

### 为什么基数不一样？

简单来说：**不同的协议/场景使用不同的单位标准**

```
Uniswap V3:  选择 /1,000,000 是因为需要更高精度（支持0.01%费率）
滑点:        选择 /10,000（基点）是因为这是金融行业的通用标准

这就像：
├── 厨房用克（g）计量调料 —— 需要精细
└── 超市用千克（kg）标价水果 —— 日常够用

两种单位都能表示同样的比例，只是精度和来源不同。
```