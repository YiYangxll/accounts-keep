# 数据格式说明

记账 App 的全部数据保存在**本机应用私有目录**下的两个文件中：

```
<应用文档目录>/accounts_keep/
  ledger.json          主数据文件（当前数据）
  ledger.json.bak      上一次写入前的备份
  ledger.json.corrupt-<时间戳>   读取失败时对损坏文件的留档
  exports/             导出结果存放目录
```

* Android 上 `<应用文档目录>` 等价于
  `/data/data/com.yiyangxll.accounts_keep/app_flutter`。
* 该目录属于应用私有空间，卸载应用会一并删除，**不会**自动同步到任何服务器。
* 应用不申请网络权限，也不申请外部存储权限。

---

## 1. ledger.json（权威格式）

### 1.1 顶层结构

```json
{
  "schemaVersion": 1,
  "data": {
    "accounts": [ ... ],
    "categories": [ ... ],
    "transactions": [ ... ],
    "preferences": { "themeMode": "system", "currencySymbol": "¥" }
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `schemaVersion` | int | 数据版本。当前为 `1`。读取到**更高**版本时会拒绝加载并提示，避免误读导致数据损坏 |
| `data.accounts` | array | 账户列表，见 1.2 |
| `data.categories` | array | 分类列表，见 1.3 |
| `data.transactions` | array | 流水列表，见 1.4 |
| `data.preferences` | object | 界面偏好，值均为字符串 |
| `data.preferences.themeMode` | string | `system` / `light` / `dark` |
| `data.preferences.currencySymbol` | string | 货币符号，默认 `¥` |

导出的完整备份在此之上额外包含 `exportedAtUtc`、`app`、`counts` 三个**只读**字段，
便于人工确认备份内容；导入时会忽略它们。

### 1.2 account（账户）

```json
{
  "id": "acc_cash",
  "name": "现金",
  "kind": "cash",
  "initialBalanceCents": 0,
  "iconName": "cash",
  "colorHex": "#FF9800",
  "sortOrder": 0,
  "archivedAt": null
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 唯一标识 |
| `name` | string | 是 | 账户名，不可重名 |
| `kind` | string | 是 | `cash` / `debitCard` / `alipay` / `wechat` / `creditCard` / `other` |
| `initialBalanceCents` | int | 否 | **期初余额，单位为分**。信用卡已有欠款时为负数 |
| `iconName` | string | 否 | 图标名，UI 层映射到具体图标 |
| `colorHex` | string | 否 | `#RRGGBB` |
| `sortOrder` | int | 否 | 排序权重，越小越靠前 |
| `archivedAt` | string\|null | 否 | ISO 8601 UTC 时间。非空表示已归档 |

**余额语义**

| 账户类型 | 余额公式 | 说明 |
|---|---|---|
| 资产类（现金/储蓄卡/支付宝/微信/其他） | 期初 + 收入 − 支出 + 转入 − 转出 − 手续费 | 正常为正 |
| 信用卡（`creditCard`） | 期初（负数表示欠款）+ 其他同上 | **负数表示欠款**，UI 显示为「待还款 ¥X」 |

> **净资产 = Σ 所有未归档账户余额**。该公式对信用卡无需特例：消费让余额更负，
> 还款（转账到信用卡）让余额回升。转账在两个账户间一增一减，因此不影响净资产。

### 1.3 category（分类）

```json
{
  "id": "cat_food",
  "name": "餐饮",
  "kind": "expense",
  "parentId": null,
  "iconName": "restaurant",
  "colorHex": "#FF7043",
  "sortOrder": 0,
  "archivedAt": null
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `kind` | string | 是 | `expense` 或 `income`。必须与所记流水的类型一致 |
| `parentId` | string\|null | 否 | 上级分类 id；MVP 界面暂未启用二级分类，结构已预留 |
| `archivedAt` | string\|null | 否 | 非空表示已归档：不再出现在选择列表，但历史流水仍可正常显示与统计 |

### 1.4 transaction（流水）

```json
{
  "id": "tx_9f1c...",
  "kind": "expense",
  "amountCents": 1234,
  "accountId": "acc_alipay",
  "toAccountId": null,
  "feeCents": 0,
  "categoryId": "cat_food",
  "occurredAtUtc": "2026-03-10T04:30:00.000Z",
  "utcOffsetMinutes": 480,
  "note": "午饭",
  "payee": "公司食堂",
  "tag": null,
  "splits": [],
  "createdAtUtc": "2026-03-10T04:31:02.000Z",
  "updatedAtUtc": "2026-03-10T04:31:02.000Z",
  "deletedAtUtc": null
}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `kind` | string | 是 | `expense` 支出 / `income` 收入 / `transfer` 转账 |
| `amountCents` | int | 是 | **金额，单位为分，恒为正整数**。方向由 `kind` 表达 |
| `accountId` | string | 是 | 转出账户；收入时为入账账户 |
| `toAccountId` | string\|null | 转账必填 | 转入账户，必须与 `accountId` 不同；非转账必须为 null |
| `feeCents` | int | 否 | 转账手续费（分，≥0），从 `accountId` 扣除 |
| `categoryId` | string\|null | 收支必填 | 转账必须为 null |
| `occurredAtUtc` | string | 是 | 发生时间的 UTC 瞬时（ISO 8601） |
| `utcOffsetMinutes` | int | 是 | **记账时**的本地时区偏移（分钟），如东八区为 `480` |
| `note` / `payee` / `tag` | string\|null | 否 | 备注 / 交易对象 / 标签 |
| `splits` | array | 否 | 分项明细，结构已预留，MVP 界面未启用 |
| `createdAtUtc` / `updatedAtUtc` | string\|null | 否 | 创建与最后修改时间 |
| `deletedAtUtc` | string\|null | 否 | 非空表示**软删除**，可通过「撤销」恢复 |

**为什么同时存 UTC 与偏移量？**
只存 UTC 时，用户在 UTC+8 记录的 3 月 1 日 00:30 换算成 UTC 是 2 月 28 日，
按 UTC 归属会错误地记到 2 月。存下记账时的偏移量后，可以还原「用户当时看到的墙上时间」，
使日期与月份归属永不漂移，即使设备时区或夏令时规则之后发生变化。

### 1.5 金额为什么用「分」

所有金额字段一律为整数分，运行时不做浮点运算，从根本上避免 `0.1 + 0.2 != 0.3`
这类误差在记账场景中累积成对不上账的问题。仅在输入解析与界面展示的边界做转换：

* 输入 `12.345` → 四舍五入为 `1234.5` 分 → 取整 `1235` 分，并提示已按分四舍五入。
* 展示（分）`123456` → `¥1,234.56`。

### 1.6 数据自愈规则

读取或导入时，以下记录会被**丢弃并产生告警**，而不是让界面崩溃或静默改数：

1. 重复 `id` 的流水（保留第一条）。
2. 不满足 1.4 不变量的流水（金额 ≤ 0、转账缺 `toAccountId`、自转、缺分类等）。
3. 引用了不存在账户或分类的流水。
4. 分类类型与流水类型不一致的流水。
5. 上级分类缺失的二级分类。

主文件读取失败时依次尝试：`.bak` 备份 → 把损坏文件改名留档 → 空账本并提示用户。
`schemaVersion` 高于当前支持版本时**不做任何自动处理**，直接提示用户升级应用。

---

## 2. CSV 流水表（交换格式）

CSV 只承载流水，用于在 Excel / 表格软件中查看与整理，**不是**权威备份格式
（缺少账户期初余额等元数据，无法完整还原）。

* 编码：UTF-8，带 BOM（便于 Excel 识别中文）。
* 换行：`CRLF`。
* 引号：含逗号、引号或换行的字段用双引号包裹，内部双引号转义为 `""`（RFC 4180）。
* 列顺序固定为 12 列：

| # | 列名 | 说明 |
|---|---|---|
| 1 | `日期` | `yyyy-MM-dd`，按记账时区还原 |
| 2 | `时间` | `HH:mm` |
| 3 | `类型` | `支出` / `收入` / `转账` |
| 4 | `金额(¥)` | 元，两位小数；符号由当前货币符号设置决定 |
| 5 | `分类` | 分类名；转账为空 |
| 6 | `账户` | 账户名 |
| 7 | `转入账户` | 仅转账有值 |
| 8 | `手续费(¥)` | 元，两位小数 |
| 9 | `交易对象` | `payee` |
| 10 | `备注` | `note` |
| 11 | `标签` | `tag` |
| 12 | `是否删除` | `是` / `否` |

示例：

```csv
日期,时间,类型,金额(¥),分类,账户,转入账户,手续费(¥),交易对象,备注,标签,是否删除
2026-03-10,12:30,支出,12.34,餐饮,支付宝,,0.00,公司食堂,午饭,,否
2026-03-12,09:00,转账,500.00,,现金,储蓄卡,0.50,,取现,,否
```

---

## 3. 导入行为

导入只能识别 JSON 备份（`schemaVersion` 必须存在）。

1. 解析文件 → 校验版本 → 执行 1.6 的自愈规则。
2. 展示差异预览：`流水 新增 N / 覆盖 M；账户 …；分类 …`。
3. 用户选择策略：

| 策略 | 行为 |
|---|---|
| **合并** | 保留现有数据，同 `id` 的记录以导入数据为准 |
| **覆盖** | 清空现有数据后写入备份内容 |

4. 写入成功后才替换内存态与磁盘文件；失败则完整回滚，磁盘保持原样。

## 4. 兼容性约定

* 任何破坏向后兼容的结构改动都必须递增 `schemaVersion`，并在 `LedgerData.fromJson`
  中补上对应迁移逻辑。
* 新增**可选**字段不递增版本；旧版本应用读到未知字段会忽略。
* 枚举值只增不改：新增账户或分类类型时，旧数据仍能被新版本正确读取。
