# ============================================================
# Windows 磁盘空间清理脚本
# 用法: 右键 -> 以管理员身份运行，或在管理员 PowerShell 中执行:
#   .\cleanup_disk.ps1              # 交互模式
#   .\cleanup_disk.ps1 -Auto        # 全自动模式
#   .\cleanup_disk.ps1 -DryRun      # 仅预览
#   .\cleanup_disk.ps1 -TargetDrive D  # 指定磁盘（默认 C）
# ============================================================

param(
    [switch]$Auto,
    [switch]$DryRun,
    [string]$TargetDrive = "C"
)

# ---------- 需要管理员权限 ----------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[错误] 请以管理员身份运行此脚本！" -ForegroundColor Red
    Write-Host "右键点击 PowerShell -> 以管理员身份运行" -ForegroundColor Yellow
    pause
    exit 1
}

# ---------- 执行策略放行（本次会话） ----------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ---------- 工具函数 ----------
function Write-Section($title) {
    Write-Host ""
    Write-Host ("=" * 46) -ForegroundColor Blue
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host ("=" * 46) -ForegroundColor Blue
}

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERR]   $msg" -ForegroundColor Red }

function Format-Size($bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Get-FolderSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    try {
        return (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch { return 0 }
}

function Confirm-Action($prompt) {
    if ($Auto) { return $true }
    $ans = Read-Host "[?] $prompt [y/N]"
    return $ans -match '^[Yy]$'
}

function Invoke-Cleanup($path, $filter = "*", $recurse = $true) {
    if (-not (Test-Path $path)) { return 0 }
    $before = Get-FolderSize $path
    if ($DryRun) {
        Write-Warn "[DRY-RUN] 将清理: $path\$filter"
        return $before
    }
    try {
        if ($recurse) {
            Get-ChildItem $path -Include $filter -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem $path -Filter $filter -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    $after = Get-FolderSize $path
    return [math]::Max(0, $before - $after)
}

$script:TotalFreed = 0
function Add-Freed($bytes) { $script:TotalFreed += $bytes }

# ──────────────────────────────────────────
# 开始
# ──────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║      Windows 磁盘空间清理工具             ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) { Write-Warn "DRY-RUN 模式：仅预览，不实际删除任何文件" }

# 清理前磁盘状态
Write-Section "清理前磁盘使用情况"
$drive = Get-PSDrive -Name $TargetDrive -ErrorAction SilentlyContinue
if ($null -eq $drive) {
    Write-Err "找不到驱动器 ${TargetDrive}:，请检查 -TargetDrive 参数"
    exit 1
}
$usedBefore = $drive.Used
$freeBefore  = $drive.Free
Write-Host ("  驱动器 {0}:  已用 {1}  可用 {2}  共 {3}" -f `
    $TargetDrive,
    (Format-Size $usedBefore),
    (Format-Size $freeBefore),
    (Format-Size ($usedBefore + $freeBefore))) -ForegroundColor White

# ──────────────────────────────────────────
# 1. 用户临时文件
# ──────────────────────────────────────────
Write-Section "1. 用户临时文件（%TEMP%）"
$userTemp = $env:TEMP
$sz = Get-FolderSize $userTemp
Write-Info "当前大小: $(Format-Size $sz)  路径: $userTemp"
if (Confirm-Action "清理用户临时文件？") {
    $freed = Invoke-Cleanup $userTemp
    Add-Freed $freed
    Write-Ok "释放约 $(Format-Size $freed)"
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 2. 系统临时文件
# ──────────────────────────────────────────
Write-Section "2. 系统临时文件（C:\Windows\Temp）"
$sysTemp = "$($TargetDrive):\Windows\Temp"
$sz = Get-FolderSize $sysTemp
Write-Info "当前大小: $(Format-Size $sz)"
if (Confirm-Action "清理系统临时文件？") {
    $freed = Invoke-Cleanup $sysTemp
    Add-Freed $freed
    Write-Ok "释放约 $(Format-Size $freed)"
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 3. 回收站
# ──────────────────────────────────────────
Write-Section "3. 回收站"
if (Confirm-Action "清空回收站？") {
    if (-not $DryRun) {
        try {
            Clear-RecycleBin -DriveLetter $TargetDrive -Force -ErrorAction SilentlyContinue
            Write-Ok "回收站已清空"
        } catch { Write-Warn "清空回收站时出错（可能已为空）" }
    } else {
        Write-Warn "[DRY-RUN] 将清空回收站"
    }
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 4. Windows Update 缓存
# ──────────────────────────────────────────
Write-Section "4. Windows Update 缓存（SoftwareDistribution\Download）"
$wuCache = "$($TargetDrive):\Windows\SoftwareDistribution\Download"
$sz = Get-FolderSize $wuCache
Write-Info "当前大小: $(Format-Size $sz)"
if (Confirm-Action "清理 Windows Update 下载缓存？（需停止 wuauserv 服务）") {
    if (-not $DryRun) {
        Write-Info "停止 Windows Update 服务..."
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $freed = Invoke-Cleanup $wuCache
        Add-Freed $freed
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-Ok "释放约 $(Format-Size $freed)，服务已重启"
    } else {
        Write-Warn "[DRY-RUN] 将清理 $wuCache"
    }
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 5. 缩略图缓存
# ──────────────────────────────────────────
Write-Section "5. 缩略图缓存（Thumbcache）"
$thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$thumbFiles = Get-ChildItem $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue
$sz = ($thumbFiles | Measure-Object -Property Length -Sum).Sum
Write-Info "缩略图缓存大小: $(Format-Size $sz)"
if (Confirm-Action "清理缩略图缓存？（Explorer 会自动重建）") {
    if (-not $DryRun) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $thumbFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Start-Process explorer
        Add-Freed ([long]$sz)
        Write-Ok "释放约 $(Format-Size $sz)"
    } else {
        Write-Warn "[DRY-RUN] 将删除 $($thumbFiles.Count) 个缩略图缓存文件"
    }
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 6. 预读取文件（Prefetch）
# ──────────────────────────────────────────
Write-Section "6. 预读取文件（Prefetch）"
$prefetchPath = "$($TargetDrive):\Windows\Prefetch"
$sz = Get-FolderSize $prefetchPath
Write-Info "当前大小: $(Format-Size $sz)"
if (Confirm-Action "清理 Prefetch 文件？（系统会自动重建，短时间内冷启动稍慢）") {
    $freed = Invoke-Cleanup $prefetchPath "*.pf"
    Add-Freed $freed
    Write-Ok "释放约 $(Format-Size $freed)"
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 7. 浏览器缓存
# ──────────────────────────────────────────
Write-Section "7. 浏览器缓存"

$browsers = @{
    "Chrome"  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data"
    "Edge"    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data"
    "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
}

foreach ($name in $browsers.Keys) {
    $bPath = $browsers[$name]
    if (Test-Path $bPath) {
        $sz = Get-FolderSize $bPath
        Write-Info "$name 缓存: $(Format-Size $sz)"
        if ($sz -gt 0 -and (Confirm-Action "清理 $name 缓存？")) {
            $freed = Invoke-Cleanup $bPath
            Add-Freed $freed
            Write-Ok "$name 释放约 $(Format-Size $freed)"
        }
    }
}

# ──────────────────────────────────────────
# 8. 系统还原点（保留最新一个）
# ──────────────────────────────────────────
Write-Section "8. 系统还原点（保留最新一个）"
Write-Info "检查还原点占用..."
if (Confirm-Action "删除旧还原点，仅保留最新一个？（不可逆）") {
    if (-not $DryRun) {
        try {
            $result = & vssadmin delete shadows /for=${TargetDrive}: /oldest /quiet 2>&1
            Write-Ok "旧还原点已删除"
        } catch { Write-Warn "操作失败或没有旧还原点" }
    } else {
        Write-Warn "[DRY-RUN] 将删除旧还原点"
    }
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 9. Windows 磁盘清理工具（cleanmgr）
# ──────────────────────────────────────────
Write-Section "9. Windows 内置磁盘清理（cleanmgr）"
Write-Info "可清理：传递优化文件、设备驱动缓存、WinSxS 旧组件等"
if (Confirm-Action "运行 cleanmgr 自动静默清理？（/sagerun:1）") {
    if (-not $DryRun) {
        Write-Info "预设清理项目..."
        # 预设所有 StateFlags0001 为 2（选中所有项）
        $regBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem $regBase -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty $_.PSPath -Name StateFlags0001 -Value 2 -ErrorAction SilentlyContinue
        }
        Write-Info "正在运行 cleanmgr，请稍候（可能需要几分钟）..."
        Start-Process cleanmgr -ArgumentList "/sagerun:1 /d $($TargetDrive):" -Wait -NoNewWindow
        Write-Ok "cleanmgr 清理完成"
    } else {
        Write-Warn "[DRY-RUN] 将运行 cleanmgr /sagerun:1"
    }
} else { Write-Warn "跳过" }

# ──────────────────────────────────────────
# 10. pip / npm 缓存（如已安装）
# ──────────────────────────────────────────
Write-Section "10. 开发工具缓存（pip / npm）"

if (Get-Command pip -ErrorAction SilentlyContinue) {
    $pipCacheDir = & pip cache dir 2>$null
    if ($pipCacheDir -and (Test-Path $pipCacheDir)) {
        $sz = Get-FolderSize $pipCacheDir
        Write-Info "pip 缓存: $(Format-Size $sz)"
        if (Confirm-Action "清理 pip 缓存？") {
            if (-not $DryRun) { & pip cache purge 2>$null }
            else { Write-Warn "[DRY-RUN] pip cache purge" }
            Write-Ok "pip 缓存已清理"
        }
    }
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmCache = & npm config get cache 2>$null
    if ($npmCache -and (Test-Path $npmCache)) {
        $sz = Get-FolderSize $npmCache
        Write-Info "npm 缓存: $(Format-Size $sz)"
        if (Confirm-Action "清理 npm 缓存？") {
            if (-not $DryRun) { & npm cache clean --force 2>$null }
            else { Write-Warn "[DRY-RUN] npm cache clean --force" }
            Write-Ok "npm 缓存已清理"
        }
    }
}

# ──────────────────────────────────────────
# 汇总
# ──────────────────────────────────────────
Write-Section "清理完成 — 磁盘使用情况"
$drive = Get-PSDrive -Name $TargetDrive
$usedAfter = $drive.Used
$freeAfter  = $drive.Free
$actualFreed = $freeAfter - $freeBefore

Write-Host ""
Write-Host ("  驱动器 {0}:  已用 {1}  可用 {2}  共 {3}" -f `
    $TargetDrive,
    (Format-Size $usedAfter),
    (Format-Size $freeAfter),
    (Format-Size ($usedAfter + $freeAfter))) -ForegroundColor White

Write-Host ""
if ($actualFreed -gt 0) {
    Write-Host ("  实际新增可用空间: {0}" -f (Format-Size $actualFreed)) -ForegroundColor Green
} elseif ($DryRun) {
    Write-Warn "DRY-RUN 模式，未实际删除文件。去掉 -DryRun 参数重新运行以执行清理。"
} else {
    Write-Host "  磁盘空间无明显变化（可能已是最优状态）" -ForegroundColor Yellow
}

Write-Host ""
pause
