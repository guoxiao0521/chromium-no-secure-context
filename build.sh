#!/bin/bash
set -e

# =====================================================
# Chromium 构建脚本 - 移除 SecureContext 限制
# 目标：让 VideoDecoder 和 SharedArrayBuffer 在 HTTP 下可用
# 推荐系统：Ubuntu 22.04
# 推荐配置：32核+ CPU，64GB+ RAM，250GB+ SSD
# =====================================================

CHROMIUM_VERSION="${CHROMIUM_VERSION:-146.0.7680.141}"
BUILD_DIR="${BUILD_DIR:-$HOME/chromium}"
OUT_DIR="${OUT_DIR:-out/Default}"
SKIP_SYSTEM_DEPS="${SKIP_SYSTEM_DEPS:-0}"

echo "===== [1/6] 安装系统依赖 ====="
if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
  echo ">> SKIP_SYSTEM_DEPS=1，跳过系统依赖安装"
else
  sudo apt-get update
  sudo apt-get install -y \
    git curl python3 python3-pip \
    lsb-release sudo \
    build-essential
fi

echo "===== [2/6] 安装 depot_tools ====="
if [ ! -d "$HOME/depot_tools" ]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$HOME/depot_tools"
fi
export PATH="$HOME/depot_tools:$PATH"
echo "export PATH=\"\$HOME/depot_tools:\$PATH\"" >> ~/.bashrc

echo "===== [3/6] 拉取 Chromium 源码 ====="
mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"

if [ ! -f ".gclient" ]; then
  fetch --nohooks --no-history chromium
fi

cd src

# 切换到指定版本
git fetch --tags
git checkout "refs/tags/$CHROMIUM_VERSION"
gclient sync --with_branch_heads --with_tags -D --force

# 安装构建依赖
./build/install-build-deps.sh --no-prompt

echo "===== [4/6] 打补丁 - 移除 SecureContext 限制 ====="

# --- 补丁 1: VideoDecoder IDL 移除 SecureContext ---
VIDEO_DECODER_IDL="third_party/blink/renderer/modules/webcodecs/video_decoder.idl"
echo ">> 修改 $VIDEO_DECODER_IDL"
sed -i '/SecureContext,/d' "$VIDEO_DECODER_IDL"
sed -i '/^  SecureContext$/d' "$VIDEO_DECODER_IDL"

# 同时处理其他 WebCodecs 相关 IDL（AudioDecoder 等也可能有）
for idl_file in third_party/blink/renderer/modules/webcodecs/*.idl; do
  sed -i '/SecureContext,/d' "$idl_file"
  sed -i '/  SecureContext$/d' "$idl_file"
done

echo ">> WebCodecs IDL 修改完成"
grep -n "SecureContext" third_party/blink/renderer/modules/webcodecs/*.idl || echo ">> 确认：IDL 中 SecureContext 已全部移除"

# --- 补丁 2: SharedArrayBuffer 移除 crossOriginIsolated 要求 ---
# 方法：强制让 CrossOriginIsolatedCapability() 返回 true
EXEC_CTX_CC="third_party/blink/renderer/core/execution_context/execution_context.cc"
echo ">> 修改 $EXEC_CTX_CC"

# 找到并注释掉 CrossOriginIsolatedCapability 的真实判断，改为始终返回 true
python3 - <<'PYEOF'
import re

filepath = "third_party/blink/renderer/core/execution_context/execution_context.cc"

with open(filepath, "r") as f:
    content = f.read()

# 将 CrossOriginIsolatedCapability 方法体改为始终返回 true
# 匹配形如: bool ExecutionContext::CrossOriginIsolatedCapability() const { ... }
pattern = r'(bool ExecutionContext::CrossOriginIsolatedCapability\(\) const \{)[^}]+(})'
replacement = r'\1\n  return true;  // PATCHED: removed cross-origin isolation requirement\n\2'

new_content, count = re.subn(pattern, replacement, content)

if count > 0:
    with open(filepath, "w") as f:
        f.write(new_content)
    print(f">> 成功修改 CrossOriginIsolatedCapability() -> 始终返回 true ({count} 处)")
else:
    print(">> 警告: 未找到 CrossOriginIsolatedCapability，尝试备用方案...")
    # 备用：搜索函数并打印上下文供手动确认
    idx = content.find("CrossOriginIsolatedCapability")
    if idx != -1:
        print(content[max(0,idx-100):idx+300])
    else:
        print(">> 未找到该函数，可能版本不同，请手动检查")
PYEOF

# --- 补丁 3: 同样处理 Worker 上下文 ---
for ctx_file in \
  "third_party/blink/renderer/core/workers/worker_global_scope.cc" \
  "third_party/blink/renderer/core/frame/local_dom_window.cc"; do
  if [ -f "$ctx_file" ]; then
    echo ">> 检查 $ctx_file"
    python3 - "$ctx_file" <<'PYEOF'
import sys, re

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

pattern = r'(bool \w+::CrossOriginIsolatedCapability\(\) const \{)[^}]+(})'
replacement = r'\1\n  return true;  // PATCHED\n\2'
new_content, count = re.subn(pattern, replacement, content)

if count > 0:
    with open(filepath, "w") as f:
        f.write(new_content)
    print(f">> 修改成功: {filepath} ({count} 处)")
else:
    print(f">> 跳过 (无匹配): {filepath}")
PYEOF
  fi
done

echo "===== [5/6] 配置并编译 ====="
mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/args.gn" <<'EOF'
is_debug = false
target_cpu = "x64"
is_component_build = false
symbol_level = 0
enable_nacl = false
blink_symbol_level = 0
v8_symbol_level = 0
EOF

gn gen "$OUT_DIR"

# 使用所有 CPU 核心编译
JOBS=$(nproc)
echo ">> 使用 $JOBS 个核心编译..."
autoninja -C "$OUT_DIR" chrome -j "$JOBS"

echo "===== [6/6] 编译完成 ====="
echo ">> 产物路径: $BUILD_DIR/src/$OUT_DIR/chrome"
ls -lh "$BUILD_DIR/src/$OUT_DIR/chrome"

# 打包产物（可选：上传到 GitHub Release）
ARTIFACT="chromium-patched-$CHROMIUM_VERSION.tar.gz"
echo ">> 打包产物..."
tar -czf "$HOME/$ARTIFACT" -C "$BUILD_DIR/src/$OUT_DIR" chrome chrome_sandbox \
  ./*.so* locales/ resources.pak chrome_100_percent.pak chrome_200_percent.pak \
  icudtl.dat snapshot_blob.bin v8_context_snapshot.bin 2>/dev/null || true

echo ""
echo "======================================"
echo "构建完成！"
echo "产物包：$HOME/$ARTIFACT"
echo "ARTIFACT_PATH=$HOME/$ARTIFACT"
echo ""
echo "验证方法："
echo "  ./chrome --no-sandbox http://your-test-page.html"
echo "  测试页面应可在 HTTP 下使用 VideoDecoder 和 SharedArrayBuffer"
echo "======================================"
