# 面板改动记录：为管理面板加上插件额度支持

本文档记录**对 CPA 管理面板所做的全部代码改动**，包含可复现的基线、逐文件清单、设计取舍与未完成项。

- 面向部署者：看 [`README.md`](README.md)
- 面向要理解原理/背景的人：看 [`docs/原理与设计.md`](docs/原理与设计.md)

---

## 一、基线（已严格锁定）

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/router-for-me/Cli-Proxy-API-Management-Center` |
| 分支 / commit | `main` @ **`4530da271ba2e89810d4dccebc57f3091afa590a`** |
| commit 日期 | 2026-09-21T14:48:06Z |
| commit 首行 | `feat(quota-toolbar): implement search functionality and separate toolbar layout` |
| 对应发布 | **v1.24.2**（2026-09-22 发布，即由该源码构建） |
| 取得方式 | `codeload.github.com/.../tar.gz/refs/heads/main`，2026-09-25 下载，8,890,683 字节 |

上游源码包**未提交进本仓库**（8.9 MB），需要时由 [`scripts/build.sh`](scripts/build.sh) 按上面的 commit 拉取。

**基线校验方法**（两条独立证据，均已通过）：

```bash
# git blob sha1 与上游 API 的 sha 字段逐个对照
git hash-object src/features/quota/providers/index.ts
#   796915a7e9cc004d386dd4da80ce6a6cdd10647c  ← 与 contents API(sha) 一致
git hash-object src/features/authFiles/components/AuthFileQuotaSection.tsx
#   b346b578746a78065644097c21645d48d8d32ad9  ← 与 contents API(sha) 一致
```

**`src/` 整树指纹**（398 个文件，逐文件 blob sha1 拼接后取 sha256）：

```
c18803e2df1344ba6b73ee37b5db7fd03789ab54a93937825c1c6cbc060076d0
```

任何上游变动都会改变这个指纹。**补丁只在上述基线上保证干净套用**；换更新的面板版本可能需手工处理上下文冲突。

---

## 二、改动概览

```
23 个文件，+686 / −17 行（其中 5 个新文件）
```

**做了什么**：给面板的额度模块加了一个**通用**适配器（`plugin`），让它去接宿主的通用额度端点
（`GET /v0/management/quota/providers` 发现 + `POST /v0/management/quota/fetch` 取数），
而不是像上游那样给每个厂商手写一份。

**为什么必须改**：上游 7 个内置适配器是**借宿主的 `api-call` 代理直连厂商自己的 API**，
所以分派表 `QUOTA_ADAPTERS` 是闭合的静态表、`QuotaProviderType` 是封闭联合类型，
没有插件分支。宿主的通用端点面板里**一行消费者都没有**。

---

## 三、逐文件清单

### 新增文件（5）

| 文件 | 行数 | 作用 |
|---|---|---|
| `src/types/pluginQuota.ts` | 61 | 展示类型契约：`PluginQuotaProvider` / `Bucket` / `Group` / `Metric` / `Subscription` / `State` |
| `src/services/api/quota.ts` | 196 | `quotaApi.listProviders()` 与 `fetchForCredential(authIndex)`；含**宽容解析**（见下） |
| `src/stores/usePluginQuotaProvidersStore.ts` | 45 | 发现结果缓存；`load()` 幂等，失败同样标记 `loaded` 避免卡片反复重试 |
| `src/features/quota/providers/plugin/data.ts` | 44 | 适配器数据层：`PLUGIN_CONFIG`，取数统一走宿主端点 |
| `src/features/quota/providers/plugin/PluginQuotaBody.tsx` | 136 | 通用渲染体：套餐/档位 chip + summary + 每个窗口一条水位条与重置时间 |

### 修改文件（18）

| 文件 | 改动 |
|---|---|
| `src/types/index.ts` | 导出 `pluginQuota` |
| `src/services/api/index.ts` | 导出 `quota` |
| `src/stores/index.ts` | 导出 `usePluginQuotaProvidersStore` |
| `src/stores/useQuotaStore.ts` | 新增 `pluginQuota` 切片 + `setPluginQuota`；`clearQuotaCache` 的**两个分支**（按名失效、整体清空）都纳入 |
| `src/features/quota/providers/types.ts` | `QuotaProviderType` 加第 8 个成员 `'plugin'`；`QuotaStore` 契约加切片与 setter |
| `src/features/quota/providers/index.ts` | `QUOTA_ADAPTERS.plugin = { ...PLUGIN_CONFIG, Body: PluginQuotaBody }` |
| `src/features/quota/constants.ts` | `QUOTA_TAB_ORDER` 末尾加 `'plugin'` |
| `src/features/quota/logic.ts` | 归类逻辑：内置筛选表改为 `Exclude<…, 'plugin'>`，插件凭证按**运行时发现结果**归入 `plugin` |
| `src/features/quota/QuotaPage.tsx` | 订阅 `pluginQuota` 与发现结果、挂载时触发 `load()`、`quotaByType` 补 `plugin`、归类时传入 provider 集合 |
| `src/features/quota/resetSchedule.ts` | 新增 `plugin` 分支：从 `groups[].buckets[].resetTime`（RFC3339 字符串）收集重置时刻 |
| `src/features/authFiles/constants.ts` | 认证文件侧的 `QuotaProviderType` 也加 `'plugin'`（两处类型必须同步） |
| `src/features/authFiles/logic.ts` | `resolveAuthFileQuotaType` 增加第三参数 `pluginProviders`；**tab 过滤同时认原始 provider 与 `plugin`** |
| `src/features/authFiles/components/AuthFileQuotaSection.tsx` | store 选择器加 `plugin` 分支（否则 `assertNever` 会抛） |
| `src/features/authFiles/components/AuthFileCard.tsx` | 订阅发现结果、挂载时触发加载、把 provider 集合传给解析函数 |
| `src/i18n/locales/zh-CN.json` | 新增 `plugin_quota.*`（14 键）与 `auth_files.filter_plugin` |
| `src/i18n/locales/en.json` | 同上 |
| `src/i18n/locales/zh-TW.json` | 同上 |
| `src/i18n/locales/ru.json` | 同上 |

> 4 个语言包同步是面板仓库 `AGENTS.md` 的硬要求（缺一个就会回落到 key）。

---

## 四、设计取舍

**1. 用"一个通用适配器"而不是逐个厂商手写。**
上游那套必须知道每个厂商的 URL、请求头和响应格式；宿主的 `/quota/fetch` 已经把这件事变成
"给我 `auth_index`，provider 与插件我自己解析"。所以面板侧只需渲染通用的
`groups[].buckets[]` + `summary[]`。**一次投入，以后任何插件的额度都能显示。**

**2. 给封闭联合类型加第 8 个成员，而不是把类型开放成 `string`。**
加成员会让编译器把所有穷尽处理点全部报出来（实际报出 5 处），是**安全的破坏式改动**；
改成开放类型会丢失穷尽性检查，且要动更多既有代码。

**3. 发现走 `/quota/providers`，而不是在凭据上找标记。**
宿主**不逐凭证下发**任何"我支持额度"的字段——`quota_provider` 是**插件能力键**，
与 `auth_provider`、`model_provider` 平级（已从运行中的二进制确认）。所以只能运行时发现。

**4. provider 条目宽容解析。**
`GET /quota/providers` 的条目包装形状**未实证**（宿主是 `QuotaProviders(ctx)` 直出）。
解析器同时接受两种形态：`supported_providers` 字符串数组，或条目本身就是字符串；
另外兼容 `display_name`/`displayName`、`supports_reset`/`supportsReset`。

**5. 额度桶解析同样双向兼容。**
宿主结构体实现了 `UnmarshalJSON`，`remainingFraction`/`remaining_fraction`、
`resetTime`/`reset_time`、`display_name` 都认。面板侧照做，避免绑定单一写法。
**同时主动丢弃无效桶**（比例缺失或非有限数），与宿主的过滤规则一致。

**6. `filterFn` 刻意不做额度判定。**
它只排除停用凭证；"是否真的支持额度"由发现结果在 `resolveAuthFileQuotaType` / `classifyQuotaFiles`
里统一决定，避免两处判断逻辑漂移。

**7. `load()` 失败也标记 `loaded`。**
宿主没有插件额度时不值得每次卡片渲染都重试；代价是同一会话内不会自动恢复，刷新页面即重新发现。

**8. tab 过滤要同时认 `provider` 与 `quotaType`。**
面板的提供商 tab 取值是**原始 provider key**（如 `cline-pass`），不是 `plugin`。
只判断 `filter === 'plugin'` 会导致在那个 tab 下反而看不到额度。

---

## 五、未完成项与风险

| # | 事项 | 说明 |
|---|---|---|
| 1 | **缺回归测试** | 仓库要求测试放 `tests/*.test.ts`、用 `bun:test`。建议覆盖 `parsePluginQuotaProviders`（两种条目形态）与 `parsePluginQuotaPayload`（camel/snake、无效桶丢弃、summary 过滤、currency 校验） |
| 2 | 补丁仅对基线保证 | 见第一节；上游 `main` 已推进时需重新对齐 |
| 3 | 与上游实现的潜在冲突 | 若上游以别的方式（例如把 `QuotaProviderType` 开放成 `string` + 默认适配器）实现插件额度，本补丁应被替换而非叠加 |
| 4 | 未验证浏览器行为 | 未做浏览器交互测试（仓库也没有 DOM 测试环境）。本次只做了类型检查、生产构建、产物校验与服务端实机验证 |

---

## 六、提上游 PR 的待办

1. 补第 1 项的测试，并跑 `bun run verify`（= test → lint → build）。
2. PR 描述需包含：宿主契约依据（`plugin_quota.go` 的路由与字段）、
   改动动机（现有 7 个适配器为厂商专属，插件额度无消费者）、UI 截图。
3. 遵循 `AGENTS.md`：4 语言包已同步、复用 `apiClient`（未在组件里裸写请求）、
   2 空格缩进 / 单引号 / `@/` 别名、`Conventional Commits`。
4. 不要提交 `dist/`（生成物）。

---

## 七、验证记录（已实际执行）

| 验证 | 结果 |
|---|---|
| `npx tsc --noEmit` | exit 0（首次报出 5 处遗漏并已修） |
| `npm run build` | 成功，`dist/index.html` 2,814,138 字节（基线 2,804,661，+9 KB） |
| 产物含补丁标记 | `quota/providers` ×1、`plugin_quota` ×14 |
| 补丁可套用性 | `git apply --check -p1` → 0；套用后 403 个文件与补丁源码**逐字节一致** |
| 服务端实际返回 | `:1235/management.html` → 200、2,814,138 字节、md5 `c35690007ab39c1558526d406acc0c8f`、`plugin_quota` ×14 |
| 端到端 | 面板上 ClinePass 卡片出现「点击此处刷新额度」，取数正常 |

> 本仓库根目录的 `management.html` 是 **2,814,625 字节、md5 `7f7ca30eadfe5946eb074df00c7c2889`**：
> 在 2,814,138 字节的额度补丁产物之上，又含两处显示层改动（登录回调路由、提示文案，见
> [`docs/原理与设计.md`](docs/原理与设计.md) 第 6 节）。校验时 `plugin_quota` 出现次数仍为 **14**；
> 注意面板是压缩过的多行文件，要用 `grep -o … | wc -l` 数出现次数（`grep -c` 数行数，会得到 2）。
