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
- `build.ps1`：Windows 入口脚本（支持 Windows 原生与 WSL Linux 构建）
- `STEP.md`：中文详细步骤说明
- `test/`：HTTP 测试页面与本地静态服务脚本
- `.github/workflows/build-and-release.yml`：CI 与发布流程

## 环境要求

- Linux 推荐 Ubuntu 22.04，建议 32 核+ CPU、64GB+ 内存、250GB+ SSD
- Windows 需安装 Visual Studio Build Tools（或等价 VS 2022 组件）
- 需要可用的 `git`、`python`/`python3`、`depot_tools` 相关命令（`fetch`、`gclient`、`gn`、`autoninja`）

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
