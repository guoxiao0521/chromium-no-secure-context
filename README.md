# chromium-no-secure-context

在 Chromium 源码基础上提供补丁与构建脚本，移除 SecureContext 限制，让以下能力可在 `http://` 页面使用：

- `VideoDecoder`（WebCodecs API）
- `SharedArrayBuffer`

## 项目目标

默认 Chromium 对部分 Web API 有安全上下文要求（HTTPS / crossOriginIsolated）。本项目通过自动化补丁与构建流程，产出可在 HTTP 场景验证与使用的 Chromium 构建产物。

## 补丁机制

1. 移除 `src/third_party/blink/renderer/modules/webcodecs/*.idl` 中的 `SecureContext` 声明。
2. 将多个 Blink 上下文实现中的 `CrossOriginIsolatedCapability()` 强制返回 `true`，覆盖 `SharedArrayBuffer` 的隔离要求。

## 仓库结构

- `build.sh`：跨平台 Bash 构建脚本（Linux / Windows Git Bash / MSYS2）
- `STEP.md`：中文详细步骤说明
- `test/`：HTTP 测试页面与本地静态服务脚本
- `.github/workflows/build-and-release.yml`：CI 与发布流程

## 环境要求

### 通用

- 磁盘空间：至少 150GB（源码 ~30GB + 编译产物 ~100GB）
- 内存：建议 32GB+；16GB 可用但需限制并行数（`-j 4`），否则编译时可能 OOM
- CPU：建议 8 核+，核心数直接影响编译速度

### Linux

- 推荐 Ubuntu 22.04
- 系统依赖由脚本自动安装（`apt-get`），或设置 `SKIP_SYSTEM_DEPS=1` 跳过

### Windows

需要手动安装以下依赖：

1. **Git for Windows**（提供 Git Bash）
   ```powershell
   winget install Git.Git
   ```

2. **Python 3**（3.8+，注意不能是 Windows Store 的 stub 版本）
   ```powershell
   winget install Python.Python.3.12
   ```
   安装后确认 `python --version` 能正常输出版本号。

3. **Visual Studio 2022 Build Tools**
   ```powershell
   winget install Microsoft.VisualStudio.2022.BuildTools
   ```
   安装后打开 **Visual Studio Installer**，修改 Build Tools 2022，勾选：
   - **"使用 C++ 的桌面开发"** 工作负载（含推荐组件）
   - 单个组件中勾选 **C++ ATL v143 生成工具 (x86 和 x64)**

4. **Windows 10/11 SDK**（含调试工具）
   ```powershell
   winget install Microsoft.WindowsSDK.10.0.26100 --override "/features OptionId.WindowsDesktopDebuggers /ceip off /q" --force
   ```

5. **Node.js**（仅运行测试页面时需要）
   ```powershell
   winget install OpenJS.NodeJS.LTS
   ```

> `depot_tools`（含 `fetch`、`gclient`、`gn`、`autoninja`）由 `build.sh` 自动安装，无需手动处理。

## 快速开始

### Linux

```bash
./build.sh
```

### Windows（Git Bash / MSYS2）

```bash
bash ./build.sh
```

## 可选环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CHROMIUM_VERSION` | `146.0.7680.152` | 目标 Chromium tag 版本 |
| `BUILD_DIR` | `~/chromium` | Chromium 工作目录 |
| `OUT_DIR` | `out/Default` | GN 输出目录 |
| `TARGET_OS` | 自动检测 | 可强制指定 `win` 或 `linux` |
| `SKIP_SYSTEM_DEPS` | `0` | Linux 下设为 `1` 可跳过系统依赖安装 |
| `USE_OFFICIAL_OPT` | `0` | 设为 `1` 启用 ThinLTO + PGO 官方级优化（需 32GB+ 内存） |

示例：

```bash
CHROMIUM_VERSION=146.0.7680.152 BUILD_DIR=$HOME/chromium OUT_DIR=out/Default ./build.sh
```

## 验证方式

构建完成后，在 HTTP 页面验证：

- `new VideoDecoder(...)` 可正常创建并工作
- `new SharedArrayBuffer(...)` 可正常创建

可以使用仓库内测试文件：

```bash
node test/server.js
```

然后在浏览器中打开：

- `http://localhost:8080/test-http-apis.html`

## CI 与发布

- `pull_request` / `push`：执行轻量校验（`bash -n` + `shellcheck`）
- `workflow_dispatch`：手动触发完整构建
- 推送 `v*` tag：触发完整构建并自动发布 Release

示例：

```bash
git tag v146.0.7680.152-1
git push origin v146.0.7680.152-1
```

## 相关文档

- Chromium 获取源码与构建说明：<https://www.chromium.org/developers/how-tos/get-the-code/>
- depot_tools：<https://chromium.googlesource.com/chromium/tools/depot_tools.git>
- Chromium 源码：<https://chromium.googlesource.com/chromium/src.git>
- 仓库内详细步骤：`STEP.md`
