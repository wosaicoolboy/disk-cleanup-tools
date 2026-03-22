# 🧹 磁盘空间清理工具套件

> 适用于 **Ubuntu Linux** 和 **Windows** 的磁盘空间清理脚本，支持交互确认、全自动、预览三种运行模式。

---

## 📦 文件说明

| 文件 | 适用系统 | 说明 |
|------|---------|------|
| `cleanup_disk.sh` | Ubuntu / Debian Linux | Bash 脚本，需 sudo 权限 |
| `cleanup_disk.ps1` | Windows 10 / 11 | PowerShell 脚本，需管理员权限 |

---

## 🐧 Ubuntu 版（cleanup_disk.sh）

### 环境要求

- Ubuntu 18.04 及以上（或其他 Debian 系发行版）
- 需要 `sudo` / root 权限
- 依赖工具：`bash`、`apt`、`du`、`find`、`bc`（系统默认均已安装）

### 使用方法

```bash
# 1. 赋予执行权限
chmod +x cleanup_disk.sh

# 2. 交互模式（推荐首次使用）
sudo bash cleanup_disk.sh

# 3. 仅预览，不实际删除
sudo bash cleanup_disk.sh --dry-run

# 4. 全自动模式，跳过所有确认
sudo bash cleanup_disk.sh --auto

# 5. 查看帮助
sudo bash cleanup_disk.sh --help
```

### 清理项目

| # | 清理内容 | 默认行为 | 说明 |
|---|---------|---------|------|
| 1 | APT 包缓存 | 询问 | `apt-get clean` + `autoclean` |
| 2 | 孤立依赖包 | 询问 | `apt-get autoremove` |
| 3 | 旧版内核 | 询问 | 保留当前运行内核，删除其余版本 |
| 4 | 系统日志 | 询问 | 保留最近 2 周 journal 日志，清理 `.gz` 旧日志 |
| 5 | `/tmp` 临时文件 | 询问 | 删除超过 7 天未访问的文件 |
| 6 | Snap 旧版本 | 询问 | 删除 disabled 状态的旧版 Snap 包 |
| 7 | Docker 资源 | 询问 | 清理悬空镜像、停止的容器（需已安装 Docker）|
| 8 | pip 缓存 | 询问 | `pip cache purge`（需已安装 pip）|
| 9 | npm 缓存 | 询问 | `npm cache clean --force`（需已安装 npm）|

### 注意事项

- ⚠️ **旧内核清理**：脚本会自动识别当前运行内核并跳过，仅删除其他版本，操作安全。
- ⚠️ **Docker 清理**：`docker image prune -af` 会删除**所有未被容器引用的镜像**，请确认不再需要后执行。
- ✅ `--dry-run` 模式不会删除任何文件，可放心用于预览。

---

## 🪟 Windows 版（cleanup_disk.ps1）

### 环境要求

- Windows 10 / 11
- PowerShell 5.1 及以上（系统自带）
- 需要**管理员权限**运行

### 使用方法

**方式一：右键运行（推荐）**
1. 右键点击 `cleanup_disk.ps1`
2. 选择 **"以管理员身份运行"**

**方式二：在管理员 PowerShell 中执行**

```powershell
# 交互模式（推荐首次使用）
.\cleanup_disk.ps1

# 仅预览，不实际删除
.\cleanup_disk.ps1 -DryRun

# 全自动模式，跳过所有确认
.\cleanup_disk.ps1 -Auto

# 指定清理 D 盘（默认为 C 盘）
.\cleanup_disk.ps1 -TargetDrive D

# 组合参数
.\cleanup_disk.ps1 -Auto -TargetDrive D
```

> 💡 如提示"此系统禁止运行脚本"，脚本内部已自动设置本次会话的执行策略，无需手动修改系统设置。

### 清理项目

| # | 清理内容 | 默认行为 | 说明 |
|---|---------|---------|------|
| 1 | 用户临时文件 `%TEMP%` | 询问 | 通常是最大的垃圾来源 |
| 2 | 系统临时文件 `C:\Windows\Temp` | 询问 | 需管理员权限 |
| 3 | 回收站 | 询问 | 彻底清空指定驱动器回收站 |
| 4 | Windows Update 缓存 | 询问 | 自动停止并重启 `wuauserv` 服务后清理 |
| 5 | 缩略图缓存 | 询问 | Explorer 会在下次访问时自动重建 |
| 6 | Prefetch 预读取文件 | 询问 | 系统自动重建，短时间内冷启动稍慢 |
| 7 | 浏览器缓存 | 询问 | 自动检测 Chrome / Edge / Firefox |
| 8 | 旧系统还原点 | 询问 | 仅保留最新一个还原点（不可逆）|
| 9 | 内置磁盘清理 `cleanmgr` | 询问 | 含传递优化文件、WinSxS 旧组件等 |
| 10 | pip / npm 开发缓存 | 询问 | 检测到已安装时自动提示 |

### 注意事项

- ⚠️ **系统还原点**：删除旧还原点**不可逆**，建议在系统稳定时执行。
- ⚠️ **cleanmgr**：运行时会弹出进度窗口，属于正常现象，等待完成即可。
- ⚠️ **缩略图缓存**：清理过程中 Explorer 会短暂重启，桌面会闪烁，属正常现象。
- ✅ `-DryRun` 模式不会删除任何文件，可放心用于预览。

---

## 🔄 运行模式对比

| 模式 | Ubuntu 参数 | Windows 参数 | 说明 |
|------|------------|-------------|------|
| 交互模式 | （无参数） | （无参数） | 每步询问是否执行，**推荐首次使用** |
| 预览模式 | `--dry-run` | `-DryRun` | 仅显示将要清理的内容，不实际删除 |
| 全自动模式 | `--auto` | `-Auto` | 跳过所有确认，**适合计划任务** |

---

## ⏰ 设置定期自动清理（可选）

### Ubuntu — cron 定时任务

```bash
# 编辑 root 的 crontab
sudo crontab -e

# 每周日凌晨 3 点自动清理（追加以下行）
0 3 * * 0 /bin/bash /path/to/cleanup_disk.sh --auto >> /var/log/cleanup_disk.log 2>&1
```

### Windows — 任务计划程序

```powershell
# 每周日凌晨 3 点自动运行（在管理员 PowerShell 中执行）
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
           -Argument "-NonInteractive -File C:\path\to\cleanup_disk.ps1 -Auto"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfIdle:$false
Register-ScheduledTask -TaskName "DiskCleanup" -Action $action `
    -Trigger $trigger -Settings $settings -RunLevel Highest -Force
```

---

## ❓ 常见问题

**Q: Ubuntu 脚本只执行了第一步就停止了？**  
A: 确保使用最新版脚本（已修复 `set -e` 导致的静默退出问题）。旧版本中任何命令返回非零退出码都会终止整个脚本。

**Q: Windows 提示"无法加载文件，因为在此系统上禁止运行脚本"？**  
A: 在管理员 PowerShell 中先执行：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Q: 清理后系统变慢了？**  
A: Prefetch 和缩略图缓存清理后，系统需要一段时间重建，属于正常现象，重启后恢复正常。

**Q: Docker 镜像被误删了怎么办？**  
A: 可从镜像仓库重新拉取：`docker pull <镜像名>:<标签>`。建议清理前用 `docker images` 确认需要保留的镜像。

---

## 📄 许可

本工具套件以 MIT 许可证开源，可自由使用、修改和分发。
