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

## 参考链接

| 资源 | 地址 |
|------|------|
| 官方构建文档 | https://www.chromium.org/developers/how-tos/get-the-code/ |
| depot_tools 仓库 | https://chromium.googlesource.com/chromium/tools/depot_tools.git |
| Chromium 主仓库 | https://chromium.googlesource.com/chromium/src.git |
