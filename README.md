# CPA-Panel-PluginQuota · 管理面板插件额度补丁

给 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（CPA）的**官方管理面板**加上**插件额度支持**：
打上这个补丁后，任何声明了 `quota_provider` 能力的 CPA 插件都能在面板上直接看到额度卡片。

![预期效果](预期效果.png)

已知配套插件：[CommandCodeBridge](https://github.com/StarzL1kerain/CommandCodeBridge)、
[ClinePassBridge](https://github.com/StarzL1kerain/ClinePassBridge)。

> **三者分工**：插件负责**取数**，宿主（CPA）负责**转发**，本补丁只负责让**面板显示**。
> 不打这个补丁，插件照常工作 —— 只是面板上不会出现额度卡片（也不会报错），
> 额度仍可用插件自己的 `GET /v0/management/<pluginID>/quota` 或插件控制台页面查看。

## 为什么必须打补丁

宿主（CPA）的插件额度能力是**完整体**：`quota_provider` 能力键、`GET /v0/management/quota/providers`、
`POST /v0/management/quota/fetch`、`POST /v0/management/quota/reset`、`/v0/management/plugins/:id/quota`
都已在二进制里实现。问题在**面板前端**：

- `src/features/quota/providers/index.ts` 的 `QUOTA_ADAPTERS` 是**闭合静态表**（7 个内置厂商），没有回退
- `QuotaProviderType` 是**封闭联合类型**，`AuthFileQuotaSection.tsx` 里一串硬编码 `if` + `assertNever`
- `src/features/authFiles/logic.ts` 用 `QUOTA_PROVIDER_TYPES` 白名单**一票否决**

也就是说宿主的通用额度端点在面板里**一个消费者都没有**。官方最新版 **v1.24.2（2026-09-22）**
实测同样如此 —— **更新面板解决不了**，只能自己补。

补丁的做法是加**一个通用适配器**去接宿主的通用端点，而不是逐个厂商手写：
发现走 `/quota/providers`，取数走 `/quota/fetch`，渲染通用的 `groups[].buckets[]` + `summary[]`。
**一次投入，以后任何插件的额度都能显示。**

## 适配哪种 CPA 安装方式

**这个补丁与安装方式无关**（它就是替换一个静态文件），但**文件放在哪由安装方式决定**。
实测确认的规则是：

> 面板文件 = **`<配置目录>/static/management.html`**

（宿主的面板下载/更新机制自己也往这个路径写，见下面"另一条路"。）

| 安装方式 | 配置目录 | 面板文件位置 |
|---|---|---|
| **Linux 一键安装脚本**（本仓库实测通过）| `~/.config/cliproxyapi/` | `~/.config/cliproxyapi/static/management.html` ✅ 实测 |
| Arch Linux (AUR) | `~/.cli-proxy-api/`（见官方文档）| `~/.cli-proxy-api/static/management.html`（按同一规则推出，未实测）|
| Docker | `/CLIProxyAPI/config.yaml` | **要自己挂载**：`-v /path/to/management.html:/CLIProxyAPI/static/management.html`（容器里自带的是原版）。官方文档另外要求把插件目录挂到 `/CLIProxyAPI/plugins` |
| macOS (Homebrew) | `brew --prefix` 下的 `etc/` | 同规则，未实测 |
| Windows | 启动时 `-config` 指向的那个文件所在目录 | 同规则，未实测 |
| 源码编译 | 你自己指定的配置目录 | 同规则 |

任何安装方式都能这样定位（先拿到配置路径，再看同级 `static/`）：

```bash
systemctl --user cat cliproxyapi.service | grep ExecStart        # Linux systemd 的启动命令
find / -name management.html -not -path '*/node_modules/*' 2>/dev/null   # 直接找已存在的面板文件
```

部署脚本默认按 `~/.config/cliproxyapi` 走，其它安装方式用环境变量指定：

```bash
CFG=/your/config/dir PORT=8317 bash scripts/deploy.sh
```

### 另一条路：让 CPA 自己从本仓库拉面板（有前提）

宿主内置面板下载/更新机制，靠这两个键：

```yaml
remote-management:
  panel-github-repository: "https://github.com/StarzL1kerain/CPA-Panel-PluginQuota"
  disable-auto-update-panel: false    # false = 允许宿主自己更新（这条路径会做摘要校验）
```

宿主会去查该仓库的**最新 Release**，下载其中名为 `management.html` 的资产 —— 本仓库的 Release 正好就是这个名字。

**但这条路有前提，已实测**：查 Release 走的是 **GitHub API**，未鉴权时**每个出口 IP 每小时只有 60 次**。
在某台服务器上实测时，宿主的出口 IP 被限流，日志是：

```
[updater.go:247] failed to fetch latest management release information, trying fallback page
  error=fetch release: unexpected status 403: API rate limit exceeded for ...
[updater.go:300] management asset downloaded from fallback URL without digest verification
```

也就是说它会**静默回退到官方面板**（下载回来的是原版，额度功能就没了，界面本身不报错）。
另外注意：`disable-auto-update-panel: true` 时，这条回退路径**不做摘要校验**。

结论：

- **宿主能稳定访问 GitHub API 时**，这条路最省事 —— 以后我们发新版，面板会自己跟着更新。
- **否则请用手动/脚本方式**（本文档的方式一、方式二）。
- 宿主的出口 IP 由配置里的**全局 `proxy-url`** 决定。如果那个代理的出口被 GitHub 限流，
  插件商店的 502 / `GitHub API rate limited` 与面板回退是**同一个原因**：换出口，或就用手动安装。

## 用法

### 方式一：直接用补丁版产物（最快，推荐）

本仓库已经带上构建好的 `management.html`（2,814,625 字节），**不需要 Node、不需要构建**：

```bash
CFG=~/.config/cliproxyapi
cp -a $CFG/static/management.html $CFG/static/management.html.bak-$(date +%Y%m%d-%H%M%S)
cp -a management.html $CFG/static/management.html
```

只想拿文件、不想克隆仓库的话，去 [Releases](https://github.com/StarzL1kerain/CPA-Panel-PluginQuota/releases/latest)
下载 `management.html` 即可（Release 里同时附了源码补丁）。

或者直接跑本仓库的脚本（自动备份 + 安装 + 校验标记）：

```bash
bash scripts/deploy.sh
```

CPA **每次请求都从磁盘读**面板（不是启动时缓存在内存），所以**不需要重启 CPA**。

### 方式二：从补丁自己构建

换面板版本、或想自己出包时用。构建脚本会拉取**锁定的上游基线**、套补丁、构建并校验：

```bash
bash scripts/build.sh            # 需要网络 + Node/npm，产物覆盖本目录的 management.html
```

手动等价步骤：

```bash
# 1) 取与下表一致的基线源码
curl -L -o panel.tar.gz \
  https://codeload.github.com/router-for-me/Cli-Proxy-API-Management-Center/tar.gz/4530da271ba2e89810d4dccebc57f3091afa590a
tar -xzf panel.tar.gz && cd Cli-Proxy-API-Management-Center-4530da271ba2e89810d4dccebc57f3091afa590a

# 2) 套用补丁（在含 src/ 的根目录执行，-p1 剥掉 a/ 或 b/ 前缀）
git apply -p1 < /path/to/panel-plugin-quota.patch
#    没有 git 时等价写法：patch -p1 < panel-plugin-quota.patch

# 3) 构建（产物是单个 HTML）
npm install && npm run build      # = tsc && vite build → dist/index.html

# 4) 复制为 CPA 的静态面板
cp -a dist/index.html ~/.config/cliproxyapi/static/management.html
```

> 面板对 Node 版本不敏感（构建用了 Vite + rolldown）；本补丁的产物是在 Node 20 上构建的。

## 两个必须注意的坑

### 1. 面板自动更新会覆盖补丁

确认 CPA 配置（`~/.config/cliproxyapi/config.yaml`）里：

```yaml
remote-management:
  disable-auto-update-panel: true
```

否则上游发布新面板时会把补丁覆盖掉，需要重新部署。

### 2. 浏览器启发式缓存（"部署成功但界面没变"）

CPA 返回面板时**只给 `Last-Modified`，没有 `Cache-Control`、也没有 `ETag`**：

```
HTTP/1.1 200 OK
Content-Length: 2814625
Last-Modified: Fri, 25 Sep 2026 11:40:11 GMT
（无 Cache-Control / ETag）
```

浏览器对没有显式新鲜度信息的资源会启用**启发式新鲜度**（约为"距今时间 × 10%"）。
旧面板如果是一个月前的，估算寿命就有约 3 天 —— 这期间浏览器**根本不回服务器问**，
于是"明明部署成功，打开还是旧界面"，连普通 F5 都可能无效。

- **用户侧**：`Ctrl+Shift+R` 硬刷新；无痕窗口；或访问 `.../management.html?v=2`
- **根治（推荐）**：在反代（如 nginx）给面板单独加 no-cache：

  ```nginx
  location = /management.html {
      proxy_pass http://127.0.0.1:1235;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      add_header Cache-Control "no-cache" always;
  }
  ```

  （改完 `nginx -t && nginx -s reload`）

## 验证补丁是否生效

```bash
curl -s -o /tmp/served.html -w "%{http_code} %{size_download}\n" http://127.0.0.1:1235/management.html
grep -o plugin_quota /tmp/served.html | wc -l     # 期望 14
```

> 要用 `grep -o … | wc -l` 数**出现次数**。面板是压缩过的文件（约 160 行），
> `grep -c` 数的是**行数**，只会得到 2，容易误判成"补丁没打上"。

生效后的表现：

- 凭据卡片底部出现 **「点击此处刷新额度」**（点一下取数并渲染窗口条）
- 配额管理页多出 **「插件」** 分组
- 识别 `five_hour` / `weekly` / `seven_day` / `monthly` 四种窗口 token，其余原样显示

## 排错

**装了补丁、也有插件，但卡片上没有「点击此处刷新额度」** —— 按顺序查：

1. **硬刷新浏览器**（见上面的坑 2），先用无痕窗口排除缓存。
2. **面板是否真的换了**：`grep -c plugin_quota` 是否为 14。
3. **provider 三处是否一致**（最隐蔽的失败模式，不报错就是没有按钮）：
   插件 `quota.describe` 返回的 `supported_providers`、凭证的 provider、宿主的
   `GET /v0/management/quota/providers` 必须是**同一个字符串**（例如 `cline-pass`）。
4. **宿主是否发现了插件能力**：直接看端点
   ```bash
   curl -s -H "Authorization: Bearer <管理密钥>" \
     http://127.0.0.1:1235/v0/management/quota/providers
   ```
   没有对应条目说明是插件侧的能力声明问题，不是面板补丁的问题。

## 回滚

```bash
mv ~/.config/cliproxyapi/static/management.html.bak-<时间戳> ~/.config/cliproxyapi/static/management.html
```

## 兼容性（上游基线已锁定）

补丁**只在下面这条基线上保证干净套用**：

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `router-for-me/Cli-Proxy-API-Management-Center` @ `main` |
| commit | `4530da271ba2e89810d4dccebc57f3091afa590a`（2026-09-21） |
| 对应发布 | v1.24.2（2026-09-22，由该源码构建） |
| `src/` 整树指纹 | sha256 `c18803e2df1344ba6b73ee37b5db7fd03789ab54a93937825c1c6cbc060076d0`（398 个文件）|

上游 `main` 已经推进时补丁可能上下文冲突，需要重新对齐（改动清单见 [`CHANGES.md`](CHANGES.md)）。

## 文件清单

| 文件 | 说明 |
|---|---|
| `management.html` | **补丁版产物**，2,814,625 字节，md5 `7f7ca30eadfe5946eb074df00c7c2889`，可直接部署。在额度补丁之上还含两处显示层改动（登录回调路由、提示文案），见 [`docs/原理与设计.md`](docs/原理与设计.md) 第 6 节 |
| `panel-plugin-quota.patch` | 相对基线的 unified diff，43,830 字节，23 段含 5 个新文件（UTF-8 + LF，前缀 `a/src/…`）|
| `CHANGES.md` | 逐文件改动记录：基线、改动清单、设计取舍、未完成项、上游 PR 待办、验证记录 |
| `docs/原理与设计.md` | 面板为什么没有插件分支、归类规则、provider 一致性要求 |
| `scripts/deploy.sh` | 备份 → 安装 → 校验 |
| `scripts/build.sh` | 取基线 → 套补丁 → 构建 → 校验 |
| `预期效果.png` | 打上补丁后的额度卡片 |

## 许可

本仓库的补丁与脚本：MIT。

`management.html` 是 [`router-for-me/Cli-Proxy-API-Management-Center`](https://github.com/router-for-me/Cli-Proxy-API-Management-Center)
（MIT，Copyright (c) 2026 Router-For.ME）打上本补丁后的**构建产物**，按上游 MIT 许可再分发，
完整许可文本见 [`LICENSE`](LICENSE)。
