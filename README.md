# Hermes Agent 国内加速安装器

面向中国大陆网络环境的 Hermes Agent 安装辅助工具，支持 Windows、Linux 和 macOS。

安装器每次运行都会下载**最新版** Hermes Agent 官方安装脚本，只对已知的境外下载入口做镜像替换，并把官方参数原样透传。因此安装流程仍由 Hermes 官方脚本决定，不会在本仓库固化一份很快过期的官方安装器。

## 快速安装

### Linux / macOS

```bash
git clone https://github.com/beaver-build/hermes-installer-cn.git
cd hermes-installer-cn
./install.sh
```

也可以先查看帮助或仅生成打补丁后的官方脚本：

```bash
./install-hermes-cn.sh --cn-help
./install-hermes-cn.sh --dry-run
```

### Windows

解压后双击 `install.bat`，或在 PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-hermes-cn.ps1
```

## 加速内容

| 下载来源 | 国内版处理 |
|---|---|
| GitHub 仓库、Release、raw 文件 | 启动时探测 GitHub 代理，也可手动指定 |
| npm registry | `registry.npmmirror.com` |
| PyPI / uv Python 包 | 清华 TUNA |
| uv 与 uv 托管 Python | GitHub 代理 |
| Node.js 二进制 | `cdn.npmmirror.com/binaries/node` |
| Electron / electron-builder | npmmirror |
| ripgrep | 提前下载官方便携包，绕开系统包管理器慢源 |
| ffmpeg | 从 npmmirror 提前下载平台独立包，并校验包摘要 |
| cua-driver | 提前下载官方安装器，并把 GitHub Release/API 改走代理 |
| Playwright Chromium | `cdn.npmmirror.com/binaries/playwright`，系统依赖仍由官方逻辑处理 |

Linux/macOS 版不会擅自改写 `/etc/apt`、Homebrew 或其他系统级软件源；官方脚本需要通过系统包管理器安装 Git、编译器或浏览器系统库时，仍使用机器现有的软件源配置。

## Linux / macOS 常用选项

国内版选项：

```bash
# 指定 GitHub 代理
./install.sh --gh-proxy https://gh-proxy.com

# 跳过便携工具或 cua-driver 的提前安装
./install.sh --skip-tools-preinstall --skip-cua-preinstall

# 只生成补丁脚本，不执行安装
./install.sh --dry-run
```

官方 `install.sh` 的参数可以直接追加：

```bash
./install.sh --skip-setup
./install.sh --skip-browser --skip-computer-use
./install.sh --include-desktop
./install.sh --branch main --dir "$HOME/.hermes/hermes-agent"
```

也可以通过环境变量覆盖镜像：

```bash
export HERMES_CN_GH_PROXY=https://gh-proxy.org
export npm_config_registry=https://registry.npmmirror.com
export UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
export PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright
./install.sh
```

单独补装工具：

```bash
./install-rg-ffmpeg-cn.sh
./install-cua-driver-cn.sh
```

## Windows 常用选项

```powershell
# 预览补丁结果，不执行
.\install-hermes-cn.ps1 -DryRun

# 指定 GitHub 代理
$env:HERMES_CN_GH_PROXY = "https://gh-proxy.com"
.\install-hermes-cn.ps1

# 跳过某个预装步骤
.\install-hermes-cn.ps1 -SkipRgFfmpeg -SkipPlaywright -SkipCuaDriver
```

单独补装工具：

```powershell
.\install-rg-ffmpeg-cn.ps1
.\install-playwright-cn.ps1
.\install-cua-driver-cn.ps1
```

## 文件说明

| 文件 | 平台 | 作用 |
|---|---|---|
| `install.sh` | Linux / macOS | Unix 一键入口 |
| `install-hermes-cn.sh` | Linux / macOS | 拉取最新版官方脚本、设置镜像、打补丁并执行 |
| `install-rg-ffmpeg-cn.sh` | Linux / macOS | 预装 ripgrep / ffmpeg |
| `install-cua-driver-cn.sh` | Linux / macOS | 通过 GitHub 代理预装 cua-driver |
| `install.bat` | Windows | 双击入口 |
| `install-hermes-cn.ps1` | Windows | Windows 主安装器 |
| `install-rg-ffmpeg-cn.ps1` | Windows | 预装 ripgrep / ffmpeg |
| `install-playwright-cn.ps1` | Windows | 预装 Playwright Chromium |
| `install-cua-driver-cn.ps1` | Windows | 预装 cua-driver |

## 安全说明

本项目会动态下载并执行 Hermes、uv 和 cua-driver 的官方安装脚本。建议首次使用时先运行 `--dry-run` 审查生成结果。镜像代理是传输中间层；对供应链安全要求较高的环境，应使用自己信任的代理或直接连接官方源。

安装完成后打开一个新终端，运行 `hermes` 开始使用。
