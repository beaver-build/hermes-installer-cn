#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OFFICIAL_INSTALLER="${HERMES_CN_OFFICIAL_INSTALLER:-https://hermes-agent.nousresearch.com/install.sh}"
GH_PROXY="${HERMES_CN_GH_PROXY:-}"
DRY_RUN=false
SKIP_TOOLS=false
SKIP_CUA=false
OFFICIAL_ARGS=()

usage() {
  cat <<'EOF'
Hermes Agent 国内加速安装器（Linux / macOS）

用法:
  ./install-hermes-cn.sh [国内版选项] [官方 install.sh 选项]

国内版选项:
  --gh-proxy URL             指定 GitHub 下载代理
  --official-installer URL   指定官方 install.sh 地址
  --skip-tools-preinstall    不预装 ripgrep / ffmpeg
  --skip-cua-preinstall      不提前安装 cua-driver
  --dry-run                  只生成打补丁后的官方脚本
  --cn-help                  显示本帮助

其余参数原样传给最新版官方 install.sh，例如：
  --skip-setup --skip-browser --skip-computer-use --include-desktop
  --branch NAME --commit SHA --dir PATH --hermes-home PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gh-proxy) GH_PROXY="${2:?--gh-proxy 需要 URL}"; shift 2 ;;
    --official-installer) OFFICIAL_INSTALLER="${2:?--official-installer 需要 URL}"; shift 2 ;;
    --skip-tools-preinstall) SKIP_TOOLS=true; shift ;;
    --skip-cua-preinstall) SKIP_CUA=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --cn-help|-h|--help) usage; exit 0 ;;
    --skip-computer-use)
      SKIP_CUA=true
      OFFICIAL_ARGS+=("$1")
      shift
      ;;
    *) OFFICIAL_ARGS+=("$1"); shift ;;
  esac
done

info() { printf '\033[0;36m-> %s\033[0m\n' "$*"; }
ok() { printf '\033[0;32m[OK] %s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m[!] %s\033[0m\n' "$*" >&2; }

probe_proxy() {
  local candidate="$1"
  curl --fail --location --silent --range 0-262143 \
    --connect-timeout 4 --max-time 10 --output /dev/null --write-out '%{speed_download}' \
    "$candidate/https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz" \
    2>/dev/null
}

if [[ -z "$GH_PROXY" ]]; then
  info '测速 GitHub 代理（取当前较快者）'
  best_speed=0
  for candidate in https://gh-proxy.com https://gh-proxy.org; do
    candidate_speed="$(probe_proxy "$candidate" || true)"
    candidate_speed="${candidate_speed%.*}"
    if [[ "$candidate_speed" =~ ^[0-9]+$ ]] && (( candidate_speed > best_speed )); then
      GH_PROXY="$candidate"
      best_speed="$candidate_speed"
    fi
  done
fi

if [[ -z "$GH_PROXY" ]]; then
  printf '[X] 没有探测到可用 GitHub 代理。请设置 HERMES_CN_GH_PROXY 或使用 --gh-proxy。\n' >&2
  exit 1
fi
GH_PROXY="${GH_PROXY%/}"
if [[ ! "$GH_PROXY" =~ ^https://[A-Za-z0-9._:/-]+$ ]]; then
  printf '[X] GitHub 代理 URL 不合法: %s\n' "$GH_PROXY" >&2
  exit 2
fi
ok "GitHub 代理: $GH_PROXY"

export HERMES_CN_GH_PROXY="$GH_PROXY"
export npm_config_registry="${npm_config_registry:-https://registry.npmmirror.com}"
export npm_config_disturl="${npm_config_disturl:-https://cdn.npmmirror.com/binaries/node}"
export ELECTRON_MIRROR="${ELECTRON_MIRROR:-https://npmmirror.com/mirrors/electron/}"
export ELECTRON_BUILDER_BINARIES_MIRROR="${ELECTRON_BUILDER_BINARIES_MIRROR:-https://npmmirror.com/mirrors/electron-builder-binaries/}"
export UV_INSTALLER_GITHUB_BASE_URL="${UV_INSTALLER_GITHUB_BASE_URL:-$GH_PROXY/https://github.com}"
export UV_PYTHON_INSTALL_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-$GH_PROXY/https://github.com/astral-sh/python-build-standalone/releases/download}"
export UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export UV_INDEX_URL="${UV_INDEX_URL:-$UV_DEFAULT_INDEX}"
export PIP_INDEX_URL="${PIP_INDEX_URL:-$UV_DEFAULT_INDEX}"
export PIP_DISABLE_PIP_VERSION_CHECK=1

printf '\nHermes Agent 国内加速安装器（Linux / macOS）\n'
printf '  npm:      %s\n' "$npm_config_registry"
printf '  PyPI:     %s\n' "$UV_DEFAULT_INDEX"
printf '  Node:     %s\n' "$npm_config_disturl"
printf '  Electron: %s\n\n' "$ELECTRON_MIRROR"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-cn-installer.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

official_script="$tmp_dir/install-official.sh"
patched_script="$tmp_dir/install-hermes-cn-patched.sh"

info "下载最新版官方安装脚本: $OFFICIAL_INSTALLER"
if ! curl --fail --location --show-error --retry 2 --connect-timeout 10 \
  "$OFFICIAL_INSTALLER" --output "$official_script"; then
  fallback="$GH_PROXY/https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"
  warn "官方站点不可达，改走 GitHub 代理: $fallback"
  curl --fail --location --show-error --retry 3 --connect-timeout 10 \
    "$fallback" --output "$official_script"
fi

if ! head -n 5 "$official_script" | grep -q 'Hermes Agent Installer'; then
  printf '[X] 下载内容不像 Hermes 官方 install.sh，已终止。\n' >&2
  exit 1
fi

# 只替换官方脚本中已知的下载入口；所有安装阶段和官方参数仍由最新版脚本负责。
sed \
  -e "s|https://github.com/|$GH_PROXY/https://github.com/|g" \
  -e "s|https://raw.githubusercontent.com/|$GH_PROXY/https://raw.githubusercontent.com/|g" \
  -e "s|git@github.com:NousResearch/hermes-agent.git|$GH_PROXY/https://github.com/NousResearch/hermes-agent.git|g" \
  -e "s|https://nodejs.org/dist/latest-v\${NODE_VERSION}.x/|https://cdn.npmmirror.com/binaries/node/latest-v\${NODE_VERSION}.x/|g" \
  -e 's|local checks=("https://pypi.org/simple/" "https://duckduckgo.com/")|local checks=("https://pypi.tuna.tsinghua.edu.cn/simple/" "https://registry.npmmirror.com/")|' \
  "$official_script" > "$patched_script"
chmod +x "$patched_script"

github_hits="$(grep -cF "$GH_PROXY/https://github.com/" "$patched_script" || true)"
raw_hits="$(grep -cF "$GH_PROXY/https://raw.githubusercontent.com/" "$patched_script" || true)"
node_hits="$(grep -cF "https://cdn.npmmirror.com/binaries/node/latest-v\${NODE_VERSION}.x/" "$patched_script" || true)"
ok "官方脚本已打补丁（GitHub $github_hits 处，raw $raw_hits 处，Node $node_hits 处）"

if [[ "$DRY_RUN" == true ]]; then
  output_path="${TMPDIR:-/tmp}/hermes-install-cn-$(date +%Y%m%d%H%M%S).sh"
  cp "$patched_script" "$output_path"
  chmod +x "$output_path"
  printf '\n[!] --dry-run：未安装。补丁脚本保留在 %s\n' "$output_path"
  exit 0
fi

if [[ "$SKIP_TOOLS" == false ]]; then
  printf '\n'
  if ! "$SCRIPT_DIR/install-rg-ffmpeg-cn.sh" --gh-proxy "$GH_PROXY"; then
    warn 'ripgrep/ffmpeg 预装未完全成功，继续由官方安装器按系统包管理器补装'
  fi
fi

if [[ "$SKIP_CUA" == false ]]; then
  printf '\n'
  if ! PATH="$HOME/.local/bin:$PATH" "$SCRIPT_DIR/install-cua-driver-cn.sh" --gh-proxy "$GH_PROXY"; then
    warn 'cua-driver 预装失败，继续安装 Hermes；之后仍可单独补装'
  fi
fi

if [[ "$(uname -s)" == "Linux" && "$(id -u)" -eq 0 ]]; then
  export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
else
  export PATH="$HOME/.local/bin:$PATH"
fi

printf '\n'
info '执行最新版 Hermes 官方安装脚本'
if (( ${#OFFICIAL_ARGS[@]} > 0 )); then
  /bin/bash "$patched_script" "${OFFICIAL_ARGS[@]}"
else
  /bin/bash "$patched_script"
fi
