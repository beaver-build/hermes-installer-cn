# ============================================================================
#  Hermes Agent —— Windows 国内加速安装器  (install-hermes-cn.ps1)
# ============================================================================
#  原理：拉取 Hermes 官方 install.ps1 -> 用国内镜像替换其中所有境外源 ->
#        在当前会话执行打补丁后的脚本（官方参数全部透传）。
#
#  替换 / 加速的源：
#    1. GitHub    仓库克隆 / archive.zip / PortableGit          -> gh-proxy.com 等 GitHub 代理
#    2. uv 二进制 + uv 托管 Python (python-build-standalone)    -> GitHub 代理
#    3. Node.js 二进制包                                        -> npmmirror (cdn.npmmirror.com)
#    4. npm registry  (hermes 依赖 / agent-browser / camofox)   -> registry.npmmirror.com
#    5. Electron / electron-builder 二进制                      -> npmmirror 镜像
#    6. Python 包 (PyPI，uv/pip 安装 hermes 依赖)               -> 清华 TUNA
#    7. Playwright Chromium                                     -> 默认 CDN（非致命；附可选项）
#
#  用法（PowerShell，任意目录）：
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-hermes-cn.ps1"
#
#  自定义 GitHub 代理（默认 gh-proxy.com）：
#    $env:HERMES_CN_GH_PROXY = "https://gh-proxy.org"
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-hermes-cn.ps1"
#
#  先预览补丁结果、不真正执行：
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-hermes-cn.ps1" -DryRun
# ============================================================================

param(
    # GitHub 代理前缀（不要带尾部斜杠）。默认 gh-proxy.com；可用 $env:HERMES_CN_GH_PROXY 覆盖
    [string]$GHProxy = $(if ($env:HERMES_CN_GH_PROXY) { $env:HERMES_CN_GH_PROXY } else { 'https://gh-proxy.com' }),

    # 官方安装脚本地址（一般无需改；官方站不可达时自动改走 GitHub 代理）
    [string]$OfficialInstaller = 'https://hermes-agent.nousresearch.com/install.ps1',

    # —— 以下参数全部透传给官方 install.ps1 ——
    [string]$Branch = 'main',
    [string]$Commit = '',
    [string]$Tag = '',
    [string]$HermesHome = '',
    [string]$InstallDir = '',
    [switch]$NoVenv,
    [switch]$SkipSetup,
    [switch]$IncludeDesktop,

    [switch]$SkipRgFfmpeg,        # 跳过 ripgrep/ffmpeg 预装（默认会预装，以绕开卡死的 winget）
    [string]$RipgrepVersion = '14.1.1',  # 便携版 ripgrep 版本；失效时可改 14.1.0/14.0.3/13.0.0
    [switch]$SkipPlaywright,      # 跳过 Playwright Chromium 预装（默认会预装，以绕开 GCS 慢速下载）
    [switch]$SkipCuaDriver,       # 跳过 cua-driver 预装（默认会预装，以绕开 GitHub 慢速下载）

    [switch]$DryRun   # 只生成打补丁后的脚本，不执行
)

$ErrorActionPreference = 'Stop'
# 关闭 Invoke-WebRequest 的进度条：PS 5.1 下它逐字节重绘，会把下载速度拖慢 10~100 倍。
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }

function W-Info ($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function W-Ok   ($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function W-Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function W-Err  ($m) { Write-Host "[X] $m" -ForegroundColor Red }

# ----------------------------------------------------------------------------
# 预装 ripgrep + ffmpeg（便携版，经 GitHub 代理下载）
# ----------------------------------------------------------------------------
# 国内 winget 卡死的根因：winget 要先同步 MSStore/winget 源索引（GFW 下常挂死），
# 且其安装包本体也来自 GitHub / gyan.dev（同样慢）。Hermes 安装器对 rg/ffmpeg 仅做
# `Get-Command rg` / `Get-Command ffmpeg` 检测——只要 PATH 上有，整个 winget 步骤会被
# 跳过。故这里直接把便携版 rg.exe / ffmpeg.exe 放进 $HermesHome\bin 并持久化到 PATH。
# ----------------------------------------------------------------------------
function Resolve-HermesHome {
    if ($HermesHome) { return $HermesHome }
    if ($env:HERMES_HOME) { return $env:HERMES_HOME }
    return (Join-Path $env:LOCALAPPDATA 'hermes')
}

function Add-DirToUserPath {
    param([string]$Dir)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @(($userPath -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts -contains $Dir) { return }
    [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
    W-Ok "已加入用户 PATH: $Dir"
}

function Pre-ProvisionRgFfmpeg {
    $bin = Join-Path (Resolve-HermesHome) 'bin'
    New-Item -ItemType Directory -Force -Path $bin | Out-Null

    $haveRg = (Get-Command rg -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $bin 'rg.exe'))
    $haveFf = (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $bin 'ffmpeg.exe'))
    if ($haveRg -and $haveFf) { W-Ok 'ripgrep / ffmpeg 已就绪，跳过预装'; Add-DirToUserPath $bin; if (($env:Path -split ';') -notcontains $bin) { $env:Path = "$bin;$env:Path" }; return }

    if (-not $haveRg) {
        W-Info "预装 ripgrep $RipgrepVersion 便携版（经 $GHProxy，约 2MB）..."
        $zip = "ripgrep-$RipgrepVersion-x86_64-pc-windows-msvc.zip"
        $url = "$GHProxy/https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/$zip"
        $tmp = Join-Path $env:TEMP $zip; $ext = Join-Path $env:TEMP 'hermes-rg-extract'
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
            if (Test-Path $ext) { Remove-Item -Recurse -Force $ext }
            Expand-Archive -Path $tmp -DestinationPath $ext -Force
            $exe = Get-ChildItem -Path $ext -Recurse -Filter 'rg.exe' | Select-Object -First 1
            if ($exe) { Copy-Item $exe.FullName (Join-Path $bin 'rg.exe') -Force; W-Ok "ripgrep -> $bin\rg.exe" }
            else { W-Warn 'ripgrep zip 内未找到 rg.exe，将回落到 winget' }
        } catch { W-Warn "ripgrep 下载失败 ($_); 将回落到 winget" }
        finally { Remove-Item $tmp, $ext -Recurse -Force -ErrorAction SilentlyContinue }
    }

    if (-not $haveFf) {
        W-Info '预装 ffmpeg 便携版（BtbN 最新构建，经 GitHub 代理，约 90~110MB，请耐心等待）...'
        $zip = 'ffmpeg-master-latest-win64-gpl.zip'
        $url = "$GHProxy/https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$zip"
        $tmp = Join-Path $env:TEMP $zip; $ext = Join-Path $env:TEMP 'hermes-ff-extract'
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
            if (Test-Path $ext) { Remove-Item -Recurse -Force $ext }
            Expand-Archive -Path $tmp -DestinationPath $ext -Force
            foreach ($n in 'ffmpeg.exe', 'ffprobe.exe', 'ffplay.exe') {
                $f = Get-ChildItem -Path $ext -Recurse -Filter $n -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($f) { Copy-Item $f.FullName (Join-Path $bin $n) -Force }
            }
            if (Test-Path (Join-Path $bin 'ffmpeg.exe')) { W-Ok "ffmpeg -> $bin\ffmpeg.exe" }
            else { W-Warn 'ffmpeg zip 内未找到 ffmpeg.exe，将回落到 winget' }
        } catch { W-Warn "ffmpeg 下载失败 ($_); 将回落到 winget（仅影响 TTS 语音）" }
        finally { Remove-Item $tmp, $ext -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 持久化到用户 PATH + 当前会话，确保 Hermes 安装器的 Get-Command 命中
    Add-DirToUserPath $bin
    if (($env:Path -split ';') -notcontains $bin) { $env:Path = "$bin;$env:Path" }
}

# ============================================================================
# 镜像常量（按需修改）
# ============================================================================
$GHProxy           = $GHProxy.TrimEnd('/')
$NpmRegistry       = 'https://registry.npmmirror.com'
$NodeMirrorBase    = 'https://cdn.npmmirror.com/binaries/node'                       # /v<ver>/<zip>
$ElectronMirror    = 'https://npmmirror.com/mirrors/electron/'
$ElectronBuilderMr = 'https://npmmirror.com/mirrors/electron-builder-binaries/'
$PypiMirror        = 'https://pypi.tuna.tsinghua.edu.cn/simple'
# uv 的托管 Python 发行版 (python-build-standalone) 经 GitHub 代理下载
$UvPythonMirror    = "$GHProxy/https://github.com/astral-sh/python-build-standalone/releases/download"
# uv 二进制本身经 GitHub 代理（astral 安装器以此为 GitHub base 拼接下载地址）
$UvGithubBase      = "$GHProxy/https://github.com"
# Playwright Chromium：留空 = 用官方 CDN（Azure，国内通常可达；且其安装在 hermes 里是非致命的，
# 失败只告警、不影响主流程）。若官方 CDN 太慢可填 npmmirror（路径不稳定，仅作尝试）：
$PlaywrightHost    = ''   # 例如 'https://npmmirror.com/mirrors/playwright'

Write-Host ''
Write-Host '+-----------------------------------------------------------+' -ForegroundColor Magenta
Write-Host '|     Hermes Agent  国内加速安装器  (CN Mirror Edition)     |' -ForegroundColor Magenta
Write-Host '+-----------------------------------------------------------+' -ForegroundColor Magenta
Write-Host ''
W-Info "GitHub 代理     : $GHProxy"
W-Info "npm registry    : $NpmRegistry"
W-Info "Node 镜像       : $NodeMirrorBase"
W-Info "Electron 镜像   : $ElectronMirror"
W-Info "PyPI 镜像       : $PypiMirror"
W-Info "Playwright      : $(if ($PlaywrightHost) { $PlaywrightHost } else { '官方 CDN（默认）' })"
Write-Host ''

# ============================================================================
# 1) 设置镜像环境变量 —— 官方脚本及其子进程 / npm / uv / electron 均会继承
# ============================================================================
W-Info '设置国内镜像环境变量 ...'
$env:npm_config_registry               = $NpmRegistry
$env:npm_config_strict_ssl             = 'true'
$env:ELECTRON_MIRROR                   = $ElectronMirror
$env:ELECTRON_BUILDER_BINARIES_MIRROR  = $ElectronBuilderMr
$env:UV_INSTALLER_GITHUB_BASE_URL      = $UvGithubBase       # astral uv 安装器下载 uv 二进制
$env:UV_PYTHON_INSTALL_MIRROR          = $UvPythonMirror     # uv 托管 Python 下载
$env:UV_INDEX_URL                      = $PypiMirror         # uv 安装 Python 包
$env:PIP_INDEX_URL                     = $PypiMirror         # 兜底：原生 pip
$env:PIP_DISABLE_PIP_VERSION_CHECK     = '1'
if ($PlaywrightHost) { $env:PLAYWRIGHT_DOWNLOAD_HOST = $PlaywrightHost }

# ============================================================================
# 2) 下载官方安装脚本
# ============================================================================
W-Info "下载官方安装脚本: $OfficialInstaller"
$scriptText = $null
try {
    $scriptText = (Invoke-WebRequest -Uri $OfficialInstaller -UseBasicParsing).Content
} catch {
    W-Warn "官方站点拉取失败 ($_); 改走 GitHub 代理 ..."
    $alt = "$GHProxy/https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
    $scriptText = (Invoke-WebRequest -Uri $alt -UseBasicParsing).Content
}
if (-not $scriptText) { throw '无法获取官方安装脚本，请检查网络或用 -GHProxy 更换 GitHub 代理' }
W-Ok ("官方脚本已就绪 ({0:N0} 字符)" -f [int]$scriptText.Length)

# ============================================================================
# 3) 打补丁：境外源 -> 国内镜像
# ============================================================================
W-Info '替换境外源为国内镜像 ...'

# 3.1 GitHub -> 代理前缀
#     覆盖：仓库 HTTPS 克隆、archive.zip 兜底下载、git-for-windows PortableGit 下载。
#     仅做字面子串替换；SSH (git@github.com:) 不受影响，
#     且官方脚本无任何 api.github.com / raw.githubusercontent 真实请求（均为注释）。
$scriptText = $scriptText.Replace('https://github.com/', "$GHProxy/https://github.com/")
$ghHits = ([regex]::Matches($scriptText, [regex]::Escape("$GHProxy/https://github.com/"))).Count
W-Ok ("GitHub 源已改走代理（命中 {0} 处）" -f $ghHits)

# 3.2 Node.js：保留 nodejs.org 小列表解析版本号，仅把大包下载改走 npmmirror。
#     官方唯一行:  $downloadUrl = "${indexUrl}${zipName}"
#     zipName 形如 node-v22.23.2-win-x64.zip -> 取出 v22.23.2 -> 拼 npmmirror 直链。
#     （npmmirror 的 /mirrors/node/ 目录是 JS 渲染页，正则无法抓取文件名，
#      故仍用 nodejs.org 的小列表解析版本，仅大包走国内 CDN。）
$nodeAnchor  = '$downloadUrl = "${indexUrl}${zipName}"'
$nodeReplace = @'
$nodeVer = ($zipName -replace '^node-(v[\d.]+?)-win-.*$','$1'); $downloadUrl = "https://cdn.npmmirror.com/binaries/node/$nodeVer/$zipName"
'@.Trim()
if ($scriptText.Contains($nodeAnchor)) {
    $scriptText = $scriptText.Replace($nodeAnchor, $nodeReplace)
    W-Ok 'Node.js 二进制下载已改走 npmmirror 镜像'
} else {
    W-Warn '未定位到 Node 下载锚点（官方脚本可能已更新），Node.js 仍走 nodejs.org'
}

# ============================================================================
# 4) 写出打补丁后的脚本（UTF-8 无 BOM；内容为纯 ASCII，PS 5.1 兼容）
# ============================================================================
$patched = Join-Path $env:TEMP ('hermes-install-cn-' + [Guid]::NewGuid().ToString('N') + '.ps1')
[System.IO.File]::WriteAllText($patched, $scriptText, [System.Text.UTF8Encoding]::new($false))
W-Ok "打补丁后的脚本: $patched"

if ($DryRun) {
    W-Warn ("-DryRun：仅生成脚本，未执行。可审查后手动运行：`n  powershell -ExecutionPolicy Bypass -File `"$patched`"")
    return
}

# ============================================================================
# 4.5) 预装 ripgrep + ffmpeg（绕开国内卡死的 winget）
# ============================================================================
if (-not $SkipRgFfmpeg) {
    Pre-ProvisionRgFfmpeg
} else {
    W-Warn '-SkipRgFfmpeg：跳过 rg/ffmpeg 预装，将依赖 Hermes 自带的 winget 步骤（国内可能卡住）'
}
Write-Host ''

# ============================================================================
# 4.6) 预装 Playwright Chromium（绕开 GCS 慢速下载）
# ============================================================================
# cdn.playwright.dev -> storage.googleapis.com 在国内 ~0.1MB/s；这里在官方脚本跑到
# Playwright 阶段【之前】，先用 npmmirror 的 chrome-for-testing 镜像把 Chromium 装好
# 并写 INSTALLATION_COMPLETE 标记，官方脚本检测到即跳过下载。
if (-not $SkipPlaywright) {
    $pwScript = Join-Path $PSScriptRoot 'install-playwright-cn.ps1'
    if (-not (Test-Path $pwScript)) { $pwScript = Join-Path $env:USERPROFILE 'HermesCN\install-playwright-cn.ps1' }
    if (Test-Path $pwScript) {
        W-Info '预装 Playwright Chromium（npmmirror 镜像，约 35s）...'
        try { & $pwScript } catch { W-Warn "Playwright 预装出错 ($_); 将依赖 hermes 内置步骤（国内可能很慢）" }
    } else {
        W-Warn "未找到 install-playwright-cn.ps1 ($pwScript)；Playwright 将走 hermes 内置步骤（国内可能很慢）"
    }
} else {
    W-Warn '-SkipPlaywright：跳过 Chromium 预装，将依赖 hermes 内置步骤（国内可能卡住）'
}
Write-Host ''

# ============================================================================
# 4.7) 预装 cua-driver（绕开 GitHub 慢速下载）
# ============================================================================
# hermes 的 Computer Use（setup 向导）调用 cua-driver 官方安装器，直接从
# github.com/trycua/cua/releases 下二进制（国内慢/卡）。这里在向导跑到之前，
# 经代理预装好 cua-driver，向导检测到已安装即跳过。
if (-not $SkipCuaDriver) {
    $cuaScript = Join-Path $PSScriptRoot 'install-cua-driver-cn.ps1'
    if (-not (Test-Path $cuaScript)) { $cuaScript = Join-Path $env:USERPROFILE 'HermesCN\install-cua-driver-cn.ps1' }
    if (Test-Path $cuaScript) {
        W-Info '预装 cua-driver（GitHub 代理）...'
        try { & $cuaScript } catch { W-Warn "cua-driver 预装出错 ($_); Computer Use 将走 hermes 内置步骤（国内可能很慢）" }
        # 官方安装器只改注册表 PATH；显式补当前会话 PATH，让同进程的 hermes 检测到
        $cuaBin = Join-Path $env:LOCALAPPDATA 'Programs\Cua\cua-driver\bin'
        if ((Test-Path $cuaBin) -and (($env:Path -split ';') -notcontains $cuaBin)) { $env:Path = "$cuaBin;$env:Path" }
    } else {
        W-Warn "未找到 install-cua-driver-cn.ps1 ($cuaScript)；cua-driver 将走 hermes 内置步骤（国内可能很慢）"
    }
} else {
    W-Warn '-SkipCuaDriver：跳过 cua-driver 预装，将依赖 hermes 内置步骤（国内可能卡住）'
}
Write-Host ''

# ============================================================================
# 5) 执行（透传官方参数）
# ============================================================================
# 注意：传「命名参数」必须用哈希表 splat（@{}），不能用数组 splat（@()）。
# 数组 splat 会把 '-Branch' 当作位置参数值，导致 hermes 收到 $Branch='-Branch'
# （实测：数组 splat -> Branch=[-Branch]；哈希表 splat -> Branch=[main]）。
$officialArgs = @{}
if ($Branch)        { $officialArgs.Branch         = $Branch }
if ($Commit)        { $officialArgs.Commit         = $Commit }
if ($Tag)           { $officialArgs.Tag            = $Tag }
if ($HermesHome)    { $officialArgs.HermesHome     = $HermesHome }
if ($InstallDir)    { $officialArgs.InstallDir     = $InstallDir }
if ($NoVenv)        { $officialArgs.NoVenv         = $true }
if ($SkipSetup)     { $officialArgs.SkipSetup      = $true }
if ($IncludeDesktop){ $officialArgs.IncludeDesktop = $true }

W-Info '开始执行 Hermes 安装（透传官方参数）...'
Write-Host ''
$failed = $false
try {
    & $patched @officialArgs
} catch {
    $failed = $true
    Write-Host ''
    W-Err "安装中断: $_"
    W-Err "已保留打补丁脚本以便排错: $patched"
    Write-Host "  分阶段排错: powershell -ExecutionPolicy Bypass -File `"$patched`" -Stage <stage>" -ForegroundColor Yellow
} finally {
    if (-not $failed) { Remove-Item $patched -Force -ErrorAction SilentlyContinue }
}

# ----------------------------------------------------------------------------
# 6) Playwright Chromium 兑底
# ----------------------------------------------------------------------------
# hermes 内置的 `playwright install chromium` 在国内常卡在 GCS 慢速下载
# (cdn.playwright.dev -> storage.googleapis.com, ~0.1MB/s)。若安装结束后
# Chromium 仍未就绪，用 npmmirror 的 chrome-for-testing 镜像补装
# (写 INSTALLATION_COMPLETE 标记，下次 playwright install 会跳过)。
$crHome  = Join-Path $env:LOCALAPPDATA 'ms-playwright'
$crReady = $false
if (Test-Path $crHome) {
    $crReady = [bool](Get-ChildItem -Path $crHome -Recurse -Filter 'INSTALLATION_COMPLETE' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'chromium' } | Select-Object -First 1)
}
$pwScript = Join-Path $PSScriptRoot 'install-playwright-cn.ps1'
if (-not (Test-Path $pwScript)) { $pwScript = Join-Path $env:USERPROFILE 'HermesCN\install-playwright-cn.ps1' }
if (-not $crReady) {
    Write-Host ''
    if ($failed) {
        W-Warn 'Playwright Chromium 未就绪。若卡在浏览器下载，中断后运行镜像脚本补装，再重跑本安装器即可跳过：'
        Write-Host "  powershell -ExecutionPolicy Bypass -File `"$pwScript`"" -ForegroundColor Yellow
    } elseif (Test-Path $pwScript) {
        W-Info '检测到 Chromium 未就绪，用国内镜像补装...'
        try { & $pwScript } catch { W-Warn "Playwright 补装出错 ($_); 可手动运行: $pwScript" }
    } else {
        W-Warn "Chromium 未就绪且未找到 $pwScript；浏览器工具暂不可用，可稍后手动补装。"
    }
}

Write-Host ''
if (-not $failed) {
    Write-Host "完成。打开新的 PowerShell 窗口，输入 hermes 即可开始。" -ForegroundColor Green
}
