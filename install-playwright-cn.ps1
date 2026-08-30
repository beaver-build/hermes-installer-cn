# ============================================================================
#  Playwright Chromium 国内镜像预装 —— install-playwright-cn.ps1
# ============================================================================
#  问题：Playwright 的 Chrome for Testing 官方源 cdn.playwright.dev 会 307 跳到
#        storage.googleapis.com（GCS），国内约 0.1MB/s，172MB 要下 ~22 分钟。
#  方案：从 npmmirror 的 chrome-for-testing 镜像下载（~7.5MB/s），解压到 Playwright
#        缓存目录并写 INSTALLATION_COMPLETE 标记。playwright install 检测到标记即跳过。
#
#  已核实 playwright-core 源码 (1.58.2)：
#    缓存根 : %LOCALAPPDATA%\ms-playwright   (= registryDirectory)
#    chromium       -> chromium-<revision>\chrome-win64\chrome.exe
#    headless shell -> chromium_headless_shell-<revision>\chrome-headless-shell-win64\chrome-headless-shell.exe
#    完成标记 : <浏览器目录>\INSTALLATION_COMPLETE   (存在即跳过下载, browserFetcher.js:46)
#
#  用法：
#    1) 先 Ctrl+C 中断卡在 Playwright 下载的 hermes 安装
#    2) powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-playwright-cn.ps1"
#    3) 重新运行 hermes 安装器 -> Playwright 步骤因标记存在而跳过
# ============================================================================

param(
    [string]$BrowsersJson = '',     # 留空=自动从 hermes 检出里找 playwright-core/browsers.json
    [string]$MsPlaywright = (Join-Path $env:LOCALAPPDATA 'ms-playwright'),
    [string]$Revision = '',         # 留空=自动从 browsers.json 读
    [string]$BrowserVersion = '',   # 留空=自动从 browsers.json 读
    [switch]$SkipHeadlessShell
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }

function W-Info ($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function W-Ok   ($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function W-Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

# --- 1. 自动定位 browsers.json，读出 revision / browserVersion ---
if (-not $BrowsersJson) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\node_modules\playwright-core\browsers.json'),
        (Join-Path $env:USERPROFILE '.hermes\hermes-agent\node_modules\playwright-core\browsers.json')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $BrowsersJson = $c; break } }
}
if ($BrowsersJson -and (Test-Path $BrowsersJson)) {
    W-Ok "browsers.json: $BrowsersJson"
    $bj = Get-Content $BrowsersJson -Raw | ConvertFrom-Json
    $cr = $bj.browsers | Where-Object { $_.name -eq 'chromium' }
    if (-not $Revision -and $cr.revision)             { $Revision = $cr.revision }
    if (-not $BrowserVersion -and $cr.browserVersion) { $BrowserVersion = $cr.browserVersion }
} else {
    W-Warn '未找到 browsers.json（hermes 可能尚未装好 deps），用内置默认 revision=1208 / 145.0.7632.6；可用 -Revision/-BrowserVersion 覆盖'
}
if (-not $Revision)       { $Revision = '1208' }
if (-not $BrowserVersion) { $BrowserVersion = '145.0.7632.6' }
W-Info "Playwright chromium: revision=$Revision  browserVersion=$BrowserVersion"

# --- 2. 清理可能残留的 dirlock（上次 Ctrl+C 中断会留下）---
$lock = Join-Path $MsPlaywright '__dirlock'
if (Test-Path $lock) { Remove-Item -Recurse -Force $lock -ErrorAction SilentlyContinue; W-Warn '已清理残留 __dirlock' }

# --- 3. 通用：下载 -> 解压 -> 校验可执行 -> 写标记 ---
$CftMirror = "https://cdn.npmmirror.com/binaries/chrome-for-testing/$BrowserVersion/win64"
New-Item -ItemType Directory -Force -Path $MsPlaywright | Out-Null

function Install-CftBrowser {
    param([string]$DirName, [string]$ZipName, [string]$ExeRelPath)
    $target = Join-Path $MsPlaywright $DirName
    $marker = Join-Path $target 'INSTALLATION_COMPLETE'
    if (Test-Path $marker) { W-Ok "$DirName 已有完成标记，跳过"; return }

    $url = "$CftMirror/$ZipName"
    $tmp = Join-Path $env:TEMP "pw-cft-$ZipName"
    W-Info "下载 $ZipName （npmmirror，约 $BrowserVersion）..."
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Expand-Archive -Path $tmp -DestinationPath $target -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    $exe = Join-Path $target $ExeRelPath
    if (-not (Test-Path $exe)) {
        throw "$DirName 解压后未找到 $ExeRelPath（npmmirror 该版本结构异常？）"
    }
    [System.IO.File]::WriteAllText($marker, '')   # 空标记文件；存在即跳过
    W-Ok "$DirName 已就绪 -> $target"
}

# --- 4. 装 chromium（完整）+ headless shell ---
Install-CftBrowser "chromium-$Revision" 'chrome-win64.zip' (Join-Path 'chrome-win64' 'chrome.exe')
if (-not $SkipHeadlessShell) {
    Install-CftBrowser "chromium_headless_shell-$Revision" 'chrome-headless-shell-win64.zip' (Join-Path 'chrome-headless-shell-win64' 'chrome-headless-shell.exe')
}

Write-Host ''
Write-Host '完成。重新运行 hermes 安装器时，Playwright 步骤会因标记存在而跳过慢速下载。' -ForegroundColor Green
Write-Host "  缓存目录: $MsPlaywright" -ForegroundColor DarkGray
