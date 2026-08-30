# ============================================================================
#  ripgrep + ffmpeg 便携版预装（国内镜像）—— install-rg-ffmpeg-cn.ps1
# ============================================================================
#  作用：把便携版 rg.exe / ffmpeg.exe 装到 %LOCALAPPDATA%\hermes\bin 并加入
#        用户 PATH。这样 Hermes 安装器的 "Checking ripgrep / ffmpeg" 会直接
#        命中 Get-Command，从而【跳过国内卡死的 winget 步骤】。
#
#  原理：Hermes 安装器对 rg/ffmpeg 仅做 Get-Command 检测——只要 PATH 上有，
#        整个 winget 安装分支被跳过（脚本里 `if (-not $needRipgrep -and -not
#        $needFfmpeg) { return }`）。所以预置二进制即可完全绕开 winget。
#
#  用法（PowerShell，任意目录）：
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-rg-ffmpeg-cn.ps1"
#
#  换 GitHub 代理：
#    $env:HERMES_CN_GH_PROXY = "https://gh-proxy.org"
#    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\HermesCN\install-rg-ffmpeg-cn.ps1"
# ============================================================================

param(
    [string]$GHProxy = $(if ($env:HERMES_CN_GH_PROXY) { $env:HERMES_CN_GH_PROXY } else { 'https://gh-proxy.com' }),
    [string]$BinDir = (Join-Path $env:LOCALAPPDATA 'hermes\bin'),
    [string]$RipgrepVersion = '14.1.1'   # 失效时可改 14.1.0 / 14.0.3 / 13.0.0
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # 关进度条（PS 5.1 下提速 10~100 倍）
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }
$GHProxy = $GHProxy.TrimEnd('/')

function W-Info ($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function W-Ok   ($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function W-Warn ($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

function Add-DirToUserPath {
    param([string]$Dir)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @(($userPath -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts -contains $Dir) { W-Ok "$Dir 已在用户 PATH 中"; return }
    [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
    W-Ok "已加入用户 PATH: $Dir"
}

# --- 1) ripgrep（BurntSushi 官方 Windows 便携包，经 GitHub 代理）---
W-Info "预装 ripgrep $RipgrepVersion 便携版（经 $GHProxy，约 2MB）..."
$rgZip = "ripgrep-$RipgrepVersion-x86_64-pc-windows-msvc.zip"
$rgUrl = "$GHProxy/https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/$rgZip"
$rgTmp = Join-Path $env:TEMP $rgZip
$rgExt = Join-Path $env:TEMP 'hermes-rg-extract'
Invoke-WebRequest -Uri $rgUrl -OutFile $rgTmp -UseBasicParsing
if (Test-Path $rgExt) { Remove-Item -Recurse -Force $rgExt }
Expand-Archive -Path $rgTmp -DestinationPath $rgExt -Force
$rgExe = Get-ChildItem -Path $rgExt -Recurse -Filter 'rg.exe' | Select-Object -First 1
if (-not $rgExe) { throw "ripgrep zip 内未找到 rg.exe（版本 $RipgrepVersion 可能已下架，请改 -RipgrepVersion）" }
Copy-Item $rgExe.FullName (Join-Path $BinDir 'rg.exe') -Force
Remove-Item $rgTmp, $rgExt -Recurse -Force -ErrorAction SilentlyContinue
W-Ok ("ripgrep -> {0}\rg.exe  ({1})" -f $BinDir, (& (Join-Path $BinDir 'rg.exe') --version | Select-Object -First 1))

# --- 2) ffmpeg（BtbN/FFmpeg-Builds，master-latest 稳定资产名，永远指向最新构建）---
W-Info '预装 ffmpeg 便携版（BtbN 最新构建，经 GitHub 代理，约 90~110MB，请耐心等待）...'
$ffZip = 'ffmpeg-master-latest-win64-gpl.zip'
$ffUrl = "$GHProxy/https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$ffZip"
$ffTmp = Join-Path $env:TEMP $ffZip
$ffExt = Join-Path $env:TEMP 'hermes-ff-extract'
Invoke-WebRequest -Uri $ffUrl -OutFile $ffTmp -UseBasicParsing
if (Test-Path $ffExt) { Remove-Item -Recurse -Force $ffExt }
Expand-Archive -Path $ffTmp -DestinationPath $ffExt -Force
foreach ($name in 'ffmpeg.exe', 'ffprobe.exe', 'ffplay.exe') {
    $f = Get-ChildItem -Path $ffExt -Recurse -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { Copy-Item $f.FullName (Join-Path $BinDir $name) -Force }
}
if (-not (Test-Path (Join-Path $BinDir 'ffmpeg.exe'))) { throw 'ffmpeg zip 内未找到 ffmpeg.exe' }
Remove-Item $ffTmp, $ffExt -Recurse -Force -ErrorAction SilentlyContinue
W-Ok ("ffmpeg -> {0}\ffmpeg.exe  ({1})" -f $BinDir, (& (Join-Path $BinDir 'ffmpeg.exe') -version | Select-Object -First 1))

# --- 3) 加入用户 PATH（持久 + 当前会话）---
Add-DirToUserPath $BinDir
if (($env:Path -split ';') -notcontains $BinDir) { $env:Path = "$BinDir;$env:Path" }

Write-Host ''
Write-Host '完成。现在可重新运行 Hermes 安装器，ripgrep/ffmpeg 检查会命中、跳过 winget。' -ForegroundColor Green
Write-Host "  rg.exe / ffmpeg.exe 位置: $BinDir" -ForegroundColor DarkGray
