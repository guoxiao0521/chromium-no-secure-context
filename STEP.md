# 编译 Chromium 并移除安全上下文限制 — 步骤总览

## 目标
移除以下两个 API 必须在安全上下文（HTTPS）下才能运行的限制：
- `VideoDecoder`（WebCodecs API）
- `SharedArrayBuffer`

---

## Step 1：环境准备

- 安装 [depot_tools](https://chromium.googlesource.com/chromium/tools/depot_tools.git)（Chromium 专用构建工具链）
- 配置系统依赖（推荐 Ubuntu Linux，需 100GB+ 磁盘空间）
- 确保已安装 Python、Git 等基础工具

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PATH:/path/to/depot_tools"
```

---

## Step 2：获取源码

> ⚠️ 不要直接 `git clone` 主仓库，必须通过 `fetch` 拉取，否则会缺少大量依赖子模块。

**相关地址：**
- 官方文档：https://www.chromium.org/developers/how-tos/get-the-code/
- 主仓库：https://chromium.googlesource.com/chromium/src.git

```bash
mkdir chromium && cd chromium
fetch chromium      # 拉取完整源码（数十 GB，耗时较长）
gclient sync        # 同步所有依赖
```

---

## Step 3：定位并修改限制代码（核心步骤）

### SharedArrayBuffer
- 检查 `crossOriginIsolated` 校验逻辑
- 关键目录：
  - `third_party/blink/renderer/core/execution_context/`
  - `content/browser/`（COOP/COEP 策略相关）

### VideoDecoder（WebCodecs API）
- 找到 IDL 文件中的 `[SecureContext]` 属性并移除
- 移除对应的运行时安全上下文检查
- 关键目录：
  - `third_party/blink/renderer/modules/webcodecs/`

---

## Step 4：配置构建参数

```bash
gn gen out/Default
```

编辑 `out/Default/args.gn`，常用配置示例：

```
is_debug = false
target_cpu = "x64"
is_component_build = false
```

---

## Step 5：编译

```bash
autoninja -C out/Default chrome
```

> ⏱ 首次编译耗时极长（数小时），建议使用高性能多核机器。

---

## Step 6：测试验证

- 运行编译产物
- 用测试页面（`http://` 非安全上下文）验证以下 API 可正常使用：
  - `new VideoDecoder(...)`
  - `new SharedArrayBuffer(...)`

---

## 本地构建

统一使用 `build.sh`（bash），自动检测操作系统（Linux / Windows Git Bash）。

### Linux

```bash
./build.sh
```

### Windows（Git Bash / MSYS2）

```bash
bash ./build.sh
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CHROMIUM_VERSION` | `146.0.7680.152` | 目标 Chromium 版本 |
| `BUILD_DIR` | `~/chromium` | 源码和构建目录 |
| `OUT_DIR` | `out/Default` | 编译输出目录 |
| `TARGET_OS` | 自动检测 | 可强制指定 `win` 或 `linux` |
| `SKIP_SYSTEM_DEPS` | `0` | 设为 `1` 跳过系统依赖安装（Linux） |

---

## GitHub Actions 使用方式

仓库已提供工作流：`.github/workflows/build-and-release.yml`。

### 触发方式

- `pull_request` / `push`：只执行轻量校验（`bash -n` + `shellcheck`）
- `workflow_dispatch`：手动触发完整构建
- `push tag (v*)`：执行完整构建并自动发布到 GitHub Release

### 自托管 Runner 前置要求

- 标签包含：`self-hosted`、`linux`、`x64`
- 推荐配置：32 核+ CPU、64GB+ RAM、250GB+ SSD
- 建议保留稳定工作目录和缓存：
  - `~/chromium`
  - `~/depot_tools`
- Runner 预装常用依赖时，可在 workflow 中设置 `SKIP_SYSTEM_DEPS=1` 跳过 `apt-get`

### 发布示例（tag 触发）

```bash
git tag v146.0.7680.141-1
git push origin v146.0.7680.141-1
```

构建成功后会自动在对应 tag 的 Release 中上传 `chromium-patched-*.tar.gz`。

### 手动触发示例

在 GitHub 页面进入 `Actions -> Build and Release Chromium Patched -> Run workflow`，即可手动触发完整构建。

---

## 参考链接

| 资源 | 地址 |
|------|------|
| 官方构建文档 | https://www.chromium.org/developers/how-tos/get-the-code/ |
| depot_tools 仓库 | https://chromium.googlesource.com/chromium/tools/depot_tools.git |
| Chromium 主仓库 | https://chromium.googlesource.com/chromium/src.git |
