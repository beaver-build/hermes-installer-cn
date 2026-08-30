#!/usr/bin/env bash
set -euo pipefail

GH_PROXY="${HERMES_CN_GH_PROXY:-https://gh-proxy.com}"

usage() {
  cat <<'EOF'
用法: ./install-cua-driver-cn.sh [--gh-proxy URL]

下载 cua-driver 官方 Unix 安装脚本，将 GitHub Release/API 地址改走代理后执行。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gh-proxy) GH_PROXY="${2:?--gh-proxy 需要 URL}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[X] 未知参数: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

GH_PROXY="${GH_PROXY%/}"
if [[ ! "$GH_PROXY" =~ ^https://[A-Za-z0-9._:/-]+$ ]]; then
  printf '[X] GitHub 代理 URL 不合法: %s\n' "$GH_PROXY" >&2
  exit 2
fi

if command -v cua-driver >/dev/null 2>&1; then
  printf '\033[0;32m[OK] cua-driver 已存在: %s\033[0m\n' "$(command -v cua-driver)"
  exit 0
fi

if [[ "$(uname -s)" == "Darwin" && -d /Applications && ! -w /Applications ]]; then
  printf '\033[0;33m[!] /Applications 不可写，跳过 cua-driver；请用有权限的 macOS 账户安装。\033[0m\n' >&2
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-cn-cua.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

printf '\033[0;36m-> 下载 cua-driver 官方安装器并替换 GitHub 下载源\033[0m\n'
curl --fail --location --show-error --retry 3 --connect-timeout 10 \
  'https://cua.ai/driver/_install-rust.sh' --output "$tmp_dir/install-rust.sh"

sed \
  -e "s|https://github.com/|$GH_PROXY/https://github.com/|g" \
  -e "s|https://api.github.com/|$GH_PROXY/https://api.github.com/|g" \
  "$tmp_dir/install-rust.sh" > "$tmp_dir/install-rust-cn.sh"
chmod +x "$tmp_dir/install-rust-cn.sh"

PATH="$HOME/.local/bin:$PATH" /bin/bash "$tmp_dir/install-rust-cn.sh"

if [[ -x "$HOME/.local/bin/cua-driver" ]] || command -v cua-driver >/dev/null 2>&1; then
  printf '\033[0;32m[OK] cua-driver 安装完成\033[0m\n'
else
  printf '\033[0;33m[!] 安装器已结束，但当前 PATH 尚未发现 cua-driver；新终端会生效。\033[0m\n' >&2
fi
