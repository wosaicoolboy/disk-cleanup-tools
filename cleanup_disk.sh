#!/bin/bash
# ============================================================
# Ubuntu 磁盘空间清理脚本
# 用法: sudo bash cleanup_disk.sh [--dry-run] [--auto]
# ============================================================

set -uo pipefail  # 注意：不加 -e，避免单步失败终止整个脚本

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- 参数解析 ----------
DRY_RUN=false
AUTO=false

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --auto)    AUTO=true ;;
    --help)
      echo "用法: sudo bash $0 [--dry-run] [--auto]"
      echo "  --dry-run  仅预览，不实际执行清理"
      echo "  --auto     跳过所有确认提示，自动执行"
      exit 0
      ;;
  esac
done

# ---------- 权限检查 ----------
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[错误]${NC} 请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

# ---------- 工具函数 ----------
log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${NC}"; \
                echo -e "${BOLD}${BLUE}  $*${NC}"; \
                echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}"; }

# 字节转可读格式
human_size() {
  local bytes=$1
  if   (( bytes >= 1073741824 )); then printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc)"
  elif (( bytes >= 1048576 ));    then printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | bc)"
  elif (( bytes >= 1024 ));       then printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | bc)"
  else printf "%d B" "$bytes"
  fi
}

# 获取目录大小（字节）
dir_size_bytes() { du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0; }

# 确认提示（--auto 时直接返回 yes）
confirm() {
  if $AUTO; then return 0; fi
  echo -en "${YELLOW}[?]${NC} $* [y/N] "
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# 执行或预览命令
run_cmd() {
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

# 记录累计释放空间
TOTAL_FREED=0
record_freed() {
  local before=$1 after=$2
  local freed=$(( before - after ))
  (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
}

# ---------- 开始 ----------
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   Ubuntu 磁盘空间清理工具             ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

$DRY_RUN && log_warn "DRY-RUN 模式：仅预览，不实际删除任何文件"

# 显示清理前磁盘状态
log_section "清理前磁盘使用情况"
df -h /

# ──────────────────────────────────────────
# 1. APT 缓存清理
# ──────────────────────────────────────────
log_section "1. APT 包缓存清理"

APT_CACHE_BEFORE=$(dir_size_bytes /var/cache/apt/archives)
log_info "当前 APT 缓存大小: $(human_size $APT_CACHE_BEFORE)"

if confirm "清理 APT 包缓存？（apt-get clean + autoclean）"; then
  run_cmd "apt-get clean -y || true"
  run_cmd "apt-get autoclean -y || true"
  APT_CACHE_AFTER=$(dir_size_bytes /var/cache/apt/archives)
  record_freed $APT_CACHE_BEFORE $APT_CACHE_AFTER
  log_ok "APT 缓存清理完成，释放约 $(human_size $(( APT_CACHE_BEFORE - APT_CACHE_AFTER )))"
else
  log_warn "跳过 APT 缓存清理"
fi

# ──────────────────────────────────────────
# 2. 自动删除不需要的依赖包
# ──────────────────────────────────────────
log_section "2. 删除无用依赖包（autoremove）"

AUTOREMOVE_LIST=$(apt-get --dry-run autoremove 2>/dev/null | grep "^Remv" | awk '{print $2}' || true)
if [[ -n "$AUTOREMOVE_LIST" ]]; then
  COUNT=$(echo "$AUTOREMOVE_LIST" | wc -l)
  log_info "发现 ${COUNT} 个可删除的孤立包："
  echo "$AUTOREMOVE_LIST" | head -20 | sed 's/^/    /'
  (( COUNT > 20 )) && echo "    ... 以及另外 $(( COUNT - 20 )) 个"

  if confirm "执行 apt-get autoremove 删除以上包？"; then
    run_cmd "apt-get autoremove -y || true"
    log_ok "孤立包清理完成"
  else
    log_warn "跳过孤立包清理"
  fi
else
  log_ok "没有需要清理的孤立包"
fi

# ──────────────────────────────────────────
# 3. 旧内核清理
# ──────────────────────────────────────────
log_section "3. 旧内核清理"

CURRENT_KERNEL=$(uname -r)
log_info "当前运行内核: $CURRENT_KERNEL"

OLD_KERNELS=$(dpkg -l 'linux-image-*' 'linux-headers-*' 'linux-modules-*' 2>/dev/null \
  | awk '/^ii/{print $2}' \
  | grep -v "$CURRENT_KERNEL" \
  | grep -v "linux-image-generic" \
  | grep -v "linux-headers-generic" \
  || true)

if [[ -n "$OLD_KERNELS" ]]; then
  log_info "发现以下旧内核包："
  echo "$OLD_KERNELS" | sed 's/^/    /'
  if confirm "删除以上旧内核包？（当前内核不受影响）"; then
    run_cmd "apt-get purge -y $OLD_KERNELS || true"
    run_cmd "apt-get autoremove -y || true"
    log_ok "旧内核清理完成"
  else
    log_warn "跳过旧内核清理"
  fi
else
  log_ok "没有发现旧内核需要清理"
fi

# ──────────────────────────────────────────
# 4. 系统日志清理
# ──────────────────────────────────────────
log_section "4. 系统日志清理（journald）"

if command -v journalctl &>/dev/null; then
  JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+\s*[KMGT]?B' | head -1 || echo "未知")
  log_info "当前 journal 日志占用: $JOURNAL_SIZE"

  if confirm "清理 2 周前的 journal 日志？"; then
    run_cmd "journalctl --vacuum-time=2weeks"
    log_ok "journal 日志清理完成"
  else
    log_warn "跳过 journal 日志清理"
  fi
fi

# /var/log 下的旧压缩日志
LOG_GZ_SIZE=$(find /var/log -name "*.gz" -type f 2>/dev/null | xargs du -sb 2>/dev/null | awk '{s+=$1}END{print s+0}')
if (( LOG_GZ_SIZE > 0 )); then
  log_info "发现压缩日志文件，占用: $(human_size $LOG_GZ_SIZE)"
  if confirm "删除 /var/log 下的已压缩日志文件（*.gz）？"; then
    run_cmd "find /var/log -name '*.gz' -type f -delete"
    log_ok "压缩日志清理完成"
  fi
fi

# ──────────────────────────────────────────
# 5. 临时文件清理
# ──────────────────────────────────────────
log_section "5. 临时文件清理"

TMP_SIZE=$(dir_size_bytes /tmp)
log_info "/tmp 当前大小: $(human_size $TMP_SIZE)"

if confirm "清理 /tmp 下超过 7 天的文件？"; then
  run_cmd "find /tmp -type f -atime +7 -delete 2>/dev/null || true"
  run_cmd "find /tmp -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true"
  log_ok "/tmp 旧文件清理完成"
else
  log_warn "跳过 /tmp 清理"
fi

# ──────────────────────────────────────────
# 6. Snap 包旧版本清理
# ──────────────────────────────────────────
if command -v snap &>/dev/null; then
  log_section "6. Snap 旧版本清理"

  SNAP_OLD=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' || true)
  if [[ -n "$SNAP_OLD" ]]; then
    log_info "发现以下 Snap 旧版本："
    echo "$SNAP_OLD" | sed 's/^/    /'
    if confirm "删除以上 Snap 旧版本？"; then
      snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
        run_cmd "snap remove '$snapname' --revision='$revision'"
      done
      log_ok "Snap 旧版本清理完成"
    else
      log_warn "跳过 Snap 旧版本清理"
    fi
  else
    log_ok "没有 Snap 旧版本需要清理"
  fi
fi

# ──────────────────────────────────────────
# 7. Docker 清理（如已安装）
# ──────────────────────────────────────────
if command -v docker &>/dev/null; then
  log_section "7. Docker 资源清理"

  DOCKER_SIZE=$(docker system df 2>/dev/null | tail -n +2 | awk '{print $4}' | paste -sd+ | bc 2>/dev/null || echo "未知")
  log_info "Docker 可回收空间预估请运行: docker system df"

  if confirm "执行 docker system prune（删除未使用的容器、网络、悬空镜像）？"; then
    run_cmd "docker system prune -f"
    log_ok "Docker 基础清理完成"
  fi

  if confirm "同时删除所有未使用的 Docker 镜像（包括未被容器引用的）？"; then
    run_cmd "docker image prune -af"
    log_ok "Docker 镜像清理完成"
  fi
fi

# ──────────────────────────────────────────
# 8. pip 缓存清理（如存在）
# ──────────────────────────────────────────
if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
  log_section "8. pip 缓存清理"

  PIP_CMD=$(command -v pip3 || command -v pip)
  PIP_CACHE=$($PIP_CMD cache dir 2>/dev/null || echo "")
  if [[ -n "$PIP_CACHE" && -d "$PIP_CACHE" ]]; then
    PIP_SIZE=$(dir_size_bytes "$PIP_CACHE")
    log_info "pip 缓存大小: $(human_size $PIP_SIZE)"
    if confirm "清理 pip 缓存？"; then
      run_cmd "$PIP_CMD cache purge"
      log_ok "pip 缓存清理完成"
    fi
  fi
fi

# ──────────────────────────────────────────
# 9. npm 缓存清理（如存在）
# ──────────────────────────────────────────
if command -v npm &>/dev/null; then
  log_section "9. npm 缓存清理"
  NPM_CACHE=$(npm config get cache 2>/dev/null || echo "")
  if [[ -n "$NPM_CACHE" && -d "$NPM_CACHE" ]]; then
    NPM_SIZE=$(dir_size_bytes "$NPM_CACHE")
    log_info "npm 缓存大小: $(human_size $NPM_SIZE)"
    if confirm "清理 npm 缓存？"; then
      run_cmd "npm cache clean --force"
      log_ok "npm 缓存清理完成"
    fi
  fi
fi

# ──────────────────────────────────────────
# 汇总报告
# ──────────────────────────────────────────
log_section "清理完成 — 磁盘使用情况"
df -h /
echo ""

if $DRY_RUN; then
  log_warn "DRY-RUN 模式，未实际删除任何文件。去掉 --dry-run 参数后重新运行以执行清理。"
else
  log_ok "全部清理任务完成！"
fi

echo ""
