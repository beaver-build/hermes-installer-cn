#!/usr/bin/env bash
set -euo pipefail

GH_PROXY="${HERMES_CN_GH_PROXY:-https://gh-proxy.com}"
RIPGREP_VERSION="${HERMES_CN_RIPGREP_VERSION:-14.1.1}"
BIN_DIR="${HERMES_CN_BIN_DIR:-}"
SKIP_RIPGREP=false
SKIP_FFMPEG=false
PORTABLE_ONLY=false

usage() {
  cat <<'EOF'
用法: ./install-rg-ffmpeg-cn.sh [选项]

选项:
  --gh-proxy URL          GitHub 下载代理
  --bin-dir PATH          安装目录（默认 ~/.local/bin；Linux root 为 /usr/local/bin）
  --ripgrep-version VER   ripgrep 版本（默认 14.1.1）
  --skip-ripgrep          不安装 ripgrep
  --skip-ffmpeg           不安装 ffmpeg
  --portable-only         不调用 apt/brew 等系统包管理器
  -h, --help              显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gh-proxy) GH_PROXY="${2:?--gh-proxy 需要 URL}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:?--bin-dir 需要路径}"; shift 2 ;;
    --ripgrep-version) RIPGREP_VERSION="${2:?--ripgrep-version 需要版本号}"; shift 2 ;;
    --skip-ripgrep) SKIP_RIPGREP=true; shift ;;
    --skip-ffmpeg) SKIP_FFMPEG=true; shift ;;
    --portable-only) PORTABLE_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[X] 未知参数: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

GH_PROXY="${GH_PROXY%/}"
if [[ -z "$BIN_DIR" ]]; then
  if [[ "$(uname -s)" == "Linux" && "$(id -u)" -eq 0 ]]; then
    BIN_DIR=/usr/local/bin
  else
    BIN_DIR="$HOME/.local/bin"
  fi
fi
mkdir -p "$BIN_DIR"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-cn-tools.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

info() { printf '\033[0;36m-> %s\033[0m\n' "$*"; }
ok() { printf '\033[0;32m[OK] %s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m[!] %s\033[0m\n' "$*" >&2; }

download() {
  local upstream_url="$1"
  local output="$2"
  curl --fail --location --show-error --retry 3 --connect-timeout 10 \
    "$GH_PROXY/$upstream_url" --output "$output"
}

verify_sha1() {
  local file="$1"
  local expected="$2"
  local actual=""
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 1 "$file" | awk '{print $1}')"
  elif command -v sha1sum >/dev/null 2>&1; then
    actual="$(sha1sum "$file" | awk '{print $1}')"
  else
    warn "系统没有 shasum/sha1sum，无法校验 $file"
    return 0
  fi
  [[ "$actual" == "$expected" ]] || {
    warn "文件校验失败: $file"
    return 1
  }
}

os="$(uname -s)"
arch="$(uname -m)"

run_admin() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo "$@"
  else
    return 1
  fi
}

try_system_packages() {
  local packages=()
  [[ "$SKIP_RIPGREP" == false ]] && ! command -v rg >/dev/null 2>&1 && packages+=(ripgrep)
  [[ "$SKIP_FFMPEG" == false ]] && ! command -v ffmpeg >/dev/null 2>&1 && packages+=(ffmpeg)
  (( ${#packages[@]} > 0 )) || return 0

  if [[ "$os" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    info "优先通过现有 Homebrew 源安装: ${packages[*]}"
    brew install "${packages[@]}" && return 0
    warn 'Homebrew 安装失败，改用便携包'
    return 1
  fi

  [[ "$os" == Linux ]] || return 1
  if command -v apt-get >/dev/null 2>&1; then
    info "优先通过现有 apt 源安装: ${packages[*]}"
    if run_admin env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      && run_admin env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"; then
      return 0
    fi
  elif command -v dnf >/dev/null 2>&1; then
    info "优先通过现有 dnf 源安装: ${packages[*]}"
    run_admin dnf install -y "${packages[@]}" && return 0
  elif command -v pacman >/dev/null 2>&1; then
    info "优先通过现有 pacman 源安装: ${packages[*]}"
    run_admin pacman -S --noconfirm --needed "${packages[@]}" && return 0
  elif command -v zypper >/dev/null 2>&1; then
    info "优先通过现有 zypper 源安装: ${packages[*]}"
    run_admin zypper --non-interactive install "${packages[@]}" && return 0
  elif command -v apk >/dev/null 2>&1; then
    info "优先通过现有 apk 源安装: ${packages[*]}"
    run_admin apk add "${packages[@]}" && return 0
  fi

  warn '系统包管理器不可用或安装失败，改用便携包'
  return 1
}

if [[ "$PORTABLE_ONLY" == false ]]; then
  try_system_packages || true
fi

if [[ "$SKIP_RIPGREP" == false ]] && ! command -v rg >/dev/null 2>&1; then
  rg_target=""
  case "$os/$arch" in
    Darwin/arm64|Darwin/aarch64) rg_target=aarch64-apple-darwin ;;
    Darwin/x86_64) rg_target=x86_64-apple-darwin ;;
    Linux/x86_64|Linux/amd64) rg_target=x86_64-unknown-linux-musl ;;
    Linux/arm64|Linux/aarch64) rg_target=aarch64-unknown-linux-gnu ;;
  esac

  if [[ -n "$rg_target" ]]; then
    rg_archive="ripgrep-$RIPGREP_VERSION-$rg_target.tar.gz"
    info "预装 ripgrep $RIPGREP_VERSION ($rg_target)"
    download \
      "https://github.com/BurntSushi/ripgrep/releases/download/$RIPGREP_VERSION/$rg_archive" \
      "$tmp_dir/$rg_archive"
    tar -xzf "$tmp_dir/$rg_archive" -C "$tmp_dir"
    rg_binary="$(find "$tmp_dir" -type f -name rg -perm -u+x | head -n 1)"
    [[ -n "$rg_binary" ]] || { warn "压缩包中未找到 rg"; exit 1; }
    install -m 0755 "$rg_binary" "$BIN_DIR/rg"
    ok "ripgrep -> $BIN_DIR/rg"
  else
    warn "当前平台 $os/$arch 没有预置的 ripgrep 包，将交给官方安装器处理"
  fi
elif [[ "$SKIP_RIPGREP" == false ]]; then
  ok "ripgrep 已存在: $(command -v rg)"
fi

if [[ "$SKIP_FFMPEG" == false ]] && ! command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg_url=""
  ffmpeg_sha1=""
  case "$os/$arch" in
    Darwin/arm64|Darwin/aarch64)
      ffmpeg_url='https://registry.npmmirror.com/@ffmpeg-installer/darwin-arm64/-/darwin-arm64-4.1.5.tgz'
      ffmpeg_sha1='b7b5c262dd96d1aea4807514e1cdcf6e11f82743'
      ;;
    Darwin/x86_64)
      ffmpeg_url='https://registry.npmmirror.com/@ffmpeg-installer/darwin-x64/-/darwin-x64-4.1.0.tgz'
      ffmpeg_sha1='48e1706c690e628148482bfb64acb67472089aaa'
      ;;
    Linux/arm64|Linux/aarch64)
      ffmpeg_url='https://registry.npmmirror.com/@ffmpeg-installer/linux-arm64/-/linux-arm64-4.1.4.tgz'
      ffmpeg_sha1='7219f3f901bb67f7926cb060b56b6974a6cad29f'
      ;;
    Linux/x86_64|Linux/amd64)
      ffmpeg_url='https://registry.npmmirror.com/@ffmpeg-installer/linux-x64/-/linux-x64-4.1.0.tgz'
      ffmpeg_sha1='b4a5d89c4e12e6d9306dbcdc573df716ec1c4323'
      ;;
  esac

  if [[ -n "$ffmpeg_url" ]]; then
    info "预装 ffmpeg (${os}/${arch}，npmmirror，约 15-20 MB)"
    curl --fail --location --show-error --retry 3 --connect-timeout 10 \
      "$ffmpeg_url" --output "$tmp_dir/ffmpeg.tgz"
    verify_sha1 "$tmp_dir/ffmpeg.tgz" "$ffmpeg_sha1"
    tar -xzf "$tmp_dir/ffmpeg.tgz" -C "$tmp_dir"
    [[ -f "$tmp_dir/package/ffmpeg" ]] || { warn 'ffmpeg 包结构异常'; exit 1; }
    install -m 0755 "$tmp_dir/package/ffmpeg" "$BIN_DIR/ffmpeg"
    "$BIN_DIR/ffmpeg" -version >/dev/null 2>&1 || {
      rm -f "$BIN_DIR/ffmpeg"
      warn "下载的 ffmpeg 无法在当前系统运行，将交给官方安装器处理"
      exit 1
    }
    ok "ffmpeg -> $BIN_DIR/ffmpeg"
  else
    warn "当前平台 $os/$arch 没有预置的 ffmpeg 包，将交给官方安装器处理"
  fi
elif [[ "$SKIP_FFMPEG" == false ]]; then
  ok "ffmpeg 已存在: $(command -v ffmpeg)"
fi

printf '\n工具预装完成。当前安装目录: %s\n' "$BIN_DIR"
