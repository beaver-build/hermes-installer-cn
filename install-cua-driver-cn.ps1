# ============================================================================
#  cua-driver 国内镜像预装 —— install-cua-driver-cn.ps1
# ============================================================================
#  问题：hermes 的 Computer Use（setup 向导）会调用 cua-driver 官方安装器，
#        它直接从 github.com/trycua/cua/releases 下载二进制（国内慢/卡），
#        且安装器本身也从 raw.githubusercontent.com 拉取——两条都是直连 GitHub。
#  方案：经 GitHub 代理拉取官方安装器 -> 把其中的 github.com 下载源替换成代理
#        -> 用 BAKED_VERSION 锁定版本（跳过 api.github.com 版本解析，避免卡住）
#        -> 跑一次装好。hermes 检测到 cua-driver 已安装（PATH）即跳过。
#
#  用法：
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-cua-driver-cn.ps1"
#  换代理：
#    $env:HERMES_CN_GH_PROXY = "https://gh-proxy.org"
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-cua-driver-cn.ps1"
# ============================================================================

param(
    [string]$GHProxy = $(if ($env:HERMES_CN_GH_PROXY) { $env:HERMES_CN_GH_PROXY } else { 'https://gh-proxy.com' })
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }
$GHProxy = $GHProxy.TrimEnd('/')

function W-Info ($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function W-Ok   ($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function W-Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

$binDir       = Join-Path $env:LOCALAPPDATA 'Programs\Cua\cua-driver\bin'
$installerRaw = "$GHProxy/https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.ps1"

# 已安装则跳过
$existing = Get-Command cua-driver -ErrorAction SilentlyContinue
if ($existing -or (Test-Path (Join-Path $binDir 'cua-driver.exe'))) {
    W-Ok "cua-driver 已安装，跳过 ($($existing.Source))"
    if ((Test-Path $binDir) -and (($env:Path -split ';') -notcontains $binDir)) { $env:Path = "$binDir;$env:Path" }
    return
}

W-Info "经 $GHProxy 拉取 cua-driver 官方安装器..."
$script = (Invoke-WebRequest -Uri $installerRaw -UseBasicParsing).Content
if (-not $script) { throw '无法获取 cua-driver 安装器（检查 GitHub 代理是否可用）' }

# 锁定 BAKED_VERSION：跳过安装器对 api.github.com 的版本解析（国内可能卡）
if ($script -match 'CuaDriverRsBakedVersion\s*=\s*"([^"]+)"') {
    $env:CUA_DRIVER_RS_VERSION = $Matches[1]
    W-Info "锁定版本 $($Matches[1])（用 BAKED_VERSION，跳过 api.github.com 解析）"
}

# 关键：把二进制下载源 github.com -> 代理
$patched = $script.Replace('https://github.com/', "$GHProxy/https://github.com/")

$tmp = Join-Path $env:TEMP ('cua-driver-install-cn-' + [Guid]::NewGuid().ToString('N') + '.ps1')
[System.IO.File]::WriteAllText($tmp, $patched, [System.Text.UTF8Encoding]::new($false))
W-Ok "打补丁后的安装器: $tmp"

W-Info '执行 cua-driver 安装（二进制走 GitHub 代理）...'
Write-Host ''
try {
    & $tmp
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

# 官方安装器只更新注册表 PATH；手动补当前会话 PATH，让同进程的 hermes 能检测到
if ((Test-Path $binDir) -and (($env:Path -split ';') -notcontains $binDir)) {
    $env:Path = "$binDir;$env:Path"
}
Write-Host ''
$ok = Get-Command cua-driver -ErrorAction SilentlyContinue
if ($ok) { W-Ok "cua-driver 就绪: $($ok.Source)" }
else { W-Warn 'cua-driver 已安装但当前会话 PATH 未生效；开新终端或重跑 hermes 安装器即可识别' }
