#!/bin/bash
set -e

# =====================================================
# Chromium 构建脚本 - 移除 SecureContext 限制
# 目标：让 VideoDecoder 和 SharedArrayBuffer 在 HTTP 下可用
# 支持平台：Linux (native)、Windows (Git Bash / MSYS2)
# 推荐配置：32核+ CPU，64GB+ RAM，250GB+ SSD
# =====================================================

CHROMIUM_VERSION="${CHROMIUM_VERSION:-146.0.7680.152}"
BUILD_DIR="${BUILD_DIR:-$HOME/chromium}"
OUT_DIR="${OUT_DIR:-out/Default}"
SKIP_SYSTEM_DEPS="${SKIP_SYSTEM_DEPS:-0}"

# Detect OS
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    HOST_OS="win"
    ;;
  Linux)
    HOST_OS="linux"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

TARGET_OS="${TARGET_OS:-$HOST_OS}"

# Detect working python command (Windows Store stub returns exit 49)
PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" &>/dev/null && "$candidate" -c "pass" &>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "No working python found"
  exit 1
fi

step() {
  echo "===== $1 ====="
}

ensure_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "Missing command: $1"
    exit 1
  fi
}

with_retry() {
  local max_retries=4
  local delay=5
  for attempt in $(seq 1 "$max_retries"); do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -eq "$max_retries" ]; then
      echo "Command failed after $max_retries attempts: $*"
      return 1
    fi
    echo "Retry $attempt/$max_retries failed. Sleep ${delay}s..."
    sleep "$delay"
    delay=$((delay * 2))
  done
}

checkout_chromium_tag() {
  local version="$1"
  local resolved_version="$version"
  local resolved_commit=""

  # Try exact peeled tag
  resolved_commit=$(git ls-remote --tags origin "refs/tags/${version}^{}" 2>/dev/null | awk '{print $1; exit}')

  # Try exact tag
  if [ -z "$resolved_commit" ]; then
    resolved_commit=$(git ls-remote --tags origin "refs/tags/${version}" 2>/dev/null | awk '{print $1; exit}')
  fi

  # Fallback: find nearby tags
  if [ -z "$resolved_commit" ]; then
    local version_prefix="${version%.*}"
    local major_minor_prefix="${version_prefix%.*}"

    local nearby_output
    nearby_output=$(git ls-remote --tags origin "refs/tags/${version_prefix}.*" 2>/dev/null || true)
    if [ -z "$nearby_output" ]; then
      nearby_output=$(git ls-remote --tags origin "refs/tags/${major_minor_prefix}.*" 2>/dev/null || true)
    fi

    if [ -z "$nearby_output" ]; then
      echo "Tag checkout failed: $version (no nearby remote tags found)"
      exit 1
    fi

    # Parse tags: prefer peeled (^{}) commits, collect tag->sha mapping
    # Sort by version descending, pick the largest version <= requested
    local fallback_version fallback_commit
    fallback_version=$(echo "$nearby_output" \
      | grep -oP 'refs/tags/\K\d+\.\d+\.\d+\.\d+(?=\^\{\})?$' \
      | sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr \
      | while IFS= read -r tag; do
          if version_le "$tag" "$version"; then
            echo "$tag"
            break
          fi
        done)

    if [ -z "$fallback_version" ]; then
      # Just pick the latest available
      fallback_version=$(echo "$nearby_output" \
        | grep -oP 'refs/tags/\K\d+\.\d+\.\d+\.\d+(?=\^\{\})?$' \
        | sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr \
        | head -1)
    fi

    if [ -z "$fallback_version" ]; then
      echo "Tag checkout failed: $version (could not parse nearby tags)"
      exit 1
    fi

    # Get commit for fallback version (prefer peeled)
    fallback_commit=$(echo "$nearby_output" | grep "refs/tags/${fallback_version}\^{}" | awk '{print $1; exit}')
    if [ -z "$fallback_commit" ]; then
      fallback_commit=$(echo "$nearby_output" | grep "refs/tags/${fallback_version}$" | awk '{print $1; exit}')
    fi

    resolved_version="$fallback_version"
    resolved_commit="$fallback_commit"
    echo "Remote tag $version not found, fallback to $resolved_version"
  fi

  if [ -z "$resolved_commit" ]; then
    echo "Unable to resolve commit for tag: $version"
    exit 1
  fi

  with_retry git fetch origin "$resolved_commit" --depth 1 --no-tags --force
  git checkout --detach "$resolved_commit"
  git tag -f "$version" "$resolved_commit"
  if [ "$resolved_version" != "$version" ]; then
    git tag -f "$resolved_version" "$resolved_commit"
  fi
}

# Compare two dotted versions: return 0 if $1 <= $2
version_le() {
  local IFS=.
  local i a b
  read -ra a <<< "$1"
  read -ra b <<< "$2"
  for i in 0 1 2 3; do
    if (( ${a[$i]:-0} < ${b[$i]:-0} )); then return 0; fi
    if (( ${a[$i]:-0} > ${b[$i]:-0} )); then return 1; fi
  done
  return 0
}

# =====================================================
# Step 1: System dependencies
# =====================================================
step "Install system dependencies"
if [ "$HOST_OS" = "linux" ]; then
  if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
    echo ">> SKIP_SYSTEM_DEPS=1, skipping"
  else
    sudo apt-get update
    sudo apt-get install -y \
      git curl python3 python3-pip \
      lsb-release sudo \
      build-essential
  fi
else
  ensure_command git
  echo ">> Windows: skipping system deps install"
fi

# =====================================================
# Step 2: depot_tools
# =====================================================
step "Install depot_tools"
DEPOT_TOOLS_DIR="$HOME/depot_tools"
if [ ! -d "$DEPOT_TOOLS_DIR" ]; then
  with_retry git clone --depth 1 \
    https://chromium.googlesource.com/chromium/tools/depot_tools.git \
    "$DEPOT_TOOLS_DIR"
fi
export PATH="$DEPOT_TOOLS_DIR:$PATH"

if [ "$HOST_OS" = "win" ]; then
  export DEPOT_TOOLS_WIN_TOOLCHAIN=0
  # VS2022 BuildTools may be in Program Files (x86); help Chromium find it
  if [ -z "$vs2022_install" ]; then
    for vs_dir in \
      "C:/Program Files/Microsoft Visual Studio/2022/BuildTools" \
      "C:/Program Files/Microsoft Visual Studio/2022/Community" \
      "C:/Program Files/Microsoft Visual Studio/2022/Professional" \
      "C:/Program Files/Microsoft Visual Studio/2022/Enterprise" \
      "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools" \
      "C:/Program Files (x86)/Microsoft Visual Studio/2022/Community"; do
      if [ -f "$vs_dir/VC/Auxiliary/Build/vcvarsall.bat" ]; then
        export vs2022_install="$vs_dir"
        echo ">> Auto-detected VS2022: $vs_dir"
        break
      fi
    done
  fi
fi

# Configure git network defaults
git config --global http.version HTTP/1.1
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# =====================================================
# Step 3: Fetch Chromium source
# =====================================================
step "Fetch Chromium source"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -f ".gclient" ] && [ ! -d "src/.git" ]; then
  with_retry fetch --nohooks --no-history chromium
elif [ ! -f ".gclient" ]; then
  echo "Existing checkout detected without .gclient, running gclient config instead"
  with_retry gclient config --name src \
    https://chromium.googlesource.com/chromium/src.git --unmanaged
fi

# Patch .gclient to exclude unnecessary dependencies
if [ -f ".gclient" ] && ! grep -q "custom_deps" .gclient 2>/dev/null; then
  "$PYTHON" -c "
import re
with open('.gclient', 'r') as f:
    content = f.read()
custom_deps = '''\"custom_deps\": {
      \"src/third_party/android_rust_toolchain\": None,
      \"src/third_party/android_build_tools\": None,
      \"src/third_party/android_sdk\": None,
      \"src/third_party/catapult\": None,
      \"src/chrome/test/data\": None,
      \"src/third_party/hunspell_dictionaries\": None,
    },
    '''
content = content.replace('\"custom_deps\": {},', custom_deps + '\"custom_deps_keep\": {},')
if '\"custom_deps\"' not in content:
    content = re.sub(r'(\"custom_vars\"\s*:\s*\{\s*\},?)', custom_deps + r'\1', content)
with open('.gclient', 'w') as f:
    f.write(content)
print('>> .gclient patched to exclude unnecessary deps')
"
fi

# Checkout tag and sync
if [ -d "src/.git" ]; then
  cd src
  checkout_chromium_tag "$CHROMIUM_VERSION"
  with_retry gclient sync --with_branch_heads --with_tags -D --force --no-history --shallow
else
  echo "src directory is not a git repo yet, running gclient sync first"
  with_retry gclient sync --nohooks --no-history --force
  cd src
  checkout_chromium_tag "$CHROMIUM_VERSION"
  with_retry gclient sync --with_branch_heads --with_tags -D --force --no-history --shallow
fi

# Install build dependencies (Linux only)
if [ "$HOST_OS" = "linux" ]; then
  ./build/install-build-deps.sh --no-prompt
fi

# =====================================================
# Step 4: Apply patches
# =====================================================
step "Apply patches - remove SecureContext restrictions"

# Patch 1: Remove SecureContext from WebCodecs IDL files
for idl_file in third_party/blink/renderer/modules/webcodecs/*.idl; do
  if [ -f "$idl_file" ]; then
    sed -i 's/SecureContext,//' "$idl_file"
    sed -i '/^  SecureContext$/d' "$idl_file"
  fi
done
echo ">> WebCodecs IDL: SecureContext removed"
grep -n "SecureContext" third_party/blink/renderer/modules/webcodecs/*.idl || echo ">> Confirmed: no SecureContext left in IDL"

# Patch 2: Force CrossOriginIsolatedCapability() to return true
patch_cross_origin() {
  local filepath="$1"
  if [ ! -f "$filepath" ]; then
    echo ">> Skip (not found): $filepath"
    return
  fi
  echo ">> Patching $filepath"
  "$PYTHON" - "$filepath" <<'PYEOF'
import sys, re
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()
pattern = r'(bool \w+::CrossOriginIsolatedCapability\(\) const \{)[^}]+(})'
replacement = r'\1\n  return true;  // PATCHED: removed cross-origin isolation requirement\n\2'
new_content, count = re.subn(pattern, replacement, content)
if count > 0:
    with open(filepath, "w") as f:
        f.write(new_content)
    print(f">> Patched: {filepath} ({count} match)")
else:
    idx = content.find("CrossOriginIsolatedCapability")
    if idx != -1:
        print(f">> WARNING: found function but regex didn't match in {filepath}")
        print(content[max(0,idx-100):idx+300])
    else:
        print(f">> Skip (no CrossOriginIsolatedCapability): {filepath}")
PYEOF
}

# CrossOriginIsolatedCapability() is pure virtual in execution_context.h;
# patch all subclass implementations
patch_cross_origin "third_party/blink/renderer/core/frame/local_dom_window.cc"
patch_cross_origin "third_party/blink/renderer/core/workers/worker_global_scope.cc"
patch_cross_origin "third_party/blink/renderer/core/workers/shared_worker_global_scope.cc"
patch_cross_origin "third_party/blink/renderer/core/workers/worklet_global_scope.cc"
patch_cross_origin "third_party/blink/renderer/core/shadow_realm/shadow_realm_global_scope.cc"
patch_cross_origin "third_party/blink/renderer/modules/service_worker/service_worker_global_scope.cc"

# =====================================================
# Step 5: Configure and build
# =====================================================
step "Configure and build ($TARGET_OS)"
mkdir -p "$OUT_DIR"

if [ "$TARGET_OS" = "win" ]; then
  cat > "$OUT_DIR/args.gn" <<'EOF'
is_debug = false
target_os = "win"
target_cpu = "x64"
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
exclude_unwind_tables = true
enable_iterator_debugging = false
use_thin_lto = false
EOF
else
  cat > "$OUT_DIR/args.gn" <<'EOF'
is_debug = false
target_cpu = "x64"
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
exclude_unwind_tables = true
use_thin_lto = false
EOF
fi

gn gen "$OUT_DIR"

JOBS=$(nproc 2>/dev/null || echo 1)
echo ">> Building with $JOBS cores..."
autoninja -C "$OUT_DIR" chrome -j "$JOBS"

# =====================================================
# Step 6: Package artifact
# =====================================================
step "Package artifact"

if [ "$TARGET_OS" = "win" ]; then
  ARTIFACT_NAME="chromium-patched-win-${CHROMIUM_VERSION}.zip"
  ARTIFACT_PATH="$HOME/$ARTIFACT_NAME"
  rm -f "$ARTIFACT_PATH"
  # On Windows, use 7z or powershell for zip
  BUILD_OUTPUT="$BUILD_DIR/src/$OUT_DIR"
  if command -v 7z &>/dev/null; then
    7z a -tzip "$ARTIFACT_PATH" "$BUILD_OUTPUT/*"
  else
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path '$(cygpath -w "$BUILD_OUTPUT")\\*' -DestinationPath '$(cygpath -w "$ARTIFACT_PATH")' -CompressionLevel Fastest"
  fi
else
  ARTIFACT_NAME="chromium-patched-${CHROMIUM_VERSION}.tar.gz"
  ARTIFACT_PATH="$HOME/$ARTIFACT_NAME"
  tar -czf "$ARTIFACT_PATH" -C "$BUILD_DIR/src/$OUT_DIR" chrome chrome_sandbox \
    ./*.so* locales/ resources.pak chrome_100_percent.pak chrome_200_percent.pak \
    icudtl.dat snapshot_blob.bin v8_context_snapshot.bin 2>/dev/null || true
fi

echo ""
echo "======================================"
echo "Build completed!"
echo "Artifact: $ARTIFACT_PATH"
echo "ARTIFACT_PATH=$ARTIFACT_PATH"
echo ""
echo "Test:"
if [ "$TARGET_OS" = "win" ]; then
  echo "  chrome.exe --no-sandbox http://your-test-page.html"
else
  echo "  ./chrome --no-sandbox http://your-test-page.html"
fi
echo "  VideoDecoder and SharedArrayBuffer should work over HTTP"
echo "======================================"
