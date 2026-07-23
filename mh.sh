#!/bin/sh

set -u

SCRIPT_AUTHOR="oKafuChino"
SCRIPT_OPTIMIZER="TANYING"
SCRIPT_VERSION="1.12.4-argo.17"
BIN_PATH="/usr/local/bin/mihomo"
BIN_BACKUP_PATH="/usr/local/bin/mihomo.previous"
CLI_PATH="/usr/local/bin/mh"
CLI_BACKUP_PATH="/usr/local/bin/mh.previous"
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
CONFIG_BACKUP_FILE="$CONFIG_DIR/config.yaml.previous"
CONFIG_PENDING_FILE="$CONFIG_DIR/.config-pending"
DNS_STATE_FILE="$CONFIG_DIR/dns.state"
DNS_TEST_NAME="${MIHOMO_DNS_TEST_NAME:-www.cloudflare.com}"
OOM_STATE_FILE="$CONFIG_DIR/oom.state"
STATE_LOCK_DIR="$CONFIG_DIR/state.lock"
NODES_DB="$CONFIG_DIR/nodes.db"
USERS_DB="$CONFIG_DIR/users.db"
TRAFFIC_DB="$CONFIG_DIR/traffic.db"
TRAFFIC_RULES_VERSION_FILE="$CONFIG_DIR/traffic-rules.version"
TRAFFIC_RULES_VERSION="2"
TRAFFIC_CHAIN="MIHOMO_LITE_USERS"
TRAFFIC_CHAIN_IN="${TRAFFIC_CHAIN}_IN"
TRAFFIC_CHAIN_OUT="${TRAFFIC_CHAIN}_OUT"
TRAFFIC_CRON_MARK="mihomo-lite-traffic-auto"
TRAFFIC_LOCK_DIR="$CONFIG_DIR/traffic.lock"
PUBLIC_IP_CACHE_TTL="${MIHOMO_PUBLIC_IP_CACHE_TTL:-21600}"
LOG_DIR="/var/log/mihomo"
SERVICE_NAME="mihomo"
RUNTIME_ENV_FILE="$CONFIG_DIR/runtime.env"
NETWORK_ENV_FILE="$CONFIG_DIR/network.env"
FEATURES_ENV_FILE="$CONFIG_DIR/features.env"
MULTI_USER_FLAG="$CONFIG_DIR/multi-user.enabled"
PUBLIC_IP_CACHE_FILE="$CONFIG_DIR/public.ip"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-mihomo-lite.conf"
SYSCTL_BACKUP_FILE="$CONFIG_DIR/sysctl.previous"
MIHOMO_GOMEMLIMIT="${MIHOMO_GOMEMLIMIT:-}"
MIHOMO_GOGC="${MIHOMO_GOGC:-}"
MIHOMO_GOMAXPROCS="${MIHOMO_GOMAXPROCS:-}"
MIHOMO_GODEBUG_DEFAULT="madvdontneed=1"
MIHOMO_GODEBUG="${MIHOMO_GODEBUG:-}"
MIHOMO_IPV6="${MIHOMO_IPV6:-}"
MIHOMO_PREFER_IPV6="${MIHOMO_PREFER_IPV6:-}"
MIHOMO_MULTI_USER="${MIHOMO_MULTI_USER:-}"
HY2_UP_MBPS=10000
HY2_DOWN_MBPS=10000
GITHUB_API="${MIHOMO_GITHUB_API:-https://api.github.com/repos/MetaCubeX/mihomo/releases/latest}"
SCRIPT_RAW_URL="${MH_SCRIPT_RAW_URL:-https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/main/mh.sh}"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
CLOUDFLARED_BACKUP_BIN="/usr/local/bin/cloudflared.previous"
CLOUDFLARED_CONFIG_DIR="/etc/cloudflared"
CLOUDFLARED_TOKEN_FILE="$CLOUDFLARED_CONFIG_DIR/token"
CLOUDFLARED_RUNNER="/usr/local/sbin/cloudflared-tunnel-run"
CLOUDFLARED_SERVICE="cloudflared-tunnel"
CLOUDFLARED_LOG="/var/log/cloudflared-tunnel.log"
CLOUDFLARED_METRICS="127.0.0.1:20241"
CLOUDFLARED_METRICS_URL="http://127.0.0.1:20241/metrics"
TUNNEL_WATCHDOG_CRON_MARK="mihomo-lite-tunnel-watchdog"
TUNNEL_WATCHDOG_STATE="$CLOUDFLARED_CONFIG_DIR/watchdog.state"
TUNNEL_WATCHDOG_LOCK="$CLOUDFLARED_CONFIG_DIR/watchdog.lock"
TUNNEL_WATCHDOG_LOG="$LOG_DIR/tunnel-watchdog.log"
LOGROTATE_FILE="/etc/logrotate.d/mihomo-lite"

red() { printf '\033[31m%s\033[0m\n' "$*"; }

C_CYAN=$(printf '\033[1;36m')
C_GREEN=$(printf '\033[1;32m')
C_YELLOW=$(printf '\033[1;33m')
C_PURPLE=$(printf '\033[1;35m')
C_RED=$(printf '\033[1;31m')
C_BOLD=$(printf '\033[1m')
C_RESET=$(printf '\033[0m')

ui_line() { printf '%s====================================================%s\n' "$C_CYAN" "$C_RESET"; }
ui_dash() { printf '%s----------------------------------------------------%s\n' "$C_CYAN" "$C_RESET"; }
ui_title() {
  ui_line
  printf ' [*] %s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
  ui_line
}
screen_title() {
  clear 2>/dev/null || true
  ui_title "$1"
}
ui_section() { printf ' %s[+] %s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
ui_prompt() { printf '%s%s%s' "$C_BOLD" "$1" "$C_RESET"; }
ui_success() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
ui_warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
ui_error() { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$1"; }

need_root() {
  if [ "$(id -u)" != "0" ]; then
    red "此操作需要 root 权限。"
    if command -v sudo >/dev/null 2>&1; then
      red "请执行：sudo mh ${1:-}"
    else
      red "当前系统没有 sudo。请先执行 su - 切换到 root，再运行 mh。"
    fi
    exit 1
  fi
}

pause() {
  printf '\n'
  ui_prompt "按回车返回菜单..."
  read -r _ || true
}

detect_os() {
  if [ ! -r /etc/os-release ]; then
    red "无法识别系统：缺少 /etc/os-release"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="${ID:-}"
  os_version="${VERSION_ID:-0}"
  os_major="${os_version%%.*}"

  case "$os_id" in
    ubuntu)
      if [ "${os_major:-0}" -lt 22 ]; then
        red "当前 Ubuntu 版本为 $os_version，本脚本要求 Ubuntu 22+。"
        exit 1
      fi
      ;;
    debian)
      if [ "${os_major:-0}" -lt 12 ]; then
        red "当前 Debian 版本为 $os_version，本脚本要求 Debian 12+。"
        exit 1
      fi
      ;;
    alpine)
      ;;
    *)
      red "暂不支持当前系统：$os_id。支持 Ubuntu 22+、Debian 12+、Alpine。"
      exit 1
      ;;
  esac
}

service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    printf 'systemd'
  elif command -v rc-service >/dev/null 2>&1; then
    printf 'openrc'
  else
    printf 'unknown'
  fi
}

service_status_text() {
  if [ ! -x "$BIN_PATH" ] || [ ! -f "$CONFIG_FILE" ]; then
    printf '未安装'
    return 0
  fi

  manager="$(service_manager)"
  case "$manager" in
    systemd)
      if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        printf '运行中'
      else
        printf '未运行'
      fi
      ;;
    openrc)
      if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
        printf '运行中'
      else
        printf '未运行'
      fi
      ;;
    *)
      printf '未知'
      ;;
  esac
}

install_packages() {
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates "$@" >/dev/null
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates "$@"
  else
    red "未找到 apk 或 apt-get，无法自动安装依赖。"
    exit 1
  fi
}

ensure_curl() {
  command -v curl >/dev/null 2>&1 || install_packages curl
}

sha256_file() {
  checksum_file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$checksum_file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$checksum_file" | awk '{print $NF}'
  else
    return 1
  fi
}

verify_remote_checksum() {
  checksum_url="$1"
  checksum_target="$2"
  checksum_tmp="$(make_temp /tmp/mh-checksum.XXXXXX)"
  if ! curl -fsSL --max-time 15 "${checksum_url}.sha256" -o "$checksum_tmp"; then
    rm -f "$checksum_tmp"
    ui_warn "上游未提供 SHA-256 sidecar，继续使用格式与可执行性检查。"
    return 2
  fi
  expected_checksum="$(awk 'NR == 1 { print $1 }' "$checksum_tmp" | tr 'A-F' 'a-f')"
  actual_checksum="$(sha256_file "$checksum_target" 2>/dev/null | tr 'A-F' 'a-f' || true)"
  rm -f "$checksum_tmp"
  case "$expected_checksum" in ''|*[!0-9a-f]* ) ui_error "远程 SHA-256 文件格式无效。"; return 1 ;; esac
  [ "${#expected_checksum}" -eq 64 ] || { ui_error "远程 SHA-256 长度无效。"; return 1; }
  if [ "$expected_checksum" != "$actual_checksum" ]; then
    ui_error "SHA-256 校验失败，拒绝安装下载内容。"
    return 1
  fi
  ui_success "SHA-256 校验通过。"
}

ensure_cron_service() {
  manager="$(service_manager)"
  if command -v crontab >/dev/null 2>&1; then
    :
  elif command -v apk >/dev/null 2>&1; then
    install_packages dcron
  elif command -v apt-get >/dev/null 2>&1; then
    install_packages cron
  else
    ui_error "未找到 crontab，且无法自动安装 cron。"
    return 1
  fi

  case "$manager" in
    systemd)
      if systemctl list-unit-files cron.service >/dev/null 2>&1; then
        systemctl enable --now cron >/dev/null 2>&1 || true
      elif systemctl list-unit-files crond.service >/dev/null 2>&1; then
        systemctl enable --now crond >/dev/null 2>&1 || true
      fi
      ;;
    openrc)
      if command -v rc-service >/dev/null 2>&1; then
        rc-update add crond default >/dev/null 2>&1 || true
        rc-service crond start >/dev/null 2>&1 || true
      fi
      ;;
  esac

  command -v crontab >/dev/null 2>&1 || {
    ui_error "crontab 仍不可用，无法启用自动刷新。"
    return 1
  }
}

write_logrotate_config() {
  [ -d /etc/logrotate.d ] || return 0
  cat > "$LOGROTATE_FILE" <<EOF
$LOG_DIR/*.log $LOG_DIR/*.err $CLOUDFLARED_LOG {
  size 10M
  rotate 3
  compress
  missingok
  notifempty
  copytruncate
}
EOF
  chmod 644 "$LOGROTATE_FILE"
}

make_temp() {
  mktemp "$1" 2>/dev/null || {
    red "无法创建临时文件：$1"
    exit 1
  }
}

host_cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc 2>/dev/null && return 0
  fi
  getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
}

cpu_quota_count() {
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r cpu_quota cpu_period < /sys/fs/cgroup/cpu.max || true
    if [ "${cpu_quota:-max}" != "max" ]; then
      awk -v quota="$cpu_quota" -v period="$cpu_period" 'BEGIN {
        if (quota > 0 && period > 0) {
          value = int((quota + period - 1) / period);
          if (value < 1) value = 1;
          print value;
        }
      }'
      return 0
    fi
  fi

  cpu_quota_file=""
  cpu_period_file=""
  for cpu_base in /sys/fs/cgroup/cpu /sys/fs/cgroup; do
    if [ -r "$cpu_base/cpu.cfs_quota_us" ] && [ -r "$cpu_base/cpu.cfs_period_us" ]; then
      cpu_quota_file="$cpu_base/cpu.cfs_quota_us"
      cpu_period_file="$cpu_base/cpu.cfs_period_us"
      break
    fi
  done

  if [ -n "$cpu_quota_file" ]; then
    cpu_quota="$(cat "$cpu_quota_file" 2>/dev/null || printf '')"
    cpu_period="$(cat "$cpu_period_file" 2>/dev/null || printf '')"
    awk -v quota="$cpu_quota" -v period="$cpu_period" 'BEGIN {
      if (quota > 0 && period > 0) {
        value = int((quota + period - 1) / period);
        if (value < 1) value = 1;
        print value;
      }
    }'
  fi
}

cpu_quota_milli() {
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r cpu_quota cpu_period < /sys/fs/cgroup/cpu.max || true
    if [ "${cpu_quota:-max}" != "max" ]; then
      awk -v quota="$cpu_quota" -v period="$cpu_period" 'BEGIN {
        if (quota > 0 && period > 0) {
          value = int((quota * 1000 + period - 1) / period);
          if (value < 1) value = 1;
          print value;
        }
      }'
      return 0
    fi
  fi

  cpu_quota_file=""
  cpu_period_file=""
  for cpu_base in /sys/fs/cgroup/cpu /sys/fs/cgroup; do
    if [ -r "$cpu_base/cpu.cfs_quota_us" ] && [ -r "$cpu_base/cpu.cfs_period_us" ]; then
      cpu_quota_file="$cpu_base/cpu.cfs_quota_us"
      cpu_period_file="$cpu_base/cpu.cfs_period_us"
      break
    fi
  done

  if [ -n "$cpu_quota_file" ]; then
    cpu_quota="$(cat "$cpu_quota_file" 2>/dev/null || printf '')"
    cpu_period="$(cat "$cpu_period_file" 2>/dev/null || printf '')"
    awk -v quota="$cpu_quota" -v period="$cpu_period" 'BEGIN {
      if (quota > 0 && period > 0) {
        value = int((quota * 1000 + period - 1) / period);
        if (value < 1) value = 1;
        print value;
      }
    }'
  fi
}

cpu_quota_severely_limited() {
  cpu_milli="$(cpu_quota_milli | sed -n '1p')"
  case "$cpu_milli" in ''|*[!0-9]*) return 1 ;; esac
  [ "$cpu_milli" -lt 1000 ]
}

cpuset_cpu_count() {
  for cpuset_file in \
    /sys/fs/cgroup/cpuset.cpus.effective \
    /sys/fs/cgroup/cpuset.cpus \
    /sys/fs/cgroup/cpuset/cpuset.cpus; do
    if [ -r "$cpuset_file" ]; then
      cpuset_value="$(cat "$cpuset_file" 2>/dev/null | tr -d '[:space:]')"
      [ -n "$cpuset_value" ] || continue
      printf '%s\n' "$cpuset_value" | awk -F, '
        {
          total = 0
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+-[0-9]+$/) {
              split($i, range, "-")
              if (range[2] >= range[1]) total += range[2] - range[1] + 1
            } else if ($i ~ /^[0-9]+$/) {
              total++
            }
          }
          if (total > 0) print total
        }'
      return 0
    fi
  done
}

effective_cpu_count() {
  quota_count="$(cpu_quota_count | sed -n '1p')"
  cpuset_count="$(cpuset_cpu_count | sed -n '1p')"
  host_count="$(host_cpu_count | sed -n '1p')"
  case "$quota_count" in ''|*[!0-9]*) quota_count="" ;; esac
  case "$cpuset_count" in ''|*[!0-9]*) cpuset_count="" ;; esac
  case "$host_count" in ''|*[!0-9]*) host_count=1 ;; esac

  cpu_count="$host_count"
  if [ -n "$quota_count" ] && [ "$quota_count" -lt "$cpu_count" ]; then
    cpu_count="$quota_count"
  fi
  if [ -n "$cpuset_count" ] && [ "$cpuset_count" -lt "$cpu_count" ]; then
    cpu_count="$cpuset_count"
  fi
  printf '%s\n' "$cpu_count"
}

cap_cpu_count() {
  cap_value="${1:-1}"
  cap_max="${2:-1}"
  case "$cap_value" in ''|*[!0-9]*) cap_value=1 ;; esac
  case "$cap_max" in ''|*[!0-9]*) cap_max=1 ;; esac
  [ "$cap_value" -ge 1 ] || cap_value=1
  [ "$cap_max" -ge 1 ] || cap_max=1
  if [ "$cap_value" -gt "$cap_max" ]; then
    printf '%s\n' "$cap_max"
  else
    printf '%s\n' "$cap_value"
  fi
}

remember_memory_limit_value() {
  memory_limit_value="$1"
  case "$memory_limit_value" in ''|max|*[!0-9]*) return 0 ;; esac
  memory_limit_value="$(awk -v value="$memory_limit_value" 'BEGIN {
    max = 4 * 1024 * 1024 * 1024 * 1024;
    if (value > 0 && value < max) printf "%.0f\n", value;
  }')"
  [ -n "$memory_limit_value" ] || return 0

  if [ -z "${best_memory_limit:-}" ]; then
    best_memory_limit="$memory_limit_value"
  else
    best_memory_limit="$(awk -v old="$best_memory_limit" -v new="$memory_limit_value" 'BEGIN {
      if (new > 0 && new < old) printf "%.0f\n", new;
      else printf "%.0f\n", old;
    }')"
  fi
}

remember_memory_limit_file() {
  memory_limit_file="$1"
  [ -r "$memory_limit_file" ] || return 0
  memory_limit_value="$(cat "$memory_limit_file" 2>/dev/null | tr -d '[:space:]')"
  remember_memory_limit_value "$memory_limit_value"
}

physical_memory_bytes() {
  [ -r /proc/meminfo ] || return 0
  awk '/^MemTotal:[[:space:]]+[0-9]+[[:space:]]+kB/ {
    printf "%.0f\n", $2 * 1024;
    exit;
  }' /proc/meminfo 2>/dev/null
}

memory_limit_bytes() {
  best_memory_limit=""
  # Full VMs and some NAT/LXC providers do not expose a usable cgroup memory
  # controller. MemTotal is still the upper bound visible to the process, so
  # include it and always keep the smallest trustworthy value.
  remember_memory_limit_value "$(physical_memory_bytes)"
  for memory_limit_file in \
    /sys/fs/cgroup/memory.max \
    /sys/fs/cgroup/memory/memory.limit_in_bytes \
    /sys/fs/cgroup/memory.limit_in_bytes; do
    remember_memory_limit_file "$memory_limit_file"
  done

  if [ -r /proc/self/cgroup ]; then
    while IFS=: read -r cgroup_id cgroup_controllers cgroup_path; do
      [ -n "$cgroup_id" ] || continue
      case "${cgroup_path:-/}" in
        /) cgroup_base="/sys/fs/cgroup" ;;
        *) cgroup_base="/sys/fs/cgroup$cgroup_path" ;;
      esac
      case "$cgroup_controllers" in
        '')
          remember_memory_limit_file "$cgroup_base/memory.max"
          ;;
        *memory*)
          remember_memory_limit_file "/sys/fs/cgroup/memory$cgroup_path/memory.limit_in_bytes"
          remember_memory_limit_file "$cgroup_base/memory.limit_in_bytes"
          ;;
      esac
    done < /proc/self/cgroup
  fi

  [ -n "$best_memory_limit" ] && printf '%s\n' "$best_memory_limit"
}

memory_limit_mib() {
  memory_limit_value="$(memory_limit_bytes)"
  case "$memory_limit_value" in ''|*[!0-9]*) return 0 ;; esac
  awk -v value="$memory_limit_value" 'BEGIN { printf "%d\n", int(value / 1048576) }'
}

memlimit_from_percent() {
  total_mib="$1"
  percent_value="$2"
  min_mib="$3"
  headroom_mib="$4"
  max_limit_mib="${5:-0}"
  awk -v total="$total_mib" -v percent="$percent_value" -v min="$min_mib" -v headroom="$headroom_mib" -v maxlimit="$max_limit_mib" 'BEGIN {
    value = int(total * percent / 100);
    value = int(value / 16) * 16;
    max = total - headroom;
    if (max < 32) max = int(total * 70 / 100);
    max = int(max / 16) * 16;
    if (max < 32) max = 32;
    if (value > max) value = max;
    if (maxlimit > 0 && value > maxlimit) value = maxlimit;
    if (value < min && min < max) value = min;
    if (value < 32) value = 32;
    printf "%dMiB", value;
  }'
}

memlimit_mib_value() {
  printf '%s' "$1" | sed -n 's/^\([0-9][0-9]*\)MiB$/\1/p'
}

normalize_runtime_profiles() {
  profile_recommended_mib="$(memlimit_mib_value "$recommended_mem")"
  profile_resource_mib="$(memlimit_mib_value "$resource_mem")"
  profile_throughput_mib="$(memlimit_mib_value "$throughput_mem")"

  case "$profile_recommended_mib:$profile_resource_mib" in
    *[!0-9:]*|:*|*:)
      ;;
    *)
      if [ "$profile_resource_mib" -ge "$profile_recommended_mib" ]; then
        profile_resource_mib=$((profile_recommended_mib * 2 / 3))
        profile_resource_mib=$((profile_resource_mib / 16 * 16))
        [ "$profile_resource_mib" -lt 64 ] && profile_resource_mib=64
        if [ "$profile_resource_mib" -ge "$profile_recommended_mib" ]; then
          profile_resource_mib=$((profile_recommended_mib - 16))
        fi
        [ "$profile_resource_mib" -lt 32 ] && profile_resource_mib=32
        resource_mem="${profile_resource_mib}MiB"
      fi
      ;;
  esac

  case "$profile_recommended_mib:$profile_throughput_mib" in
    *[!0-9:]*|:*|*:)
      ;;
    *)
      if [ "$profile_throughput_mib" -le "$profile_recommended_mib" ]; then
        profile_throughput_mib=$((profile_recommended_mib * 4 / 3))
        profile_throughput_mib=$(((profile_throughput_mib + 15) / 16 * 16))
        [ "$profile_throughput_mib" -gt 1024 ] && profile_throughput_mib=1024
        if [ "$profile_throughput_mib" -le "$profile_recommended_mib" ]; then
          profile_throughput_mib=$((profile_recommended_mib + 16))
        fi
        throughput_mem="${profile_throughput_mib}MiB"
      fi
      ;;
  esac

  case "$recommended_gogc:$resource_gogc" in
    *[!0-9:]*|:*|*:)
      ;;
    *)
      if [ "$resource_gogc" -le "$recommended_gogc" ]; then
        resource_gogc=$((recommended_gogc + 50))
      fi
      ;;
  esac
  case "$recommended_gogc:$throughput_gogc" in
    *[!0-9:]*|:*|*:)
      ;;
    *)
      if [ "$throughput_gogc" -ge "$recommended_gogc" ]; then
        throughput_gogc=$((recommended_gogc - 50))
        if [ "$recommended_gogc" -gt 75 ] && [ "$throughput_gogc" -lt 75 ]; then
          throughput_gogc=75
        elif [ "$throughput_gogc" -lt 50 ]; then
          throughput_gogc=50
        fi
      fi
      ;;
  esac
}

recommended_runtime() {
  cpu_count="$(effective_cpu_count)"
  cpu_limited=0
  if cpu_quota_severely_limited; then
    cpu_limited=1
  fi
  memory_mib="$(memory_limit_mib)"
  case "$memory_mib" in
    ''|*[!0-9]*)
      ;;
    *)
      if [ "$memory_mib" -le 192 ]; then
        recommended_mem="$(memlimit_from_percent "$memory_mib" 60 64 48)"
        recommended_gogc="75"
        cpu_count="$(cap_cpu_count "$cpu_count" 1)"
      elif [ "$memory_mib" -le 256 ]; then
        recommended_mem="$(memlimit_from_percent "$memory_mib" 60 64 64)"
        recommended_gogc="100"
        cpu_count="$(cap_cpu_count "$cpu_count" 1)"
      elif [ "$memory_mib" -le 512 ]; then
        recommended_mem="$(memlimit_from_percent "$memory_mib" 60 96 96)"
        recommended_gogc="125"
        cpu_count="$(cap_cpu_count "$cpu_count" 2)"
      elif [ "$memory_mib" -le 1024 ]; then
        recommended_mem="$(memlimit_from_percent "$memory_mib" 60 128 128)"
        recommended_gogc="150"
      else
        case "${os_id:-}" in
          alpine)
            recommended_mem="384MiB"
            recommended_gogc="150"
            ;;
          debian|ubuntu)
            recommended_mem="512MiB"
            recommended_gogc="200"
            ;;
          *)
            recommended_mem="512MiB"
            recommended_gogc="150"
            ;;
        esac
      fi
      if [ "$cpu_limited" = "1" ]; then
        case "$recommended_gogc" in ''|*[!0-9]*) recommended_gogc="175" ;; esac
        if [ "$recommended_gogc" -lt 175 ]; then
          recommended_gogc="175"
        fi
        cpu_count="$(cap_cpu_count "$cpu_count" 1)"
      fi
      printf '%s|%s|%s' "$recommended_mem" "$recommended_gogc" "$cpu_count"
      return 0
      ;;
  esac

  case "${os_id:-}" in
    alpine)
      fallback_mem="192MiB"
      fallback_gogc="125"
      ;;
    debian|ubuntu)
      fallback_mem="384MiB"
      fallback_gogc="200"
      ;;
    *)
      fallback_mem="256MiB"
      fallback_gogc="150"
      ;;
  esac
  if [ "$cpu_limited" = "1" ]; then
    [ "$fallback_gogc" -lt 175 ] && fallback_gogc="175"
    cpu_count="$(cap_cpu_count "$cpu_count" 1)"
  fi
  printf '%s|%s|%s' "$fallback_mem" "$fallback_gogc" "$cpu_count"
}

load_runtime_tuning() {
  if [ -r "$RUNTIME_ENV_FILE" ]; then
    while IFS='=' read -r runtime_key runtime_value; do
      case "$runtime_key" in
        MIHOMO_GOMEMLIMIT)
          [ -n "$MIHOMO_GOMEMLIMIT" ] || MIHOMO_GOMEMLIMIT="$runtime_value"
          ;;
        MIHOMO_GOGC)
          [ -n "$MIHOMO_GOGC" ] || MIHOMO_GOGC="$runtime_value"
          ;;
        MIHOMO_GOMAXPROCS)
          [ -n "$MIHOMO_GOMAXPROCS" ] || MIHOMO_GOMAXPROCS="$runtime_value"
          ;;
        MIHOMO_GODEBUG)
          [ -n "$MIHOMO_GODEBUG" ] || MIHOMO_GODEBUG="$runtime_value"
          ;;
      esac
    done < "$RUNTIME_ENV_FILE"
  fi
  [ -n "$MIHOMO_GODEBUG" ] || MIHOMO_GODEBUG="$MIHOMO_GODEBUG_DEFAULT"
}

validate_runtime_tuning() {
  [ -n "$MIHOMO_GODEBUG" ] || MIHOMO_GODEBUG="$MIHOMO_GODEBUG_DEFAULT"
  case "$MIHOMO_GOGC" in
    ''|*[!0-9]*)
      red "GOGC 必须是数字。"
      exit 1
      ;;
  esac
  case "$MIHOMO_GOMEMLIMIT" in
    *[!A-Za-z0-9]*|'')
      red "GOMEMLIMIT 只能包含字母和数字，例如 192MiB。"
      exit 1
      ;;
  esac
  case "${MIHOMO_GOMAXPROCS:-}" in
    ''|*[!0-9]*)
      red "GOMAXPROCS 必须是正整数。"
      exit 1
      ;;
  esac
  if [ "$MIHOMO_GOMAXPROCS" -lt 1 ]; then
    red "GOMAXPROCS 必须大于 0。"
    exit 1
  fi
  case "$MIHOMO_GODEBUG" in
    *[!A-Za-z0-9_=,.:+-]*)
      red "GODEBUG 只能包含字母、数字和常见分隔符。"
      exit 1
      ;;
  esac
}

write_runtime_tuning() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'MIHOMO_GOMEMLIMIT=%s\n' "$MIHOMO_GOMEMLIMIT"
    printf 'MIHOMO_GOGC=%s\n' "$MIHOMO_GOGC"
    printf 'MIHOMO_GOMAXPROCS=%s\n' "$MIHOMO_GOMAXPROCS"
    printf 'MIHOMO_GODEBUG=%s\n' "$MIHOMO_GODEBUG"
  } > "$RUNTIME_ENV_FILE"
  chmod 600 "$RUNTIME_ENV_FILE"
}

prompt_runtime_tuning() {
  env_mem="$MIHOMO_GOMEMLIMIT"
  env_gogc="$MIHOMO_GOGC"
  env_gomaxprocs="$MIHOMO_GOMAXPROCS"
  load_runtime_tuning
  recommended="$(recommended_runtime)"
  recommended_mem="${recommended%%|*}"
  recommended_rest="${recommended#*|}"
  recommended_gogc="${recommended_rest%%|*}"
  recommended_gomaxprocs="${recommended_rest#*|}"
  [ "$recommended_gomaxprocs" = "$recommended_rest" ] && recommended_gomaxprocs="$(effective_cpu_count)"
  detected_memory_mib="$(memory_limit_mib)"

  ui_section "设置 Mihomo 运行参数"
  case "$detected_memory_mib" in
    ''|*[!0-9]*) ui_warn "未检测到明确的容器内存限制，将使用系统类型推荐值。" ;;
    *) ui_warn "检测到可用内存约 ${detected_memory_mib}MiB，推荐值已按低内存容器预留余量。" ;;
  esac
  if [ -z "$env_mem" ]; then
    default_mem="${MIHOMO_GOMEMLIMIT:-$recommended_mem}"
    ui_prompt "请输入 GOMEMLIMIT（默认 $default_mem，推荐 $recommended_mem）："
    read -r input_mem || true
    MIHOMO_GOMEMLIMIT="${input_mem:-$default_mem}"
  else
    ui_warn "使用环境变量 GOMEMLIMIT=$MIHOMO_GOMEMLIMIT"
  fi

  if [ -z "$env_gogc" ]; then
    default_gogc="${MIHOMO_GOGC:-$recommended_gogc}"
    ui_prompt "请输入 GOGC（默认 $default_gogc，推荐 $recommended_gogc）："
    read -r input_gogc || true
    MIHOMO_GOGC="${input_gogc:-$default_gogc}"
  else
    ui_warn "使用环境变量 GOGC=$MIHOMO_GOGC"
  fi

  if [ -z "$env_gomaxprocs" ]; then
    default_gomaxprocs="${MIHOMO_GOMAXPROCS:-$recommended_gomaxprocs}"
    ui_prompt "请输入 GOMAXPROCS（默认 $default_gomaxprocs，推荐 $recommended_gomaxprocs）："
    read -r input_gomaxprocs || true
    MIHOMO_GOMAXPROCS="${input_gomaxprocs:-$default_gomaxprocs}"
  else
    ui_warn "使用环境变量 GOMAXPROCS=$MIHOMO_GOMAXPROCS"
  fi

  validate_runtime_tuning
  write_runtime_tuning
}

bool_value() {
  case "${1:-}" in
    1|y|Y|yes|YES|true|TRUE|on|ON|enable|ENABLE|enabled|ENABLED) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

load_network_settings() {
  if [ -r "$NETWORK_ENV_FILE" ]; then
    while IFS='=' read -r network_key network_value; do
      case "$network_key" in
        MIHOMO_IPV6)
          [ -n "$MIHOMO_IPV6" ] || MIHOMO_IPV6="$network_value"
          ;;
        MIHOMO_PREFER_IPV6)
          [ -n "$MIHOMO_PREFER_IPV6" ] || MIHOMO_PREFER_IPV6="$network_value"
          ;;
      esac
    done < "$NETWORK_ENV_FILE"
  fi

  MIHOMO_IPV6="$(bool_value "${MIHOMO_IPV6:-false}")"
  MIHOMO_PREFER_IPV6="$(bool_value "${MIHOMO_PREFER_IPV6:-false}")"
}

write_network_settings() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'MIHOMO_IPV6=%s\n' "$MIHOMO_IPV6"
    printf 'MIHOMO_PREFER_IPV6=%s\n' "$MIHOMO_PREFER_IPV6"
  } > "$NETWORK_ENV_FILE"
  chmod 600 "$NETWORK_ENV_FILE"
}

listener_address() {
  load_network_settings
  if [ "$MIHOMO_IPV6" = "true" ]; then
    printf '::'
  else
    printf '0.0.0.0'
  fi
}

load_feature_settings() {
  if [ -r "$FEATURES_ENV_FILE" ]; then
    while IFS='=' read -r feature_key feature_value; do
      case "$feature_key" in
        MULTI_USER_ENABLED)
          [ -n "$MIHOMO_MULTI_USER" ] || MIHOMO_MULTI_USER="$feature_value"
          ;;
      esac
    done < "$FEATURES_ENV_FILE"
  fi

  if [ -f "$MULTI_USER_FLAG" ]; then
    MIHOMO_MULTI_USER="true"
  else
    MIHOMO_MULTI_USER="$(bool_value "${MIHOMO_MULTI_USER:-false}")"
  fi
}

write_feature_settings() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'MULTI_USER_ENABLED=%s\n' "$MIHOMO_MULTI_USER"
  } > "$FEATURES_ENV_FILE"
  chmod 600 "$FEATURES_ENV_FILE"

  if [ "$MIHOMO_MULTI_USER" = "true" ]; then
    : > "$MULTI_USER_FLAG"
    chmod 600 "$MULTI_USER_FLAG"
  else
    rm -f "$MULTI_USER_FLAG"
  fi
}

multi_user_enabled() {
  load_feature_settings
  [ "$MIHOMO_MULTI_USER" = "true" ]
}

prompt_multi_user_feature() {
  if [ -x "$BIN_PATH" ] || [ -f "$CONFIG_FILE" ]; then
    load_feature_settings
    return 0
  fi

  if [ -f "$FEATURES_ENV_FILE" ] || [ -f "$MULTI_USER_FLAG" ]; then
    load_feature_settings
    return 0
  fi

  ui_section "可选功能"
  ui_prompt "是否安装多用户管理面板？仅首次安装时选择 [y/N]："
  read -r enable_multi_user || true
  case "$enable_multi_user" in
    y|Y|yes|YES)
      MIHOMO_MULTI_USER="true"
      write_feature_settings
      : > "$USERS_DB"
      chmod 600 "$USERS_DB"
      ui_success "多用户管理面板已启用。"
      ;;
    *)
      MIHOMO_MULTI_USER="false"
      write_feature_settings
      ui_warn "未启用多用户管理面板，菜单不会显示 77。"
      ;;
  esac
}

ensure_multi_user_enabled() {
  if ! multi_user_enabled; then
    ui_error "多用户管理未启用。该功能只能在初次安装 Mihomo 内核时选择安装。"
    exit 1
  fi
  [ -f "$USERS_DB" ] || : > "$USERS_DB"
  chmod 600 "$USERS_DB"
}

today_ymd() {
  date +%Y-%m-%d
}

date_to_epoch() {
  input_date="$1"
  date -d "$input_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$input_date" +%s 2>/dev/null || printf ''
}

is_valid_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  [ -n "$(date_to_epoch "$1")" ]
}

is_user_active() {
  user_enabled="$1"
  user_expire="$2"
  user_quota="${3:-0}"
  user_used="${4:-0}"
  [ "$user_enabled" = "1" ] || return 1

  case "$user_quota" in ''|*[!0-9]*) user_quota=0 ;; esac
  case "$user_used" in ''|*[!0-9]*) user_used=0 ;; esac
  if [ "$user_quota" != "0" ] && awk -v used="$user_used" -v quota="$user_quota" 'BEGIN { exit used >= quota ? 0 : 1 }'; then
    return 1
  fi

  [ -n "$user_expire" ] || return 0
  today_epoch="$(date_to_epoch "$(today_ymd)")"
  expire_epoch="$(date_to_epoch "$user_expire")"
  [ -n "$today_epoch" ] && [ -n "$expire_epoch" ] || return 1
  [ "$expire_epoch" -ge "$today_epoch" ]
}

quota_exceeded_user_count() {
  [ -s "$USERS_DB" ] || {
    printf '0\n'
    return 0
  }
  awk -F'|' '
    NF >= 9 {
      quota = $6 + 0
      used = $7 + 0
      if ($8 == "1" && quota > 0 && used >= quota) count++
    }
    END { print count + 0 }
  ' "$USERS_DB"
}

format_bytes() {
  bytes="${1:-0}"
  case "$bytes" in
    ''|*[!0-9]*) bytes=0 ;;
  esac
  awk -v b="$bytes" 'BEGIN {
    if (b >= 1073741824) printf "%.2fGiB", b / 1073741824;
    else if (b >= 1048576) printf "%.2fMiB", b / 1048576;
    else if (b >= 1024) printf "%.2fKiB", b / 1024;
    else printf "%dB", b;
  }'
}

quota_to_bytes() {
  quota_value="$1"
  case "$quota_value" in
    ''|0) printf '0'; return 0 ;;
    *[!0-9GgMmKk]*)
      return 1
      ;;
  esac
  printf '%s\n' "$quota_value" | awk '
    /^[0-9]+$/ { print $1; exit 0 }
    /^[0-9]+[Gg]$/ { sub(/[Gg]$/, ""); printf "%.0f\n", $1 * 1024 * 1024 * 1024; exit 0 }
    /^[0-9]+[Mm]$/ { sub(/[Mm]$/, ""); printf "%.0f\n", $1 * 1024 * 1024; exit 0 }
    /^[0-9]+[Kk]$/ { sub(/[Kk]$/, ""); printf "%.0f\n", $1 * 1024; exit 0 }
    { exit 1 }
  '
}

sanitize_db_field() {
  printf '%s' "$1" | tr -d '|\r\n'
}

sanitize_user_field() {
  sanitize_db_field "$1"
}

sanitize_sni_field() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
}

is_valid_hostname() {
  hostname_value="$1"
  [ "${#hostname_value}" -le 253 ] || return 1
  printf '%s\n' "$hostname_value" | awk -F'.' '
    NF < 2 { exit 1 }
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "" || length($i) > 63 || $i !~ /^[A-Za-z0-9-]+$/ || $i ~ /^-/ || $i ~ /-$/) exit 1
      }
    }
  '
}

is_valid_endpoint() {
  is_ipv4 "$1" || is_ipv6 "$1" || is_valid_hostname "$1"
}

yaml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

user_name_exists() {
  user_name="$1"
  [ -s "$USERS_DB" ] || return 1
  awk -F'|' -v n="$user_name" '$1 == n { found = 1 } END { exit found ? 0 : 1 }' "$USERS_DB"
}

node_record_by_index() {
  node_index="$1"
  awk -F'|' -v n="$node_index" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      i++
      if (i == n) { print; exit }
    }
  ' "$NODES_DB"
}

user_record_by_index() {
  user_index="$1"
  awk -F'|' -v n="$user_index" '
    NF >= 9 {
      i++
      if (i == n) { print; exit }
    }
  ' "$USERS_DB"
}

node_record_by_name_proto() {
  lookup_name="$1"
  lookup_proto="$2"
  awk -F'|' -v name="$lookup_name" -v proto="$lookup_proto" '
    $1 == proto && $2 == name { print; exit }
  ' "$NODES_DB"
}

ensure_user_ports() {
  [ "$MIHOMO_MULTI_USER" = "true" ] || return 0
  [ -s "$USERS_DB" ] || return 0

  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  changed=0
  while IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra; do
    [ -n "$user_name" ] || continue
    case "${user_port:-}" in
      ''|*[!0-9]*)
        user_port="$(unique_port)"
        changed=1
        ;;
    esac
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$user_name" "$user_node" "$user_proto" "$user_credential" "$user_expire" "$user_quota" "${user_used:-0}" "${user_enabled:-1}" "$user_created" "$user_note" "$user_port" "${user_extra:-}"
  done < "$USERS_DB" > "$tmp_file"

  if [ "$changed" = "1" ]; then
    mv "$tmp_file" "$USERS_DB"
    chmod 600 "$USERS_DB"
  else
    rm -f "$tmp_file"
  fi
}

detect_arch() {
  machine="$(uname -m)"
  case "$machine" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    armv7l | armv7) printf 'armv7' ;;
    armv6l | armv6) printf 'armv6' ;;
    i386 | i686) printf '386' ;;
    riscv64) printf 'riscv64' ;;
    *)
      red "暂不支持当前 CPU 架构：$machine"
      exit 1
      ;;
  esac
}

latest_download_url() {
  arch="$(detect_arch)"
  release_json="$(curl -fsSL "$GITHUB_API")" || {
    red "无法访问 mihomo GitHub Release API。"
    exit 1
  }

  urls="$(printf '%s\n' "$release_json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  download_url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${arch}.*compatible.*\.gz$" | head -n 1 || true)"

  if [ -z "$download_url" ]; then
    download_url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${arch}.*\.gz$" | head -n 1 || true)"
  fi

  if [ -z "$download_url" ]; then
    red "没有找到适配 linux-$arch 的 mihomo release 资产。"
    exit 1
  fi

  printf '%s' "$download_url"
}

rand_alnum() {
  length="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$length"
}

rand_hex() {
  bytes="${1:-4}"
  od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

new_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    h="$(rand_hex 16)"
    printf '%s-%s-%s-%s-%s\n' \
      "$(printf '%s' "$h" | cut -c1-8)" \
      "$(printf '%s' "$h" | cut -c9-12)" \
      "$(printf '%s' "$h" | cut -c13-16)" \
      "$(printf '%s' "$h" | cut -c17-20)" \
      "$(printf '%s' "$h" | cut -c21-32)"
  fi
}

url_path() {
  value="${1:-node}"
  printf '%s' "$value" | sed 's/%/%25/g; s/ /%20/g; s/\//%2F/g; s/#/%23/g; s/?/%3F/g; s/&/%26/g; s/@/%40/g; s/:/%3A/g; s/"/%22/g; s/'\''/%27/g; s/+/%2B/g; s/=/%3D/g'
}

url_query() {
  value="${1:-}"
  printf '%s' "$value" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g; s/&/%26/g; s/\[/%5B/g; s/\]/%5D/g; s/:/%3A/g; s/"/%22/g; s/'\''/%27/g; s/+/%2B/g; s/=/%3D/g'
}

need_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    red "缺少 openssl，请先在菜单输入 1 安装/补齐依赖。"
    exit 1
  fi
}

base64_urlsafe() {
  base64 | tr '+/' '-_' | tr -d '=\n'
}

base64_one_line() {
  base64 | tr -d '\n'
}

create_reality_keypair() {
  need_openssl
  key_file="$(make_temp "$CONFIG_DIR/reality.key.XXXXXX")"
  openssl genpkey -algorithm X25519 -out "$key_file" >/dev/null 2>&1 || {
    rm -f "$key_file"
    red "生成 Reality X25519 密钥失败。"
    exit 1
  }
  private_key="$(openssl pkey -in "$key_file" -outform DER 2>/dev/null | tail -c 32 | base64_urlsafe)"
  public_key="$(openssl pkey -in "$key_file" -pubout -outform DER 2>/dev/null | tail -c 32 | base64_urlsafe)"
  rm -f "$key_file"

  if [ -z "$private_key" ] || [ -z "$public_key" ]; then
    red "解析 Reality 密钥失败。"
    exit 1
  fi

  printf '%s|%s' "$private_key" "$public_key"
}

ensure_tls_cert() {
  need_openssl
  cert_name="$1"
  sni="$2"
  cert_dir="$CONFIG_DIR/certs"
  cert_file="$cert_dir/${cert_name}.crt"
  key_file="$cert_dir/${cert_name}.key"
  mkdir -p "$cert_dir"

  if [ ! -s "$cert_file" ] || [ ! -s "$key_file" ]; then
    openssl req -x509 -nodes -newkey ec \
      -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout "$key_file" \
      -out "$cert_file" \
      -subj "/CN=$sni" \
      -days 3650 >/dev/null 2>&1 || {
        red "生成 TLS 自签证书失败。"
        exit 1
      }
    chmod 600 "$key_file" "$cert_file"
  fi

  printf '%s|%s' "$cert_file" "$key_file"
}

random_port() {
  od -An -N2 -tu2 /dev/urandom | awk '{ print 20000 + ($1 % 30000) }'
}

is_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
      }
      exit 0
    }
  '
}

is_ipv6() {
  case "$1" in
    *:*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | awk '
    {
      if ($0 !~ /^[0-9A-Fa-f:]+$/) exit 1
      value = $0
      double_colon = gsub(/::/, "", value)
      if (double_colon > 1 || $0 ~ /:::/) exit 1
      split($0, parts, ":")
      nonempty = 0
      for (i in parts) {
        if (parts[i] != "") {
          if (length(parts[i]) > 4) exit 1
          nonempty++
        }
      }
      if (double_colon == 1 && nonempty <= 7) exit 0
      if (double_colon == 0 && nonempty == 8) exit 0
      exit 1
    }
  '
}

is_ip_address() {
  is_ipv4 "$1" || is_ipv6 "$1"
}

format_link_host() {
  if is_ipv6 "$1"; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

fetch_public_ipv4() {
  command -v curl >/dev/null 2>&1 || return 1
  ip="$(curl -4 -m 4 -fsSL https://api.ipify.org 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -4 -m 4 -fsSL https://ifconfig.me 2>/dev/null || true)"
  fi
  ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
  is_ipv4 "$ip" || return 1
  printf '%s' "$ip"
}

fetch_public_ipv6() {
  command -v curl >/dev/null 2>&1 || return 1
  ip="$(curl -6 -m 4 -fsSL https://api6.ipify.org 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    ip="$(curl -6 -m 4 -fsSL https://ifconfig.me 2>/dev/null || true)"
  fi
  ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
  is_ipv6 "$ip" || return 1
  printf '%s' "$ip"
}

cached_public_ip() {
  cache_family="$1"
  cache_ip=""
  cache_time=""
  cache_now="$(date +%s 2>/dev/null || printf '0')"
  if [ -r "$PUBLIC_IP_CACHE_FILE" ]; then
    cache_ip="$(awk -F= -v family="$cache_family" '$1 == family { value = $2 } END { print value }' "$PUBLIC_IP_CACHE_FILE" 2>/dev/null | tr -d '[:space:]')"
    cache_time="$(awk -F= -v family="${cache_family}_time" '$1 == family { value = $2 } END { print value }' "$PUBLIC_IP_CACHE_FILE" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$cache_ip" ]; then
      case "$cache_time" in
        '') ;;
        *[!0-9]*) return 1 ;;
        *)
          case "$PUBLIC_IP_CACHE_TTL" in ''|*[!0-9]*) return 1 ;; esac
          if [ "$cache_now" -lt "$cache_time" ] || [ $((cache_now - cache_time)) -gt "$PUBLIC_IP_CACHE_TTL" ]; then
            return 1
          fi
          ;;
      esac
      case "$cache_family" in
        ipv6) is_ipv6 "$cache_ip" || return 1 ;;
        *) is_ipv4 "$cache_ip" || return 1 ;;
      esac
      printf '%s' "$cache_ip"
      return 0
    fi

    cache_ip="$(sed -n '1p' "$PUBLIC_IP_CACHE_FILE" 2>/dev/null | sed 's/^ipv[46]=//' | tr -d '[:space:]')"
    case "$cache_family" in
      ipv6) is_ipv6 "$cache_ip" || return 1 ;;
      *) is_ipv4 "$cache_ip" || return 1 ;;
    esac
    printf '%s' "$cache_ip"
    return 0
  fi
  return 1
}

cache_public_ip() {
  cache_family="$1"
  cache_ip="$2"
  mkdir -p "$CONFIG_DIR" 2>/dev/null || true
  if [ ! -w "$CONFIG_DIR" ] && [ ! -w "$PUBLIC_IP_CACHE_FILE" ]; then
    return 0
  fi

  tmp_file="$(make_temp "$CONFIG_DIR/public-ip.XXXXXX")"
  cache_time="$(date +%s 2>/dev/null || printf '0')"
  if [ -r "$PUBLIC_IP_CACHE_FILE" ]; then
    awk -F= -v family="$cache_family" '$1 != family && $1 != family "_time" && $1 ~ /^ipv[46](_time)?$/ { print }' "$PUBLIC_IP_CACHE_FILE" > "$tmp_file" 2>/dev/null || : > "$tmp_file"
  else
    : > "$tmp_file"
  fi
  printf '%s=%s\n' "$cache_family" "$cache_ip" >> "$tmp_file"
  printf '%s_time=%s\n' "$cache_family" "$cache_time" >> "$tmp_file"
  mv "$tmp_file" "$PUBLIC_IP_CACHE_FILE"
  chmod 600 "$PUBLIC_IP_CACHE_FILE"
}

local_ip_by_family() {
  local_family="$1"
  hostname -I 2>/dev/null | tr ' ' '\n' | awk -v family="$local_family" '
    family == "ipv6" && index($0, ":") > 0 { print; exit }
    family != "ipv6" && index($0, ":") == 0 && $0 != "" { print; exit }
  '
}

public_ip_by_family() {
  ip_family="$1"

  if ip="$(cached_public_ip "$ip_family" 2>/dev/null)"; then
    printf '%s' "$ip"
    return 0
  fi

  case "$ip_family" in
    ipv6)
      if ip="$(fetch_public_ipv6 2>/dev/null)"; then
        cache_public_ip ipv6 "$ip"
        printf '%s' "$ip"
        return 0
      fi
      ip="$(local_ip_by_family ipv6)"
      ;;
    *)
      if ip="$(fetch_public_ipv4 2>/dev/null)"; then
        cache_public_ip ipv4 "$ip"
        printf '%s' "$ip"
        return 0
      fi
      ip="$(local_ip_by_family ipv4)"
      ;;
  esac

  if is_ip_address "$ip"; then
    printf '%s' "$ip"
    return 0
  fi
  return 1
}

public_ip() {
  load_network_settings

  if [ "$MIHOMO_PREFER_IPV6" = "true" ]; then
    if ip="$(public_ip_by_family ipv6 2>/dev/null)"; then
      printf '%s' "$ip"
      return 0
    fi
    if ip="$(public_ip_by_family ipv4 2>/dev/null)"; then
      printf '%s' "$ip"
      return 0
    fi
  else
    if ip="$(public_ip_by_family ipv4 2>/dev/null)"; then
      printf '%s' "$ip"
      return 0
    fi
    if [ "$MIHOMO_IPV6" = "true" ] && ip="$(public_ip_by_family ipv6 2>/dev/null)"; then
      printf '%s' "$ip"
      return 0
    fi
  fi

  printf 'YOUR_SERVER_IP'
}

render_user_listener() {
  render_user_name="$1"
  render_user_node="$2"
  render_user_proto="$3"
  render_user_credential="$4"
  render_user_port="$5"
  render_listen_address="$6"

  render_node_record="$(node_record_by_name_proto "$render_user_node" "$render_user_proto")"
  [ -n "$render_node_record" ] || return 0

  IFS='|' read -r render_proto render_node_name render_node_port render_value1 render_value2 render_value3 render_value4 render_value5 render_value6 <<EOF
$render_node_record
EOF
  render_user_name_yaml="$(yaml_escape "$render_user_name")"
  render_user_credential_yaml="$(yaml_escape "$render_user_credential")"
  render_listen_address_yaml="$(yaml_escape "$render_listen_address")"

  case "$render_user_proto" in
    vless-reality)
      render_sni="$(yaml_escape "$render_value2")"
      render_dest="$(yaml_escape "$render_value3")"
      render_private_key="$(yaml_escape "$render_value4")"
      render_short_id="$(yaml_escape "$render_value6")"
      cat <<EOF
  - name: "$render_user_name_yaml"
    type: vless
    port: $render_user_port
    listen: "$render_listen_address_yaml"
    users:
      - username: "$render_user_name_yaml"
        uuid: "$render_user_credential_yaml"
    tls: true
    reality-config:
      dest: "$render_dest"
      private-key: "$render_private_key"
      short-id:
        - "$render_short_id"
      server-names:
        - "$render_sni"
EOF
      ;;
    hysteria2)
      render_sni="$(yaml_escape "$render_value2")"
      render_cert_file="$(yaml_escape "$render_value3")"
      render_key_file="$(yaml_escape "$render_value4")"
      render_salamander_password="$(yaml_escape "$render_value5")"
      cat <<EOF
  - name: "$render_user_name_yaml"
    type: hysteria2
    port: $render_user_port
    listen: "$render_listen_address_yaml"
    users:
      "$render_user_name_yaml": "$render_user_credential_yaml"
    certificate: "$render_cert_file"
    private-key: "$render_key_file"
    up: ${HY2_UP_MBPS} Mbps
    down: ${HY2_DOWN_MBPS} Mbps
EOF
      if [ -n "$render_salamander_password" ]; then
        cat <<EOF
    obfs: salamander
    obfs-password: "$render_salamander_password"
EOF
      fi
      ;;
    anytls)
      render_cert_file="$(yaml_escape "$render_value3")"
      render_key_file="$(yaml_escape "$render_value4")"
      cat <<EOF
  - name: "$render_user_name_yaml"
    type: anytls
    port: $render_user_port
    listen: "$render_listen_address_yaml"
    users:
      "$render_user_name_yaml": "$render_user_credential_yaml"
    certificate: "$render_cert_file"
    private-key: "$render_key_file"
EOF
      ;;
    vless-ws)
      render_ws_path="$(yaml_escape "$render_value2")"
      render_ws_mode="${render_value4:-legacy}"
      if [ "$render_ws_mode" = "argo" ]; then
        render_user_listen_address="127.0.0.1"
      else
        render_user_listen_address="$render_listen_address"
      fi
      render_user_listen_address_yaml="$(yaml_escape "$render_user_listen_address")"
      cat <<EOF
  - name: "$render_user_name_yaml"
    type: vless
    port: $render_user_port
    listen: "$render_user_listen_address_yaml"
    allow-insecure: true
    users:
      - username: "$render_user_name_yaml"
        uuid: "$render_user_credential_yaml"
    ws-path: "$render_ws_path"
EOF
      ;;
  esac
}

render_user_listeners() {
  [ "$MIHOMO_MULTI_USER" = "true" ] || return 0
  [ -s "$USERS_DB" ] || return 0
  while IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra; do
    [ -n "$user_name" ] || continue
    [ -n "${user_port:-}" ] || continue
    is_user_active "$user_enabled" "$user_expire" "$user_quota" "$user_used" || continue
    render_user_listener "$user_name" "$user_node" "$user_proto" "$user_credential" "$user_port" "$cfg_listen_address"
  done < "$USERS_DB"
}

dns_is_address() {
  case "${1:-}" in
    ''|0.0.0.0|::|*[!0-9A-Fa-f:.]*) return 1 ;;
    *) return 0 ;;
  esac
}

system_dns_candidates() {
  [ -r /etc/resolv.conf ] || return 0
  awk '/^[[:space:]]*nameserver[[:space:]]+/ { print $2 }' /etc/resolv.conf 2>/dev/null |
    awk 'NF && !seen[$0]++'
}

run_with_timeout() {
  run_timeout="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$run_timeout" "$@"
  else
    "$@"
  fi
}

dns_udp_query_works() {
  dns_test_server="$1"
  dns_is_address "$dns_test_server" || return 1
  if command -v nslookup >/dev/null 2>&1; then
    if dns_lookup_output="$(run_with_timeout 6 nslookup "$DNS_TEST_NAME" "$dns_test_server" 2>/dev/null)"; then
      printf '%s\n' "$dns_lookup_output" | grep -Eq '(^Name:|^Address [0-9]+:|has address|canonical name)' && return 0
    fi
  fi
  if command -v dig >/dev/null 2>&1; then
    run_with_timeout 6 dig +time=2 +tries=1 +short @"$dns_test_server" "$DNS_TEST_NAME" A 2>/dev/null |
      grep -Eq '^[0-9A-Fa-f:.]+$' && return 0
  fi
  return 1
}

dns_tcp_53_works() {
  dns_test_server="$1"
  dns_is_address "$dns_test_server" || return 1
  if command -v dig >/dev/null 2>&1; then
    run_with_timeout 6 dig +tcp +time=2 +tries=1 +short @"$dns_test_server" "$DNS_TEST_NAME" A 2>/dev/null |
      grep -Eq '^[0-9A-Fa-f:.]+$' && return 0
  fi
  if command -v nc >/dev/null 2>&1; then
    run_with_timeout 5 nc -z -w 3 "$dns_test_server" 53 >/dev/null 2>&1 && return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    run_with_timeout 5 curl -sS --connect-timeout 3 "telnet://$dns_test_server:53" </dev/null >/dev/null 2>&1 && return 0
  fi
  return 1
}

probe_public_dns() {
  dns_public_udp=""
  dns_public_tcp=""
  for dns_public in 1.1.1.1 8.8.8.8 9.9.9.9; do
    if dns_udp_query_works "$dns_public"; then
      dns_public_udp="${dns_public_udp}${dns_public_udp:+ }$dns_public"
    fi
    if dns_tcp_53_works "$dns_public"; then
      dns_public_tcp="${dns_public_tcp}${dns_public_tcp:+ }$dns_public"
    fi
  done
}

select_working_dns() {
  dns_selected=""
  dns_system_working=""
  for dns_candidate in $(system_dns_candidates); do
    dns_is_address "$dns_candidate" || continue
    if dns_udp_query_works "$dns_candidate"; then
      dns_system_working="${dns_system_working}${dns_system_working:+ }$dns_candidate"
      dns_selected="$dns_candidate"
      break
    fi
  done

  probe_public_dns
  if [ -z "$dns_selected" ]; then
    for dns_candidate in $dns_public_udp; do
      dns_selected="${dns_selected}${dns_selected:+ }$dns_candidate"
      [ "$(printf '%s\n' "$dns_selected" | wc -w | tr -d ' ')" -ge 2 ] && break
    done
  fi

  mkdir -p "$CONFIG_DIR"
  {
    printf 'checked_at=%s\n' "$(date +%s 2>/dev/null || printf 0)"
    printf 'system_working=%s\n' "$dns_system_working"
    printf 'public_udp=%s\n' "$dns_public_udp"
    printf 'public_tcp=%s\n' "$dns_public_tcp"
    printf 'selected=%s\n' "$dns_selected"
  } > "$DNS_STATE_FILE"
  chmod 600 "$DNS_STATE_FILE"
  [ -n "$dns_selected" ]
}

configured_dns_servers() {
  [ -r "$CONFIG_FILE" ] || return 0
  awk '
    /^[[:space:]]*nameserver:[[:space:]]*$/ { in_nameserver=1; next }
    in_nameserver && /^[[:space:]]*-[[:space:]]*/ {
      value=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value); gsub(/"/, "", value)
      if (value ~ /^[0-9A-Fa-f:.]+$/) print value
      next
    }
    in_nameserver { exit }
  ' "$CONFIG_FILE"
}

configured_dns_works() {
  for dns_candidate in $(configured_dns_servers); do
    dns_udp_query_works "$dns_candidate" && return 0
  done
  return 1
}

dns_preflight_repair() {
  [ -f "$CONFIG_FILE" ] || return 0
  configured_dns_works && return 0
  ui_warn "DNS 上游不可达，正在自动选择有效的系统或公共 DNS。"
  if ! select_working_dns; then
    ui_error "未找到能够完成解析的 DNS 上游；已停止重启，节点配置本身未判定为故障。"
    return 1
  fi
  render_config || return 1
  ui_success "DNS 已自动迁移为可用上游：$dns_selected"
}

render_config() {
  mkdir -p "$CONFIG_DIR" "$LOG_DIR"
  load_network_settings
  load_feature_settings
  ensure_user_ports
  cfg_ipv6="$MIHOMO_IPV6"
  cfg_listen_address="$(listener_address)"
  tmp_file="$(make_temp "$CONFIG_DIR/config.XXXXXX")"
  secret_file="$CONFIG_DIR/controller.secret"

  if [ ! -s "$secret_file" ]; then
    rand_alnum 32 > "$secret_file"
    chmod 600 "$secret_file"
  fi
  controller_secret="$(cat "$secret_file")"

  if ! select_working_dns; then
    ui_error "未检测到可用 DNS 上游，拒绝生成包含无效公共 DNS 的配置。"
    rm -f "$tmp_file"
    return 1
  fi

  cat > "$tmp_file" <<EOF
mixed-port: 7890
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: warning
ipv6: $cfg_ipv6
external-controller: 127.0.0.1:9090
secret: "$controller_secret"
profile:
  store-selected: true
  store-fake-ip: false
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: $cfg_ipv6
  enhanced-mode: redir-host
  nameserver:
EOF
  for cfg_dns_server in $dns_selected; do
    printf '    - %s\n' "$cfg_dns_server" >> "$tmp_file"
  done

  if [ -s "$NODES_DB" ]; then
    printf 'listeners:\n' >> "$tmp_file"
    while IFS='|' read -r cfg_proto cfg_node_name cfg_node_port cfg_value1 cfg_value2 cfg_value3 cfg_value4 cfg_value5 cfg_value6; do
      [ -n "$cfg_proto" ] || continue
      cfg_node_name_yaml="$(yaml_escape "$cfg_node_name")"
      cfg_listen_address_yaml="$(yaml_escape "$cfg_listen_address")"
      case "$cfg_proto" in
        vless-reality)
          cfg_node_uuid="$(yaml_escape "$cfg_value1")"
          cfg_sni="$(yaml_escape "$cfg_value2")"
          cfg_dest="$(yaml_escape "$cfg_value3")"
          cfg_private_key="$(yaml_escape "$cfg_value4")"
          cfg_short_id="$(yaml_escape "$cfg_value6")"
          cat >> "$tmp_file" <<EOF
  - name: "$cfg_node_name_yaml"
    type: vless
    port: $cfg_node_port
    listen: "$cfg_listen_address_yaml"
    users:
      - username: "$cfg_node_name_yaml"
        uuid: "$cfg_node_uuid"
EOF
          cat >> "$tmp_file" <<EOF
    tls: true
    reality-config:
      dest: "$cfg_dest"
      private-key: "$cfg_private_key"
      short-id:
        - "$cfg_short_id"
      server-names:
        - "$cfg_sni"
EOF
          ;;
        hysteria2)
          cfg_node_password="$(yaml_escape "$cfg_value1")"
          cfg_cert_file="$(yaml_escape "$cfg_value3")"
          cfg_key_file="$(yaml_escape "$cfg_value4")"
          cfg_salamander_password="$(yaml_escape "$cfg_value5")"
          cat >> "$tmp_file" <<EOF
  - name: "$cfg_node_name_yaml"
    type: hysteria2
    port: $cfg_node_port
    listen: "$cfg_listen_address_yaml"
    users:
      "$cfg_node_name_yaml": "$cfg_node_password"
EOF
          cat >> "$tmp_file" <<EOF
    certificate: "$cfg_cert_file"
    private-key: "$cfg_key_file"
    up: ${HY2_UP_MBPS} Mbps
    down: ${HY2_DOWN_MBPS} Mbps
EOF
          if [ -n "$cfg_salamander_password" ]; then
            cat >> "$tmp_file" <<EOF
    obfs: salamander
    obfs-password: "$cfg_salamander_password"
EOF
          fi
          ;;
        anytls)
          cfg_node_password="$(yaml_escape "$cfg_value1")"
          cfg_cert_file="$(yaml_escape "$cfg_value3")"
          cfg_key_file="$(yaml_escape "$cfg_value4")"
          cat >> "$tmp_file" <<EOF
  - name: "$cfg_node_name_yaml"
    type: anytls
    port: $cfg_node_port
    listen: "$cfg_listen_address_yaml"
    users:
      "$cfg_node_name_yaml": "$cfg_node_password"
EOF
          cat >> "$tmp_file" <<EOF
    certificate: "$cfg_cert_file"
    private-key: "$cfg_key_file"
EOF
          ;;
        vless-ws)
          cfg_node_uuid="$(yaml_escape "$cfg_value1")"
          cfg_ws_path="$(yaml_escape "$cfg_value2")"
          cfg_ws_mode="${cfg_value4:-legacy}"
          if [ "$cfg_ws_mode" = "argo" ]; then
            cfg_ws_listen_address="127.0.0.1"
          else
            cfg_ws_listen_address="$cfg_listen_address"
          fi
          cfg_ws_listen_address_yaml="$(yaml_escape "$cfg_ws_listen_address")"
          cat >> "$tmp_file" <<EOF
  - name: "$cfg_node_name_yaml"
    type: vless
    port: $cfg_node_port
    listen: "$cfg_ws_listen_address_yaml"
    allow-insecure: true
    users:
      - username: "$cfg_node_name_yaml"
        uuid: "$cfg_node_uuid"
EOF
          cat >> "$tmp_file" <<EOF
    ws-path: "$cfg_ws_path"
EOF
          ;;
      esac
    done < "$NODES_DB"
    render_user_listeners >> "$tmp_file"
  else
    printf 'listeners: []\n' >> "$tmp_file"
  fi

  cat >> "$tmp_file" <<'EOF'
proxies: []
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DIRECT
EOF

  if [ -x "$BIN_PATH" ]; then
    if ! "$BIN_PATH" -t -d "$CONFIG_DIR" -f "$tmp_file" >/dev/null 2>&1; then
      ui_error "新配置未通过 Mihomo 自检，已保留当前运行配置。"
      "$BIN_PATH" -t -d "$CONFIG_DIR" -f "$tmp_file" 2>&1 | tail -n 8 >&2 || true
      rm -f "$tmp_file"
      return 1
    fi
  fi

  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_BACKUP_FILE"
    chmod 600 "$CONFIG_BACKUP_FILE"
  else
    rm -f "$CONFIG_BACKUP_FILE"
  fi
  mv "$tmp_file" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  : > "$CONFIG_PENDING_FILE"
}

write_systemd_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=mihomo proxy service
Documentation=https://wiki.metacubex.one/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=GOMEMLIMIT=$MIHOMO_GOMEMLIMIT
Environment=GOGC=$MIHOMO_GOGC
Environment=GOMAXPROCS=$MIHOMO_GOMAXPROCS
Environment=GODEBUG=$MIHOMO_GODEBUG
ExecStart=$BIN_PATH -d $CONFIG_DIR -f $CONFIG_FILE
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  restart_service || return 1
}

write_openrc_service() {
  cat > "/etc/init.d/${SERVICE_NAME}" <<EOF
#!/sbin/openrc-run

description="mihomo proxy service"
command="$BIN_PATH"
command_args="-d $CONFIG_DIR -f $CONFIG_FILE"
output_log="$LOG_DIR/${SERVICE_NAME}.log"
error_log="$LOG_DIR/${SERVICE_NAME}.err"
supervisor="supervise-daemon"
respawn_delay=2
respawn_max=0
rc_ulimit="-n 1048576"
export GOMEMLIMIT="$MIHOMO_GOMEMLIMIT"
export GOGC="$MIHOMO_GOGC"
export GOMAXPROCS="$MIHOMO_GOMAXPROCS"
export GODEBUG="$MIHOMO_GODEBUG"

depend() {
  need net
}
EOF
  chmod +x "/etc/init.d/${SERVICE_NAME}"
  rc-update add "$SERVICE_NAME" default >/dev/null
  restart_service || return 1
}

mihomo_process_is_running() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x mihomo >/dev/null 2>&1 && return 0
  fi
  if command -v pidof >/dev/null 2>&1; then
    pidof mihomo >/dev/null 2>&1 && return 0
  fi
  ps 2>/dev/null | awk '$0 ~ /[\/]usr[\/]local[\/]bin[\/]mihomo/ && $0 !~ /supervise-daemon/ { found=1 } END { exit !found }'
}

service_is_running() {
  manager="$(service_manager)"
  case "$manager" in
    systemd) systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && mihomo_process_is_running ;;
    openrc) rc-service "$SERVICE_NAME" status >/dev/null 2>&1 && mihomo_process_is_running ;;
    *) return 1 ;;
  esac
}

wait_service_running() {
  wait_service_count=0
  while [ "$wait_service_count" -lt 10 ]; do
    if service_is_running && system_port_in_use 7890 && system_port_in_use 9090 && system_port_in_use 1053; then
      return 0
    fi
    sleep 1
    wait_service_count=$((wait_service_count + 1))
  done
  return 1
}

restart_service() {
  dns_recovery_attempt="${1:-0}"
  if [ "$dns_recovery_attempt" = "0" ]; then
    dns_preflight_repair || return 1
  fi
  if [ -x "$BIN_PATH" ] && [ -f "$CONFIG_FILE" ] && ! "$BIN_PATH" -t -d "$CONFIG_DIR" -f "$CONFIG_FILE" >/dev/null 2>&1; then
    ui_error "Mihomo 当前配置未通过启动前检查，已取消重启。"
    if [ -f "$CONFIG_PENDING_FILE" ] && [ -f "$CONFIG_BACKUP_FILE" ]; then
      cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
      rm -f "$CONFIG_PENDING_FILE" "$CONFIG_BACKUP_FILE"
      ui_warn "已恢复上一份有效配置，当前运行中的 Mihomo 未被中断。"
    fi
    return 1
  fi
  manager="$(service_manager)"
  restart_result=0
  case "$manager" in
    systemd)
      systemctl daemon-reload || restart_result=1
      systemctl restart "$SERVICE_NAME" || restart_result=1
      ;;
    openrc)
      rc-service "$SERVICE_NAME" restart || restart_result=1
      ;;
    *)
      red "未找到 systemd 或 OpenRC，无法管理 mihomo 服务。"
      return 1
      ;;
  esac

  if [ "$restart_result" = "0" ] && wait_service_running; then
    if ! configured_dns_works; then
      if [ "$dns_recovery_attempt" = "0" ]; then
        ui_warn "Mihomo 启动后 DNS 验证失败，正在重新选择上游并复验一次。"
        select_working_dns && render_config && restart_service 1 && return 0
      fi
      ui_error "Mihomo 服务已启动，但 DNS 上游仍不可达；节点监听与 DNS 故障需分别排查。"
      return 1
    fi
    rm -f "$CONFIG_PENDING_FILE" "$CONFIG_BACKUP_FILE"
    return 0
  fi

  if [ -f "$CONFIG_PENDING_FILE" ] && [ -f "$CONFIG_BACKUP_FILE" ]; then
    ui_error "Mihomo 使用新配置启动失败，正在自动恢复上一份配置。"
    cp "$CONFIG_BACKUP_FILE" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    case "$manager" in
      systemd) systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true ;;
      openrc) rc-service "$SERVICE_NAME" restart >/dev/null 2>&1 || true ;;
    esac
    rm -f "$CONFIG_PENDING_FILE" "$CONFIG_BACKUP_FILE"
    if wait_service_running; then
      ui_warn "已恢复旧配置，Mihomo 服务重新运行。"
    else
      ui_error "旧配置也未能启动，请查看服务日志。"
    fi
  fi
  return 1
}

install_core() {
  need_root
  screen_title "一键安装 Mihomo 内核"
  detect_os
  check_internal_ports mihomo || return 1
  prompt_runtime_tuning
  prompt_multi_user_feature
  ui_section "安装系统依赖"
  install_packages curl gzip openssl logrotate
  mkdir -p "$CONFIG_DIR" "$LOG_DIR"
  write_logrotate_config

  download_url="$(latest_download_url)"
  tmp_file="$(make_temp /tmp/mihomo.XXXXXX)"
  bin_tmp="$(make_temp /tmp/mihomo-bin.XXXXXX)"

  ui_warn "下载地址：$download_url"
  ui_section "下载并安装 Mihomo 内核"
  curl -fL "$download_url" -o "$tmp_file" || {
    rm -f "$tmp_file" "$bin_tmp"
    ui_error "Mihomo 下载失败。"
    return 1
  }
  verify_remote_checksum "$download_url" "$tmp_file"
  verify_result=$?
  [ "$verify_result" -ne 1 ] || { rm -f "$tmp_file" "$bin_tmp"; return 1; }
  gzip -dc "$tmp_file" > "$bin_tmp" || {
    rm -f "$tmp_file" "$bin_tmp"
    ui_error "下载文件无法解压。"
    return 1
  }
  chmod +x "$bin_tmp"
  if ! "$bin_tmp" -v >/dev/null 2>&1; then
    rm -f "$tmp_file" "$bin_tmp"
    ui_error "下载的 Mihomo 内核无法运行，已取消安装。"
    return 1
  fi
  if [ -x "$BIN_PATH" ]; then
    cp "$BIN_PATH" "$BIN_BACKUP_PATH"
    chmod 755 "$BIN_BACKUP_PATH"
  fi
  mv "$bin_tmp" "$BIN_PATH"
  rm -f "$tmp_file"
  chmod +x "$BIN_PATH"

  [ -f "$NODES_DB" ] || : > "$NODES_DB"
  chmod 600 "$NODES_DB"
  if multi_user_enabled; then
    [ -f "$USERS_DB" ] || : > "$USERS_DB"
    chmod 600 "$USERS_DB"
  fi
  if ! render_config; then
    if [ -x "$BIN_BACKUP_PATH" ]; then
      cp "$BIN_BACKUP_PATH" "$BIN_PATH"
      ui_warn "新内核无法加载现有配置，已恢复上一版本。"
    else
      rm -f "$BIN_PATH"
    fi
    return 1
  fi

  core_install_failed=0
  manager="$(service_manager)"
  case "$manager" in
    systemd) write_systemd_service || core_install_failed=1 ;;
    openrc) write_openrc_service || core_install_failed=1 ;;
    *)
      ui_error "未找到 systemd 或 OpenRC，mihomo 已安装但服务未创建。"
      core_install_failed=1
      ;;
  esac

  if [ "${core_install_failed:-0}" = "1" ]; then
    if [ -x "$BIN_BACKUP_PATH" ]; then
      cp "$BIN_BACKUP_PATH" "$BIN_PATH"
      restart_service >/dev/null 2>&1 || true
      ui_warn "新内核启动失败，已恢复上一版本。"
    fi
    return 1
  fi

  ui_success "mihomo 内核安装完成，服务已启动。"
}

rollback_core() {
  need_root
  ensure_installed
  [ -x "$BIN_BACKUP_PATH" ] || { ui_error "没有可回滚的 Mihomo 内核版本。"; return 1; }
  rollback_tmp="$(make_temp /tmp/mihomo-current.XXXXXX)"
  cp "$BIN_PATH" "$rollback_tmp"
  cp "$BIN_BACKUP_PATH" "$BIN_PATH"
  chmod 755 "$BIN_PATH"
  if "$BIN_PATH" -t -d "$CONFIG_DIR" -f "$CONFIG_FILE" >/dev/null 2>&1 && restart_service; then
    mv "$rollback_tmp" "$BIN_BACKUP_PATH"
    chmod 755 "$BIN_BACKUP_PATH"
    ui_success "Mihomo 已回滚并正常运行：$($BIN_PATH -v 2>/dev/null | sed -n '1p')"
  else
    mv "$rollback_tmp" "$BIN_PATH"
    chmod 755 "$BIN_PATH"
    restart_service >/dev/null 2>&1 || true
    ui_error "上一版本无法加载当前配置，已恢复回滚前内核。"
    return 1
  fi
}

ensure_installed() {
  if [ ! -x "$BIN_PATH" ] || [ ! -f "$CONFIG_FILE" ]; then
    red "mihomo 尚未安装，请先在菜单输入 4 安装内核。"
    exit 1
  fi
}

node_name_exists() {
  name="$1"
  awk -F'|' -v n="$name" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      if ($2 == n) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$NODES_DB" 2>/dev/null
}

system_port_in_use() {
  check_port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | awk -v p="$check_port" '
      NR > 1 {
        address = $5
        sub(/^.*:/, "", address)
        if (address == p) found = 1
      }
      END { exit found ? 0 : 1 }
    ' && return 0
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | awk -v p="$check_port" '
      NR > 2 {
        address = $4
        sub(/^.*:/, "", address)
        if (address == p) found = 1
      }
      END { exit found ? 0 : 1 }
    ' && return 0
  fi

  port_hex="$(printf '%04X' "$check_port" 2>/dev/null || printf '')"
  [ -n "$port_hex" ] || return 1
  for socket_file in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
    [ -r "$socket_file" ] || continue
    awk -v hex="$port_hex" '
      NR > 1 {
        split($2, local, ":")
        if (toupper(local[2]) == hex) found = 1
      }
      END { exit found ? 0 : 1 }
    ' "$socket_file" && return 0
  done
  return 1
}

port_owned_by_process() {
  owned_port="$1"
  owned_process="$2"
  command -v ss >/dev/null 2>&1 || return 2
  ss -lntup 2>/dev/null | awk -v p="$owned_port" -v proc="$owned_process" '
    {
      address = $5
      sub(/^.*:/, "", address)
      if (address == p && index($0, proc) > 0) found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

port_bound_to_loopback() {
  loop_port="$1"
  command -v ss >/dev/null 2>&1 || return 2
  ss -lntu 2>/dev/null | awk -v p="$loop_port" '
    {
      address = $5
      raw = address
      sub(/^.*:/, "", address)
      if (address == p) {
        found = 1
        if (raw !~ /^127\.0\.0\.1:/ && raw !~ /^\[::1\]:/) public_bind = 1
      }
    }
    END { if (!found) exit 2; exit public_bind ? 1 : 0 }
  '
}

port_in_use() {
  port="$1"
  if awk -F'|' -v p="$port" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      if ($3 == p) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$NODES_DB" 2>/dev/null; then
    return 0
  fi

  if [ -s "$USERS_DB" ] && awk -F'|' -v p="$port" '
      NF >= 11 && $11 == p { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$USERS_DB" 2>/dev/null; then
    return 0
  fi

  system_port_in_use "$port"
}

check_internal_ports() {
  check_scope="${1:-all}"
  if [ "$check_scope" != "cloudflared" ]; then
  for reserved_port in 7890 9090 1053; do
    if system_port_in_use "$reserved_port"; then
      if command -v ss >/dev/null 2>&1 && port_owned_by_process "$reserved_port" "mihomo"; then
        continue
      fi
      ui_error "Mihomo 内部端口 $reserved_port 已被其他进程占用。"
      return 1
    fi
  done
  fi
  [ "$check_scope" != "mihomo" ] || return 0
  if system_port_in_use 20241; then
    if command -v ss >/dev/null 2>&1 && port_owned_by_process 20241 "cloudflared"; then
      return 0
    fi
    ui_error "cloudflared 内部监控端口 20241 已被其他进程占用。"
    return 1
  fi
}

remove_users_for_node() {
  removed_node="$1"
  [ -s "$USERS_DB" ] || return 0
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v node="$removed_node" 'BEGIN { OFS = FS } NF >= 9 && $2 == node { next } { print }' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  reset_user_traffic_snapshot 2>/dev/null || true
}

ensure_iptables() {
  command -v iptables >/dev/null 2>&1 || install_packages iptables
  if traffic_ipv6_enabled && ! command -v ip6tables >/dev/null 2>&1; then
    install_packages iptables
  fi
}

iptables_cmd() {
  if command -v iptables >/dev/null 2>&1; then
    printf 'iptables'
    return 0
  fi
  return 1
}

ip6tables_cmd() {
  if command -v ip6tables >/dev/null 2>&1; then
    printf 'ip6tables'
    return 0
  fi
  return 1
}

traffic_ipv6_enabled() {
  load_network_settings
  [ "$MIHOMO_IPV6" = "true" ]
}

traffic_rules_current() {
  [ -r "$TRAFFIC_RULES_VERSION_FILE" ] || return 1
  read -r traffic_rules_version < "$TRAFFIC_RULES_VERSION_FILE" || return 1
  [ "$traffic_rules_version" = "$TRAFFIC_RULES_VERSION" ]
}

setup_user_traffic_rules_for_cmd() {
  traffic_fw="$1"
  traffic_family="$2"

  "$traffic_fw" -N "$TRAFFIC_CHAIN_IN" 2>/dev/null || true
  "$traffic_fw" -N "$TRAFFIC_CHAIN_OUT" 2>/dev/null || true
  "$traffic_fw" -F "$TRAFFIC_CHAIN_IN" 2>/dev/null || {
    ui_error "无法写入 $traffic_family 统计链。LXC 容器可能缺少 NET_ADMIN 权限。"
    return 1
  }
  "$traffic_fw" -F "$TRAFFIC_CHAIN_OUT" 2>/dev/null || {
    ui_error "无法写入 $traffic_family 统计链。LXC 容器可能缺少 NET_ADMIN 权限。"
    return 1
  }
  "$traffic_fw" -C INPUT -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || "$traffic_fw" -I INPUT 1 -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || {
    ui_error "无法挂载 $traffic_family 入站统计链。请检查容器权限。"
    return 1
  }
  "$traffic_fw" -C OUTPUT -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || "$traffic_fw" -I OUTPUT 1 -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || {
    ui_error "无法挂载 $traffic_family 出站统计链。请检查容器权限。"
    return 1
  }
}

append_user_traffic_rules_for_cmd() {
  traffic_fw="$1"
  [ -s "$USERS_DB" ] || return 0
  while IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra; do
    [ -n "$user_name" ] || continue
    case "${user_port:-}" in ''|*[!0-9]*) continue ;; esac
    is_user_active "$user_enabled" "$user_expire" "$user_quota" "$user_used" || continue
    case "$user_proto" in
      hysteria2)
        "$traffic_fw" -A "$TRAFFIC_CHAIN_IN" -p udp --dport "$user_port" 2>/dev/null || true
        "$traffic_fw" -A "$TRAFFIC_CHAIN_OUT" -p udp --sport "$user_port" 2>/dev/null || true
        ;;
      vless-reality|vless-ws|anytls)
        "$traffic_fw" -A "$TRAFFIC_CHAIN_IN" -p tcp --dport "$user_port" 2>/dev/null || true
        "$traffic_fw" -A "$TRAFFIC_CHAIN_OUT" -p tcp --sport "$user_port" 2>/dev/null || true
        ;;
      *)
        "$traffic_fw" -A "$TRAFFIC_CHAIN_IN" -p tcp --dport "$user_port" 2>/dev/null || true
        "$traffic_fw" -A "$TRAFFIC_CHAIN_IN" -p udp --dport "$user_port" 2>/dev/null || true
        "$traffic_fw" -A "$TRAFFIC_CHAIN_OUT" -p tcp --sport "$user_port" 2>/dev/null || true
        "$traffic_fw" -A "$TRAFFIC_CHAIN_OUT" -p udp --sport "$user_port" 2>/dev/null || true
        ;;
    esac
  done < "$USERS_DB"
}

traffic_counter_lines_for_cmd() {
  traffic_fw="$1"
  "$traffic_fw" -x -v -n -L "$TRAFFIC_CHAIN_IN" 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
      bytes = $2 + 0
      port = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "dpt:" && (i + 1) <= NF) port = $(i + 1)
        else if ($i ~ /^dpt:[0-9]+$/) { port = $i; sub(/^dpt:/, "", port) }
      }
      if (port != "") print port "|" bytes
    }'
  "$traffic_fw" -x -v -n -L "$TRAFFIC_CHAIN_OUT" 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
      bytes = $2 + 0
      port = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "spt:" && (i + 1) <= NF) port = $(i + 1)
        else if ($i ~ /^spt:[0-9]+$/) { port = $i; sub(/^spt:/, "", port) }
      }
      if (port != "") print port "|" bytes
    }'
}

cleanup_user_traffic_rules_for_cmd() {
  traffic_fw="$1"
  while "$traffic_fw" -C INPUT -j "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1; do
    "$traffic_fw" -D INPUT -j "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1 || break
  done
  while "$traffic_fw" -C OUTPUT -j "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1; do
    "$traffic_fw" -D OUTPUT -j "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1 || break
  done
  "$traffic_fw" -F "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1 || true
  "$traffic_fw" -F "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1 || true
  "$traffic_fw" -X "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1 || true
  "$traffic_fw" -X "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1 || true
}

reset_user_traffic_snapshot() {
  tmp_file="$(make_temp "$CONFIG_DIR/traffic.XXXXXX")"
  if [ -s "$USERS_DB" ]; then
    while IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra; do
      [ -n "$user_name" ] || continue
      case "${user_port:-}" in ''|*[!0-9]*) continue ;; esac
      is_user_active "$user_enabled" "$user_expire" "$user_quota" "$user_used" || continue
      printf '%s|0\n' "$user_port"
    done < "$USERS_DB" > "$tmp_file"
  else
    : > "$tmp_file"
  fi
  mv "$tmp_file" "$TRAFFIC_DB"
  chmod 600 "$TRAFFIC_DB"
}

refresh_user_traffic_rules() {
  ensure_multi_user_enabled
  ensure_user_ports
  ensure_iptables
  ipt="$(iptables_cmd)" || {
    ui_error "未找到 iptables，无法启用 IPv4 端口级流量统计。"
    return 1
  }
  ip6t=""
  if traffic_ipv6_enabled; then
    ip6t="$(ip6tables_cmd)" || {
      ui_error "IPv6 已开启，但未找到 ip6tables，无法统计 IPv6 用户流量。"
      return 1
    }
  fi

  setup_user_traffic_rules_for_cmd "$ipt" "IPv4" || return 1

  if [ -n "$ip6t" ]; then
    setup_user_traffic_rules_for_cmd "$ip6t" "IPv6" || return 1
  fi

  append_user_traffic_rules_for_cmd "$ipt"
  if [ -n "$ip6t" ]; then
    append_user_traffic_rules_for_cmd "$ip6t"
  fi
  reset_user_traffic_snapshot
  printf '%s\n' "$TRAFFIC_RULES_VERSION" > "$TRAFFIC_RULES_VERSION_FILE"
  chmod 600 "$TRAFFIC_RULES_VERSION_FILE"
}

refresh_user_traffic_rules_if_available() {
  command -v iptables >/dev/null 2>&1 || return 0
  refresh_user_traffic_rules
}

ensure_user_traffic_rules_ready() {
  ensure_iptables
  ipt="$(iptables_cmd)" || return 1
  if ! traffic_rules_current; then
    refresh_user_traffic_rules
    return $?
  fi
  if ! "$ipt" -L "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1 || ! "$ipt" -L "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1; then
    refresh_user_traffic_rules
    return $?
  fi
  "$ipt" -C INPUT -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || "$ipt" -I INPUT 1 -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || return 1
  "$ipt" -C OUTPUT -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || "$ipt" -I OUTPUT 1 -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || return 1
  if traffic_ipv6_enabled; then
    ip6t="$(ip6tables_cmd)" || return 1
    if ! "$ip6t" -L "$TRAFFIC_CHAIN_IN" >/dev/null 2>&1 || ! "$ip6t" -L "$TRAFFIC_CHAIN_OUT" >/dev/null 2>&1; then
      refresh_user_traffic_rules
      return $?
    fi
    "$ip6t" -C INPUT -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || "$ip6t" -I INPUT 1 -j "$TRAFFIC_CHAIN_IN" 2>/dev/null || return 1
    "$ip6t" -C OUTPUT -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || "$ip6t" -I OUTPUT 1 -j "$TRAFFIC_CHAIN_OUT" 2>/dev/null || return 1
  fi
}

cleanup_user_traffic_rules() {
  if command -v iptables >/dev/null 2>&1; then
    ipt="$(iptables_cmd)" && cleanup_user_traffic_rules_for_cmd "$ipt"
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    ip6t="$(ip6tables_cmd)" && cleanup_user_traffic_rules_for_cmd "$ip6t"
  fi
  rm -f "$TRAFFIC_RULES_VERSION_FILE"
}

prompt_node_name() {
  proto_prefix="$1"
  default_name="${2:-$proto_prefix}"
  ui_prompt "请输入节点名称（默认 $default_name）："
  read -r node_name || true
  if [ -z "$node_name" ]; then
    node_name="$default_name"
  fi
  node_name="$(printf '%s' "$node_name" | tr -cd 'A-Za-z0-9_.-')"
  if [ -z "$node_name" ]; then
    red "节点名称无效，只能包含字母、数字、下划线、点和短横线。"
    return 1
  fi

  if node_name_exists "$node_name"; then
    red "节点 $node_name 已存在。"
    return 1
  fi
  SELECTED_NODE_NAME="$node_name"
}

prompt_port() {
  default_port="$(random_port)"
  ui_prompt "请输入监听端口（默认 $default_port）："
  read -r node_port || true
  [ -n "$node_port" ] || node_port="$default_port"

  case "$node_port" in
    ''|*[!0-9]*)
      red "端口必须是数字。"
      return 1
      ;;
  esac
  if [ "$node_port" -lt 1 ] || [ "$node_port" -gt 65535 ]; then
    red "端口范围必须为 1-65535。"
    return 1
  fi

  if port_in_use "$node_port"; then
    red "端口 $node_port 已被其他节点、用户或系统进程占用。"
    return 1
  fi
  SELECTED_NODE_PORT="$node_port"
}

append_node() {
  state_transaction_begin || return 1
  printf '%s\n' "$1" >> "$NODES_DB"
  chmod 600 "$NODES_DB"
  state_transaction_apply
}

state_transaction_begin() {
  mkdir -p "$CONFIG_DIR"
  if ! mkdir "$STATE_LOCK_DIR" 2>/dev/null; then
    state_lock_pid="$(cat "$STATE_LOCK_DIR/pid" 2>/dev/null || true)"
    case "$state_lock_pid" in ''|*[!0-9]*) state_lock_alive=0 ;; *) if kill -0 "$state_lock_pid" 2>/dev/null; then state_lock_alive=1; else state_lock_alive=0; fi ;; esac
    if [ "$state_lock_alive" = "1" ]; then
      ui_error "另一个 mh 进程正在修改配置（PID $state_lock_pid），请稍后重试。"
      return 1
    fi
    stale_tx_dir="$(cat "$STATE_LOCK_DIR/txdir" 2>/dev/null || true)"
    case "$stale_tx_dir" in
      "$CONFIG_DIR"/.state-tx.*)
        if [ -d "$stale_tx_dir" ]; then
          STATE_TX_DIR="$stale_tx_dir"
          state_transaction_restore_files
          rm -rf "$stale_tx_dir"
          ui_warn "检测到上次未完成的配置操作，已恢复数据库快照。"
        fi
        ;;
    esac
    rm -rf "$STATE_LOCK_DIR"
    mkdir "$STATE_LOCK_DIR" 2>/dev/null || { ui_error "无法取得配置修改锁。"; return 1; }
  fi
  printf '%s\n' "$$" > "$STATE_LOCK_DIR/pid"
  STATE_TX_DIR="$(mktemp -d "$CONFIG_DIR/.state-tx.XXXXXX" 2>/dev/null)" || {
    rm -rf "$STATE_LOCK_DIR"
    ui_error "无法创建状态事务目录。"
    return 1
  }
  printf '%s\n' "$STATE_TX_DIR" > "$STATE_LOCK_DIR/txdir"
  for state_file in nodes.db users.db traffic.db runtime.env network.env features.env multi-user.enabled; do
    if [ -e "$CONFIG_DIR/$state_file" ]; then
      cp "$CONFIG_DIR/$state_file" "$STATE_TX_DIR/$state_file"
    else
      : > "$STATE_TX_DIR/$state_file.missing"
    fi
  done
  trap 'state_transaction_abort' HUP INT TERM
}

state_transaction_commit() {
  [ -n "${STATE_TX_DIR:-}" ] && [ -d "$STATE_TX_DIR" ] && rm -rf "$STATE_TX_DIR"
  rm -rf "$STATE_LOCK_DIR"
  STATE_TX_DIR=""
  trap - HUP INT TERM
}

state_transaction_abort() {
  state_transaction_restore_files
  state_transaction_commit
  ui_error "操作被中断，节点、用户和运行设置已恢复。"
  exit 130
}

state_transaction_restore_files() {
  [ -n "${STATE_TX_DIR:-}" ] && [ -d "$STATE_TX_DIR" ] || return 0
  for state_file in nodes.db users.db traffic.db runtime.env network.env features.env multi-user.enabled; do
    if [ -f "$STATE_TX_DIR/$state_file" ]; then
      cp "$STATE_TX_DIR/$state_file" "$CONFIG_DIR/$state_file"
      chmod 600 "$CONFIG_DIR/$state_file"
    elif [ -f "$STATE_TX_DIR/$state_file.missing" ]; then
      rm -f "$CONFIG_DIR/$state_file"
    fi
  done
}

state_transaction_apply() {
  if render_config && restart_service; then
    state_transaction_commit
    return 0
  fi
  ui_error "状态变更未能安全生效，正在恢复节点、用户和运行设置。"
  state_transaction_restore_files
  render_config >/dev/null 2>&1 || true
  restart_service >/dev/null 2>&1 || true
  state_transaction_commit
  ui_warn "数据库与运行配置已恢复到操作前状态。"
  return 1
}

append_node_record() {
  printf '%s\n' "$1" >> "$NODES_DB"
  chmod 600 "$NODES_DB"
}

unique_node_name() {
  base="$1"
  name="$base"
  suffix=2
  while node_name_exists "$name"; do
    name="${base}-${suffix}"
    suffix=$((suffix + 1))
  done
  printf '%s' "$name"
}

unique_port() {
  while true; do
    port="$(random_port)"
    case " ${RESERVED_PORTS:-} " in
      *" $port "*) continue ;;
    esac
    if ! port_in_use "$port"; then
      RESERVED_PORTS="${RESERVED_PORTS:-} $port"
      printf '%s' "$port"
      return 0
    fi
  done
}

country_profile() {
  country="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$country" in
    cn|china|中国|中國) printf '🇨🇳|China' ;;
    hk|hongkong|hong\ kong|香港) printf '🇭🇰|Hong Kong' ;;
    tw|taiwan|台湾|台灣) printf '🇹🇼|Taiwan' ;;
    jp|japan|日本) printf '🇯🇵|Japan' ;;
    kr|korea|south\ korea|韩国|韓國|南韩|南韓) printf '🇰🇷|South Korea' ;;
    sg|singapore|新加坡) printf '🇸🇬|Singapore' ;;
    us|usa|united\ states|america|美国|美國) printf '🇺🇸|United States' ;;
    uk|gb|united\ kingdom|britain|英国|英國) printf '🇬🇧|United Kingdom' ;;
    de|germany|德国|德國) printf '🇩🇪|Germany' ;;
    fr|france|法国|法國) printf '🇫🇷|France' ;;
    nl|netherlands|荷兰|荷蘭) printf '🇳🇱|Netherlands' ;;
    ch|switzerland|瑞士) printf '🇨🇭|Switzerland' ;;
    it|italy|意大利) printf '🇮🇹|Italy' ;;
    es|spain|西班牙) printf '🇪🇸|Spain' ;;
    se|sweden|瑞典) printf '🇸🇪|Sweden' ;;
    ca|canada|加拿大) printf '🇨🇦|Canada' ;;
    au|australia|澳大利亚|澳洲|澳大利亞) printf '🇦🇺|Australia' ;;
    ru|russia|俄罗斯|俄羅斯) printf '🇷🇺|Russia' ;;
    ae|uae|united\ arab\ emirates|阿联酋|阿聯酋) printf '🇦🇪|United Arab Emirates' ;;
    in|india|印度) printf '🇮🇳|India' ;;
    br|brazil|巴西) printf '🇧🇷|Brazil' ;;
    tr|turkey|土耳其) printf '🇹🇷|Turkey' ;;
    th|thailand|泰国|泰國) printf '🇹🇭|Thailand' ;;
    vn|vietnam|越南) printf '🇻🇳|Vietnam' ;;
    my|malaysia|马来西亚|馬來西亞) printf '🇲🇾|Malaysia' ;;
    id|indonesia|印度尼西亚|印尼|印度尼西亞) printf '🇮🇩|Indonesia' ;;
    ph|philippines|菲律宾|菲律賓) printf '🇵🇭|Philippines' ;;
    *) return 1 ;;
  esac
}

protocol_label() {
  case "$1" in
    vless-reality) printf 'Reality' ;;
    hysteria2) printf 'Hysteria2' ;;
    anytls) printf 'AnyTLS' ;;
    vless-ws) printf 'VLESS-WS' ;;
    *) printf '%s' "$1" ;;
  esac
}

sanitize_label() {
  sanitize_db_field "$1" | tr -d '/'
}

node_share_link() {
  proto="$1"
  node_name="$2"
  node_port="$3"
  value1="${4:-}"
  value2="${5:-}"
  value3="${6:-}"
  value4="${7:-}"
  value5="${8:-}"
  value6="${9:-}"
  server_ip="${SHARE_SERVER_IP:-$(public_ip)}"
  server_host="$(format_link_host "$server_ip")"
  link_name="$(url_path "$node_name")"

  case "$proto" in
    vless-reality)
      node_uuid="$value1"
      sni="$(url_query "$value2")"
      public_key="$(url_query "$value5")"
      short_id="$(url_query "$value6")"
      printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s\n' \
        "$node_uuid" "$server_host" "$node_port" "$sni" "$public_key" "$short_id" "$link_name"
      ;;
    hysteria2)
      node_password="$(url_path "$value1")"
      sni="$(url_query "$value2")"
      salamander_password="$(url_query "$value5")"
      if [ -n "$salamander_password" ]; then
        printf 'hysteria2://%s@%s:%s?insecure=1&sni=%s&upmbps=%s&downmbps=%s&obfs=salamander&obfs-password=%s#%s\n' \
          "$node_password" "$server_host" "$node_port" "$sni" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS" "$salamander_password" "$link_name"
      else
        printf 'hysteria2://%s@%s:%s?insecure=1&sni=%s&upmbps=%s&downmbps=%s#%s\n' \
          "$node_password" "$server_host" "$node_port" "$sni" "$HY2_UP_MBPS" "$HY2_DOWN_MBPS" "$link_name"
      fi
      ;;
    anytls)
      node_password="$(url_path "$value1")"
      sni="$(url_query "$value2")"
      printf 'anytls://%s@%s:%s?insecure=1&sni=%s#%s\n' \
        "$node_password" "$server_host" "$node_port" "$sni" "$link_name"
      ;;
    vless-ws)
      node_uuid="$value1"
      ws_path="$(url_path "$value2")"
      ws_host="${value3:-}"
      ws_mode="${value4:-legacy}"
      ws_entry_address="${value5:-}"
      ws_entry_port="${value6:-}"
      case "$ws_mode" in
        direct)
          [ -n "$ws_entry_port" ] || ws_entry_port="$node_port"
          printf 'vless://%s@%s:%s?encryption=none&security=none&type=ws&path=%s#%s\n' \
            "$node_uuid" "$server_host" "$ws_entry_port" "$ws_path" "$link_name"
          ;;
        cdn|argo)
          [ -n "$ws_entry_address" ] || ws_entry_address="$ws_host"
          [ -n "$ws_entry_port" ] || ws_entry_port="443"
          ws_entry_host="$(format_link_host "$ws_entry_address")"
          ws_host_query="$(url_query "$ws_host")"
          ws_sni_query="$(url_query "$ws_host")"
          printf 'vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&type=ws&host=%s&path=%s#%s\n' \
            "$node_uuid" "$ws_entry_host" "$ws_entry_port" "$ws_sni_query" "$ws_host_query" "$ws_path" "$link_name"
          ;;
        *)
          ws_host="${ws_host:-$server_host}"
          ws_host_query="$(url_query "$ws_host")"
          printf 'vless://%s@%s:%s?encryption=none&security=none&type=ws&host=%s&path=%s#%s\n' \
            "$node_uuid" "$server_host" "$node_port" "$ws_host_query" "$ws_path" "$link_name"
          ;;
      esac
      ;;
  esac
}

print_node_link() {
  proto="$1"
  node_name="$2"
  node_port="$3"
  value1="${4:-}"
  value2="${5:-}"
  value3="${6:-}"
  value4="${7:-}"
  value5="${8:-}"
  value6="${9:-}"
  if [ -z "$node_name" ] || [ -z "$node_port" ]; then
    red "生成节点链接失败：节点名称或端口为空。"
    return 1
  fi
  node_link="$(node_share_link "$proto" "$node_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6")"
  link_notice="请确认 VPS 防火墙和云厂商安全组已放行 TCP/UDP $node_port"
  if [ "$proto" = "vless-ws" ]; then
    case "$value4" in
      argo) link_notice="Argo 本地监听 127.0.0.1:$node_port，无需开放或映射该端口" ;;
      direct) link_notice="请确认公网 TCP ${value6:-$node_port} 已映射到本地 $node_port" ;;
      cdn) link_notice="请确认源站端口 $node_port 可达，客户端 Cloudflare 入口为 ${value6:-443}" ;;
    esac
  fi
  cat <<EOF

${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[!]${C_RESET} $link_notice

 ${C_GREEN}[+] 节点链接${C_RESET}
$node_link
${C_CYAN}----------------------------------------------------${C_RESET}
EOF
}

add_vless_reality_node() {
  screen_title "创建 VLESS + Reality 节点"
  prompt_node_name vless-reality || return 1
  node_name="$SELECTED_NODE_NAME"
  prompt_port || return 1
  node_port="$SELECTED_NODE_PORT"
  ui_prompt "请输入 Reality SNI（默认 www.amd.com）："
  read -r sni || true
  [ -n "$sni" ] || sni="www.amd.com"
  sni="$(sanitize_sni_field "$sni")"
  [ -n "$sni" ] || sni="www.amd.com"
  dest="${sni}:443"
  node_uuid="$(new_uuid)"
  key_pair="$(create_reality_keypair)" || { ui_error "Reality 密钥生成失败。"; return 1; }
  private_key="${key_pair%%|*}"
  public_key="${key_pair#*|}"
  short_id="$(rand_hex 8)"
  append_node "vless-reality|$node_name|$node_port|$node_uuid|$sni|$dest|$private_key|$public_key|$short_id"
  ui_success "VLESS + Reality 节点已生成并重启服务。"
  print_node_link vless-reality "$node_name" "$node_port" "$node_uuid" "$sni" "$dest" "$private_key" "$public_key" "$short_id"
}

add_hysteria2_node() {
  screen_title "创建 Hysteria2 节点"
  prompt_node_name hy2 || return 1
  node_name="$SELECTED_NODE_NAME"
  prompt_port || return 1
  node_port="$SELECTED_NODE_PORT"
  ui_prompt "请输入 TLS SNI / 证书域名（默认 www.amd.com）："
  read -r sni || true
  [ -n "$sni" ] || sni="www.amd.com"
  sni="$(sanitize_sni_field "$sni")"
  [ -n "$sni" ] || sni="www.amd.com"
  default_password="$(rand_alnum 32)"
  ui_prompt "请输入 Hysteria2 密码（默认随机生成）："
  read -r node_password || true
  [ -n "$node_password" ] || node_password="$default_password"
  node_password="$(printf '%s' "$node_password" | tr -cd 'A-Za-z0-9._~-')"
  [ -n "$node_password" ] || node_password="$default_password"
  ui_prompt "是否开启 Salamander 混淆？会增加 CPU 占用，低配机器建议关闭 [y/N]："
  read -r enable_salamander || true
  salamander_password=""
  case "$enable_salamander" in
    y|Y|yes|YES)
      salamander_password="$(rand_alnum 32)"
      ;;
  esac
  cert_pair="$(ensure_tls_cert "$node_name" "$sni")" || { ui_error "Hysteria2 证书生成失败。"; return 1; }
  cert_file="${cert_pair%%|*}"
  key_file="${cert_pair#*|}"
  append_node "hysteria2|$node_name|$node_port|$node_password|$sni|$cert_file|$key_file|$salamander_password|"
  ui_success "Hysteria2 节点已生成并重启服务。"
  print_node_link hysteria2 "$node_name" "$node_port" "$node_password" "$sni" "$cert_file" "$key_file" "$salamander_password" ""
}

add_anytls_node() {
  screen_title "创建 AnyTLS 节点"
  prompt_node_name anytls || return 1
  node_name="$SELECTED_NODE_NAME"
  prompt_port || return 1
  node_port="$SELECTED_NODE_PORT"
  ui_prompt "请输入 TLS SNI / 证书域名（默认 www.amd.com）："
  read -r sni || true
  [ -n "$sni" ] || sni="www.amd.com"
  sni="$(sanitize_sni_field "$sni")"
  [ -n "$sni" ] || sni="www.amd.com"
  node_password="$(rand_alnum 32)"
  cert_pair="$(ensure_tls_cert "$node_name" "$sni")" || { ui_error "AnyTLS 证书生成失败。"; return 1; }
  cert_file="${cert_pair%%|*}"
  key_file="${cert_pair#*|}"
  append_node "anytls|$node_name|$node_port|$node_password|$sni|$cert_file|$key_file||"
  ui_success "AnyTLS 节点已生成并重启服务。"
  print_node_link anytls "$node_name" "$node_port" "$node_password" "$sni" "$cert_file" "$key_file" "" ""
}

add_vless_ws_node() {
  screen_title "创建 VLESS + WebSocket 节点"
  cat <<EOF
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}1.${C_RESET} IP 直连 WS（需要公网端口映射）
 ${C_GREEN}2.${C_RESET} Cloudflare 小黄云 CDN WS-TLS（需要受支持的公网端口）
 ${C_GREEN}3.${C_RESET} Cloudflare Tunnel / Argo WS-TLS（无需端口映射、不要预建 A/AAAA）
 ${C_GREEN}0.${C_RESET} 返回
${C_CYAN}----------------------------------------------------${C_RESET}
EOF
  ui_prompt "请选择使用模式 (0-3)："
  read -r ws_mode_choice || true

  case "$ws_mode_choice" in
    0) ui_warn "已取消创建 VLESS-WS 节点。"; return 0 ;;
    1|2|3) ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac

  ws_default_name="$(unique_node_name vless-ws)"
  prompt_node_name vless-ws "$ws_default_name" || return 1
  node_name="$SELECTED_NODE_NAME"
  prompt_port || return 1
  node_port="$SELECTED_NODE_PORT"

  ws_host=""
  ws_mode=""
  ws_entry_address=""
  ws_entry_port=""
  case "$ws_mode_choice" in
    1)
      ws_mode="direct"
      ui_prompt "请输入 NAT 公网映射端口（默认与本地端口 $node_port 相同）："
      read -r ws_entry_port || true
      [ -n "$ws_entry_port" ] || ws_entry_port="$node_port"
      case "$ws_entry_port" in
        ''|*[!0-9]*) ui_error "公网映射端口必须是数字。"; return 1 ;;
      esac
      if [ "$ws_entry_port" -lt 1 ] || [ "$ws_entry_port" -gt 65535 ]; then
        ui_error "公网映射端口范围必须为 1-65535。"
        return 1
      fi
      ;;
    2)
      ws_mode="cdn"
      ui_warn "小黄云模式需要先创建指向公网 IP 的代理 DNS 记录；随机 NAT 端口可能不受 Cloudflare 支持。"
      ui_prompt "请输入 Cloudflare 真实域名（用于 SNI/Host）："
      read -r ws_host || true
      ws_host="$(sanitize_sni_field "$ws_host")"
      is_valid_hostname "$ws_host" || { ui_error "小黄云模式必须填写有效的完整域名。"; return 1; }
      ui_prompt "请输入 CDN 入口地址（默认 $ws_host，可填写优选域名/IP）："
      read -r ws_entry_address || true
      [ -n "$ws_entry_address" ] || ws_entry_address="$ws_host"
      ws_entry_address="$(sanitize_db_field "$ws_entry_address" | tr -d '[:space:]')"
      is_valid_endpoint "$ws_entry_address" || { ui_error "CDN 入口必须是有效域名或 IP。"; return 1; }
      ui_prompt "请输入 CDN 入口端口（默认 443）："
      read -r ws_entry_port || true
      [ -n "$ws_entry_port" ] || ws_entry_port="443"
      ;;
    3)
      ws_mode="argo"
      ui_warn "Argo 模式不要提前创建同名 A/AAAA 记录；请在 Tunnel 路由中添加公共主机名，由 Cloudflare 自动创建 CNAME。"
      ui_prompt "请输入计划使用的 Tunnel 公共主机名："
      read -r ws_host || true
      ws_host="$(sanitize_sni_field "$ws_host")"
      is_valid_hostname "$ws_host" || { ui_error "Argo 模式必须填写有效的 Tunnel 公共主机名。"; return 1; }
      ui_prompt "请输入客户端入口地址（默认 $ws_host，可填写优选域名/IP）："
      read -r ws_entry_address || true
      [ -n "$ws_entry_address" ] || ws_entry_address="$ws_host"
      ws_entry_address="$(sanitize_db_field "$ws_entry_address" | tr -d '[:space:]')"
      is_valid_endpoint "$ws_entry_address" || { ui_error "客户端入口必须是有效域名或 IP。"; return 1; }
      ws_entry_port="443"
      ;;
  esac

  case "$ws_entry_port" in
    ''|*[!0-9]*) ui_error "入口端口必须是数字。"; return 1 ;;
  esac
  if [ "$ws_entry_port" -lt 1 ] || [ "$ws_entry_port" -gt 65535 ]; then
    ui_error "入口端口范围必须为 1-65535。"
    return 1
  fi

  default_path="/$(rand_alnum 10)"
  ui_prompt "请输入 WebSocket 路径（默认 $default_path）："
  read -r ws_path || true
  [ -n "$ws_path" ] || ws_path="$default_path"
  ws_path="$(sanitize_db_field "$ws_path")"
  case "$ws_path" in
    /*) ;;
    *) ws_path="/$ws_path" ;;
  esac
  node_uuid="$(new_uuid)"
  append_node "vless-ws|$node_name|$node_port|$node_uuid|$ws_path|$ws_host|$ws_mode|$ws_entry_address|$ws_entry_port"
  ui_success "VLESS + WS 节点已生成并重启服务。"
  if [ "$ws_mode" = "argo" ]; then
    ui_warn "Tunnel 路由服务请填写：http://127.0.0.1:$node_port"
    ui_warn "公共主机名：$ws_host（不要手动创建 A/AAAA；Tunnel 会自动创建 CNAME）"
  fi
  print_node_link vless-ws "$node_name" "$node_port" "$node_uuid" "$ws_path" "$ws_host" "$ws_mode" "$ws_entry_address" "$ws_entry_port"
}

add_combo_nodes() {
  need_root
  ensure_installed
  screen_title "一键生成 Reality + Hysteria2 + AnyTLS 节点"

  sni="www.amd.com"
  RESERVED_PORTS=""
  reality_name="$(unique_node_name vless-reality)"
  reality_port="$(unique_port)"
  reality_uuid="$(new_uuid)"
  reality_key_pair="$(create_reality_keypair)" || { ui_error "Reality 密钥生成失败。"; return 1; }
  reality_private_key="${reality_key_pair%%|*}"
  reality_public_key="${reality_key_pair#*|}"
  reality_short_id="$(rand_hex 8)"
  reality_dest="${sni}:443"

  hy2_name="$(unique_node_name hy2)"
  hy2_port="$(unique_port)"
  hy2_password="$(rand_alnum 32)"
  hy2_cert_pair="$(ensure_tls_cert "$hy2_name" "$sni")" || { ui_error "Hysteria2 证书生成失败。"; return 1; }
  hy2_cert_file="${hy2_cert_pair%%|*}"
  hy2_key_file="${hy2_cert_pair#*|}"

  anytls_name="$(unique_node_name anytls)"
  anytls_port="$(unique_port)"
  anytls_password="$(rand_alnum 32)"
  anytls_cert_pair="$(ensure_tls_cert "$anytls_name" "$sni")" || { ui_error "AnyTLS 证书生成失败。"; return 1; }
  anytls_cert_file="${anytls_cert_pair%%|*}"
  anytls_key_file="${anytls_cert_pair#*|}"

  state_transaction_begin || return 1
  append_node_record "vless-reality|$reality_name|$reality_port|$reality_uuid|$sni|$reality_dest|$reality_private_key|$reality_public_key|$reality_short_id"
  append_node_record "hysteria2|$hy2_name|$hy2_port|$hy2_password|$sni|$hy2_cert_file|$hy2_key_file||"
  append_node_record "anytls|$anytls_name|$anytls_port|$anytls_password|$sni|$anytls_cert_file|$anytls_key_file||"
  state_transaction_apply || return 1

  SHARE_SERVER_IP="$(public_ip)"
  export SHARE_SERVER_IP
  ui_success "Reality + Hysteria2 + AnyTLS 节点已生成并重启服务。"
  print_node_link vless-reality "$reality_name" "$reality_port" "$reality_uuid" "$sni" "$reality_dest" "$reality_private_key" "$reality_public_key" "$reality_short_id"
  print_node_link hysteria2 "$hy2_name" "$hy2_port" "$hy2_password" "$sni" "$hy2_cert_file" "$hy2_key_file" "" ""
  print_node_link anytls "$anytls_name" "$anytls_port" "$anytls_password" "$sni" "$anytls_cert_file" "$anytls_key_file" "" ""
}

rename_all_nodes() {
  need_root
  ensure_installed
  screen_title "一键重命名所有节点"

  if [ ! -s "$NODES_DB" ]; then
    ui_warn "当前没有节点。"
    return 0
  fi

  ui_prompt "请输入国家/地区（如 Japan、日本、US、美国）："
  read -r country_input || true
  country_input="$(sanitize_label "$country_input")"
  if [ -z "$country_input" ]; then
    ui_error "国家/地区不能为空。"
    return 1
  fi

  country_info="$(country_profile "$country_input" || true)"
  if [ -n "$country_info" ]; then
    country_emoji="${country_info%%|*}"
    country_name="${country_info#*|}"
  else
    ui_prompt "未识别该国家，请手动输入国家旗帜 Emoji："
    read -r country_emoji || true
    country_name="$country_input"
    if [ -z "$country_emoji" ]; then
      ui_error "国家旗帜 Emoji 不能为空。"
      return 1
    fi
  fi

  ui_prompt "请输入服务商名称："
  read -r provider || true
  provider="$(sanitize_label "$provider")"
  if [ -z "$provider" ]; then
    ui_error "服务商名称不能为空。"
    return 1
  fi

  tmp_file="$(make_temp "$CONFIG_DIR/nodes.XXXXXX")"
  rename_map_file="$(make_temp "$CONFIG_DIR/rename-map.XXXXXX")"
  reality_count=0
  hy2_count=0
  anytls_count=0
  ws_count=0
  while IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6; do
    db_line="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' "$proto" "$node_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6")"
    [ -n "$proto" ] || continue
    case "$proto" in
      vless-reality|hysteria2|anytls|vless-ws)
        proto_name="$(protocol_label "$proto")"
        case "$proto" in
          vless-reality) reality_count=$((reality_count + 1)); proto_count="$reality_count" ;;
          hysteria2) hy2_count=$((hy2_count + 1)); proto_count="$hy2_count" ;;
          anytls) anytls_count=$((anytls_count + 1)); proto_count="$anytls_count" ;;
          vless-ws) ws_count=$((ws_count + 1)); proto_count="$ws_count" ;;
        esac
        new_name="${country_emoji}${country_name}-${provider}-${proto_name}"
        if [ "$proto_count" -gt 1 ]; then
          new_name="${new_name}-${proto_count}"
        fi
        new_name="$(sanitize_db_field "$new_name")"
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
          "$proto" "$new_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6" >> "$tmp_file"
        printf '%s|%s|%s\n' "$proto" "$node_name" "$new_name" >> "$rename_map_file"
        ;;
      *)
        printf '%s\n' "$db_line" >> "$tmp_file"
        ;;
    esac
  done < "$NODES_DB"

  state_transaction_begin || { rm -f "$tmp_file" "$rename_map_file"; return 1; }
  mv "$tmp_file" "$NODES_DB"
  chmod 600 "$NODES_DB"
  if [ -s "$USERS_DB" ]; then
    users_tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
    awk -F'|' '
      BEGIN { OFS = FS }
      NR == FNR {
        key = $1 "|" $2
        renamed[key] = $3
        next
      }
      NF >= 9 {
        key = $3 "|" $2
        if (key in renamed) $2 = renamed[key]
      }
      { print }
    ' "$rename_map_file" "$USERS_DB" > "$users_tmp_file"
    mv "$users_tmp_file" "$USERS_DB"
    chmod 600 "$USERS_DB"
  fi
  rm -f "$rename_map_file"
  state_transaction_apply || return 1
  ui_success "所有节点已按 ${country_emoji}${country_name}-${provider}-协议 格式重命名。"
}

add_node() {
  need_root
  ensure_installed

  clear 2>/dev/null || true
  cat <<EOF
${C_CYAN}====================================================${C_RESET}
 [*] ${C_BOLD}创建代理节点${C_RESET}
${C_CYAN}====================================================${C_RESET}
 ${C_YELLOW}[+] 请选择协议类型${C_RESET}
   ${C_GREEN}1.${C_RESET} VLESS + Reality
   ${C_GREEN}2.${C_RESET} Hysteria2
   ${C_GREEN}3.${C_RESET} AnyTLS
   ${C_GREEN}4.${C_RESET} VLESS + WebSocket
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}0.${C_RESET} => 返回主菜单
${C_CYAN}====================================================${C_RESET}
EOF
  ui_prompt "请输入数字选择 (0-4)："
  read -r protocol_choice || true

  case "$protocol_choice" in
    1) add_vless_reality_node ;;
    2) add_hysteria2_node ;;
    3) add_anytls_node ;;
    4) add_vless_ws_node ;;
    0) return 0 ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac
}

show_all_nodes() {
  if [ ! -s "$NODES_DB" ]; then
    clear 2>/dev/null || true
    ui_title "查看所有节点"
    ui_warn "当前没有节点。"
    return 1
  fi

  screen_title "查看所有节点"
  ui_section "节点列表"
  i=1
  SHARE_SERVER_IP="$(public_ip)"
  export SHARE_SERVER_IP
  sub_file="$(make_temp /tmp/mihomo-sub.XXXXXX)"
  : > "$sub_file"
  while IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6; do
    [ -n "$proto" ] || continue
    case "$proto" in
      vless-reality|hysteria2|anytls|vless-ws)
        node_link="$(node_share_link "$proto" "$node_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6")"
        printf ' %s%s.%s %s%s%s  protocol=%s  port=%s\n' "$C_GREEN" "$i" "$C_RESET" "$C_BOLD" "$node_name" "$C_RESET" "$proto" "$node_port"
        printf '   %s\n\n' "$node_link"
        printf '%s\n' "$node_link" >> "$sub_file"
        i=$((i + 1))
        ;;
    esac
  done < "$NODES_DB"

  if [ -s "$sub_file" ]; then
    sub_base64="$(base64_one_line < "$sub_file")"
    cat <<EOF

${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[+] 聚合订阅 Base64${C_RESET}
$sub_base64
${C_CYAN}----------------------------------------------------${C_RESET}
EOF
  fi
  rm -f "$sub_file"
}

list_nodes() {
  if [ ! -s "$NODES_DB" ]; then
    ui_warn "当前没有节点。"
    return 1
  fi

  ui_section "可删除节点"
  i=1
  while IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6; do
    [ -n "$proto" ] || continue
    case "$proto" in
      vless-reality|hysteria2|anytls|vless-ws)
        printf ' %s%s.%s %s%s%s  protocol=%s  port=%s\n' "$C_GREEN" "$i" "$C_RESET" "$C_BOLD" "$node_name" "$C_RESET" "$proto" "$node_port"
        i=$((i + 1))
        ;;
    esac
  done < "$NODES_DB"
}

select_node() {
  list_nodes || return 1
  ui_prompt "请输入节点编号（0 返回）："
  read -r selected_node_choice || true
  case "$selected_node_choice" in
    0) return 1 ;;
    ''|*[!0-9]*) ui_error "请输入有效数字。"; return 1 ;;
  esac
  SELECTED_NODE_RECORD="$(node_record_by_index "$selected_node_choice")"
  [ -n "$SELECTED_NODE_RECORD" ] || { ui_error "未找到编号 $selected_node_choice。"; return 1; }
  SELECTED_NODE_INDEX="$selected_node_choice"
}

replace_selected_node_record() {
  replacement_record="$1"
  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/nodes.XXXXXX")"
  awk -F'|' -v n="$SELECTED_NODE_INDEX" -v replacement="$replacement_record" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      i++
      if (i == n) { print replacement; next }
    }
    { print }
  ' "$NODES_DB" > "$tmp_file"
  mv "$tmp_file" "$NODES_DB"
  chmod 600 "$NODES_DB"
  if [ -n "${EDIT_OLD_NODE_NAME:-}" ] && [ -n "${EDIT_NEW_NODE_NAME:-}" ] && [ "$EDIT_OLD_NODE_NAME" != "$EDIT_NEW_NODE_NAME" ] && [ -s "$USERS_DB" ]; then
    tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
    awk -F'|' -v old="$EDIT_OLD_NODE_NAME" -v new="$EDIT_NEW_NODE_NAME" '
      BEGIN { OFS = FS }
      $2 == old { $2 = new }
      { print }
    ' "$USERS_DB" > "$tmp_file"
    mv "$tmp_file" "$USERS_DB"
    chmod 600 "$USERS_DB"
  fi
  state_transaction_apply
}

edit_node() {
  need_root
  ensure_installed
  screen_title "编辑节点"
  select_node || return 0
  IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6 <<EOF
$SELECTED_NODE_RECORD
EOF
  EDIT_OLD_NODE_NAME="$node_name"
  ui_section "$node_name ($proto)"
  printf ' %s1.%s 修改名称\n' "$C_GREEN" "$C_RESET"
  printf ' %s2.%s 修改本地监听端口\n' "$C_GREEN" "$C_RESET"
  printf ' %s3.%s 重新生成凭据（UUID/密码）\n' "$C_GREEN" "$C_RESET"
  [ "$proto" = "vless-ws" ] && printf ' %s4.%s 修改 WebSocket 模式、Host、Path 和入口\n' "$C_GREEN" "$C_RESET"
  printf ' %s0.%s 返回\n' "$C_GREEN" "$C_RESET"
  ui_prompt "请选择编辑项目："
  read -r edit_choice || true

  case "$edit_choice" in
    1)
      ui_prompt "请输入新名称："
      read -r new_name || true
      new_name="$(printf '%s' "$new_name" | tr -cd 'A-Za-z0-9_.-')"
      [ -n "$new_name" ] || { ui_error "名称无效。"; return 1; }
      if [ "$new_name" != "$node_name" ] && node_name_exists "$new_name"; then
        ui_error "节点 $new_name 已存在。"
        return 1
      fi
      node_name="$new_name"
      ;;
    2)
      prompt_port || return 1
      node_port="$SELECTED_NODE_PORT"
      ;;
    3)
      case "$proto" in
        vless-reality|vless-ws) value1="$(new_uuid)" ;;
        hysteria2|anytls) value1="$(rand_alnum 32)" ;;
      esac
      ;;
    4)
      [ "$proto" = "vless-ws" ] || { ui_error "此节点不是 VLESS-WS。"; return 1; }
      cat <<EOF
 1. IP 直连 WS
 2. Cloudflare CDN WS-TLS
 3. Cloudflare Tunnel / Argo WS-TLS
EOF
      ui_prompt "请选择 WS 模式："
      read -r ws_edit_mode || true
      case "$ws_edit_mode" in
        1)
          value3=""; value4="direct"; value5=""
          ui_prompt "请输入公网映射端口（默认 $node_port）："
          read -r value6 || true
          [ -n "$value6" ] || value6="$node_port"
          case "$value6" in ''|*[!0-9]*) ui_error "公网映射端口必须是数字。"; return 1 ;; esac
          if [ "$value6" -lt 1 ] || [ "$value6" -gt 65535 ]; then
            ui_error "公网映射端口范围必须为 1-65535。"
            return 1
          fi
          ;;
        2|3)
          [ "$ws_edit_mode" = "2" ] && value4="cdn" || value4="argo"
          [ "$value4" = "argo" ] && ui_warn "不要预建同名 A/AAAA；由 Tunnel 路由创建 CNAME。"
          ui_prompt "请输入完整 Host/SNI 域名："
          read -r value3 || true
          value3="$(sanitize_sni_field "$value3")"
          is_valid_hostname "$value3" || { ui_error "Host/SNI 域名无效。"; return 1; }
          ui_prompt "请输入客户端入口（默认 $value3，可填 CF 优选 IP/域名）："
          read -r value5 || true
          [ -n "$value5" ] || value5="$value3"
          value5="$(sanitize_db_field "$value5" | tr -d '[:space:]')"
          is_valid_endpoint "$value5" || { ui_error "客户端入口无效。"; return 1; }
          value6="443"
          ;;
        *) ui_error "无效选择。"; return 1 ;;
      esac
      ui_prompt "请输入 WebSocket Path（默认 $value2）："
      read -r new_path || true
      [ -n "$new_path" ] && value2="$(sanitize_db_field "$new_path")"
      [ -n "$value2" ] || value2="/$(rand_alnum 10)"
      case "$value2" in /*) ;; *) value2="/$value2" ;; esac
      ;;
    0) return 0 ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac

  EDIT_NEW_NODE_NAME="$node_name"
  replace_selected_node_record "$proto|$node_name|$node_port|$value1|$value2|$value3|$value4|$value5|$value6" || return 1
  EDIT_OLD_NODE_NAME=""
  EDIT_NEW_NODE_NAME=""
  ui_success "节点已更新并通过配置检查。"
  print_node_link "$proto" "$node_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6"
}

node_management_menu() {
  screen_title "节点管理"
  printf ' %s1.%s 编辑节点\n' "$C_GREEN" "$C_RESET"
  printf ' %s2.%s 删除节点\n' "$C_GREEN" "$C_RESET"
  printf ' %s0.%s 返回\n' "$C_GREEN" "$C_RESET"
  ui_prompt "请输入数字选择 (0-2)："
  read -r node_manage_choice || true
  case "$node_manage_choice" in
    1) edit_node ;;
    2) delete_node ;;
    0) return 0 ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac
}

delete_node() {
  need_root
  ensure_installed

  screen_title "删除节点"
  list_nodes || return 0
  ui_dash
  printf ' %s0.%s 返回上一级\n' "$C_GREEN" "$C_RESET"
  printf ' %s99.%s 一键删除所有节点\n' "$C_GREEN" "$C_RESET"
  ui_dash
  ui_prompt "请输入要删除的节点编号："
  read -r choice || true

  case "$choice" in
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  if [ "$choice" = "0" ]; then
    ui_warn "已退出删除节点页面。"
    return 0
  fi

  if [ "$choice" = "99" ]; then
    ui_prompt "确认删除所有节点？输入 y 确认："
    read -r confirm_all || true
    case "$confirm_all" in
      y|Y|yes|YES) ;;
      *)
        ui_warn "已取消删除所有节点。"
        return 0
        ;;
    esac
    state_transaction_begin || return 1
    : > "$NODES_DB"
    chmod 600 "$NODES_DB"
    if multi_user_enabled && [ -f "$USERS_DB" ]; then
      : > "$USERS_DB"
      chmod 600 "$USERS_DB"
      reset_user_traffic_snapshot
    fi
    state_transaction_apply || return 1
    refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
    ui_success "所有节点已删除，服务已重启。"
    return 0
  fi

  deleted="$(awk -F'|' -v n="$choice" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      i++
      if (i == n) { print $2; exit }
    }
  ' "$NODES_DB")"
  if [ -z "$deleted" ]; then
    ui_error "未找到编号 $choice。"
    return 1
  fi

  ui_prompt "确认删除节点 $deleted？输入 y 确认："
  read -r confirm || true
  case "$confirm" in
    y|Y|yes|YES) ;;
    *)
      ui_warn "已取消删除。"
      return 0
      ;;
  esac

  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/nodes.XXXXXX")"
  awk -F'|' -v n="$choice" '
    $1 == "vless-reality" || $1 == "hysteria2" || $1 == "anytls" || $1 == "vless-ws" {
      i++
      if (i == n) next
    }
    { print }
  ' "$NODES_DB" > "$tmp_file"
  mv "$tmp_file" "$NODES_DB"
  chmod 600 "$NODES_DB"
  if multi_user_enabled; then
    remove_users_for_node "$deleted"
  fi
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "节点 $deleted 已删除，服务已重启。"
}

list_multi_users() {
  if [ ! -s "$USERS_DB" ]; then
    ui_warn "当前没有多用户记录。"
    return 1
  fi

  ensure_user_ports
  ui_section "多用户列表"
  i=1
  while IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra; do
    [ -n "$user_name" ] || continue
    if is_user_active "$user_enabled" "$user_expire" "$user_quota" "$user_used"; then
      status="启用"
    elif [ "$user_enabled" = "1" ]; then
      status="已过期"
    else
      status="禁用"
    fi
    quota_text="不限"
    [ "${user_quota:-0}" != "0" ] && quota_text="$(format_bytes "$user_quota")"
    used_text="$(format_bytes "${user_used:-0}")"
    printf ' %s%s.%s %s%s%s  node=%s  proto=%s  port=%s  expire=%s  quota=%s  used=%s  status=%s\n' \
      "$C_GREEN" "$i" "$C_RESET" "$C_BOLD" "$user_name" "$C_RESET" "$user_node" "$user_proto" "${user_port:-unknown}" "${user_expire:-never}" "$quota_text" "$used_text" "$status"
    i=$((i + 1))
  done < "$USERS_DB"
}

add_multi_user() {
  ensure_multi_user_enabled
  if [ ! -s "$NODES_DB" ]; then
    ui_warn "当前没有节点，请先创建节点。"
    return 1
  fi

  screen_title "添加多用户"
  list_nodes || return 1
  ui_prompt "请选择要绑定的节点编号："
  read -r node_choice || true
  case "$node_choice" in
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  node_record="$(node_record_by_index "$node_choice")"
  if [ -z "$node_record" ]; then
    ui_error "未找到节点编号 $node_choice。"
    return 1
  fi

  IFS='|' read -r user_proto user_node_name user_node_port user_value1 user_value2 user_value3 user_value4 user_value5 user_value6 <<EOF
$node_record
EOF
  user_node_name="$(sanitize_db_field "$user_node_name")"

  ui_prompt "请输入用户名（英文/数字/下划线，不能重复）："
  read -r user_name || true
  user_name="$(printf '%s' "$user_name" | tr -cd 'A-Za-z0-9._-')"
  if [ -z "$user_name" ]; then
    ui_error "用户名不能为空。"
    return 1
  fi
  if user_name_exists "$user_name"; then
    ui_error "用户名 $user_name 已存在。"
    return 1
  fi

  ui_prompt "请输入到期日期 YYYY-MM-DD（留空为永不过期）："
  read -r user_expire || true
  user_expire="$(sanitize_user_field "$user_expire")"
  if [ -n "$user_expire" ] && ! is_valid_date "$user_expire"; then
    ui_error "日期格式无效。"
    return 1
  fi

  ui_prompt "请输入流量配额（如 100G / 500M，留空或 0 为不限）："
  read -r quota_input || true
  quota_input="$(sanitize_user_field "$quota_input")"
  if [ -z "$quota_input" ]; then
    user_quota=0
  else
    user_quota="$(quota_to_bytes "$quota_input")" || {
      ui_error "流量配额格式无效。"
      return 1
    }
  fi

  case "$user_proto" in
    vless-reality|vless-ws)
      user_credential="$(new_uuid)"
      ;;
    hysteria2|anytls)
      user_credential="$(rand_alnum 32)"
      ;;
    *)
      ui_error "该节点协议暂不支持多用户。"
      return 1
      ;;
  esac

  default_user_port="$(unique_port)"
  ui_prompt "请输入用户监听端口（默认 $default_user_port，回车自动分配）："
  read -r user_port_input || true
  if [ -z "$user_port_input" ]; then
    user_port="$default_user_port"
  else
    case "$user_port_input" in
      ''|*[!0-9]*)
        ui_error "端口必须是数字。"
        return 1
        ;;
    esac
    if [ "$user_port_input" -lt 1 ] || [ "$user_port_input" -gt 65535 ]; then
      ui_error "端口范围必须为 1-65535。"
      return 1
    fi
    if port_in_use "$user_port_input"; then
      ui_error "端口 $user_port_input 已被其他节点或用户占用。"
      return 1
    fi
    user_port="$user_port_input"
  fi

  user_created="$(today_ymd)"
  state_transaction_begin || return 1
  printf '%s|%s|%s|%s|%s|%s|0|1|%s||%s\n' \
    "$user_name" "$user_node_name" "$user_proto" "$user_credential" "$user_expire" "$user_quota" "$user_created" "$user_port" >> "$USERS_DB"
  chmod 600 "$USERS_DB"
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 已添加并重载服务。"
  SHARE_SERVER_IP="$(public_ip)"
  export SHARE_SERVER_IP
  print_node_link "$user_proto" "$user_name" "$user_port" "$user_credential" "$user_value2" "$user_value3" "$user_value4" "$user_value5" "$user_value6"
}

delete_multi_user() {
  ensure_multi_user_enabled
  screen_title "删除多用户"
  list_multi_users || return 0
  ui_prompt "请输入要删除的用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi
  user_name="${user_record%%|*}"
  ui_prompt "确认删除用户 $user_name？输入 y 确认："
  read -r confirm || true
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) ui_warn "已取消删除。"; return 0 ;;
  esac

  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v n="$user_choice" 'NF >= 9 { i++; if (i == n) next } { print }' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 已删除并重载服务。"
}

set_multi_user_enabled_state() {
  target_enabled="$1"
  action_text="$2"
  ensure_multi_user_enabled
  screen_title "$action_text"
  list_multi_users || return 0
  ui_prompt "请输入用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi
  user_name="${user_record%%|*}"
  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v n="$user_choice" -v enabled="$target_enabled" '
    BEGIN { OFS = FS }
    NF >= 9 {
      i++
      if (i == n) { $8 = enabled }
    }
    { print }
  ' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 已更新为 $action_text。"
}

edit_multi_user_limits() {
  ensure_multi_user_enabled
  screen_title "修改用户到期/配额"
  list_multi_users || return 0
  ui_prompt "请输入用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi
  IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra <<EOF
$user_record
EOF

  ui_prompt "请输入新的到期日期 YYYY-MM-DD（当前 ${user_expire:-永不过期}，留空不变，输入 never 清空）："
  read -r new_expire || true
  new_expire="$(sanitize_user_field "$new_expire")"
  case "$new_expire" in
    '') new_expire="$user_expire" ;;
    never|NEVER|none|NONE) new_expire="" ;;
    *)
      if ! is_valid_date "$new_expire"; then
        ui_error "日期格式无效。"
        return 1
      fi
      ;;
  esac

  ui_prompt "请输入新的流量配额（当前 $(format_bytes "${user_quota:-0}")，留空不变，0 为不限）："
  read -r new_quota_input || true
  new_quota_input="$(sanitize_user_field "$new_quota_input")"
  if [ -z "$new_quota_input" ]; then
    new_quota="$user_quota"
  else
    new_quota="$(quota_to_bytes "$new_quota_input")" || {
      ui_error "流量配额格式无效。"
      return 1
    }
  fi

  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v n="$user_choice" -v expire="$new_expire" -v quota="$new_quota" '
    BEGIN { OFS = FS }
    NF >= 9 {
      i++
      if (i == n) {
        $5 = expire
        $6 = quota
      }
    }
    { print }
  ' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 的到期/配额已更新。"
}

refresh_multi_user_status() {
  ensure_multi_user_enabled
  screen_title "刷新用户状态"
  render_config || return 1
  restart_service || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "已重新渲染配置。过期、禁用或超额用户不会写入独立 listener。"
}

acquire_traffic_lock() {
  mkdir -p "$CONFIG_DIR" 2>/dev/null || return 1
  if mkdir "$TRAFFIC_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$TRAFFIC_LOCK_DIR/pid"
    return 0
  fi

  if [ -f "$TRAFFIC_LOCK_DIR/pid" ]; then
    lock_pid="$(cat "$TRAFFIC_LOCK_DIR/pid" 2>/dev/null || printf '')"
    case "$lock_pid" in
      ''|*[!0-9]*) ;;
      *) kill -0 "$lock_pid" 2>/dev/null && return 1 ;;
    esac
  fi
  rm -f "$TRAFFIC_LOCK_DIR/pid"
  rmdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || return 1
  mkdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || return 1
  printf '%s\n' "$$" > "$TRAFFIC_LOCK_DIR/pid"
}

release_traffic_lock() {
  rm -f "$TRAFFIC_LOCK_DIR/pid"
  rmdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || true
}

_update_user_traffic_from_iptables() {
  traffic_quiet="${1:-0}"
  traffic_enforce="${2:-1}"
  ensure_multi_user_enabled
  [ "$traffic_quiet" = "1" ] || screen_title "刷新流量统计"
  if [ ! -s "$USERS_DB" ]; then
    [ "$traffic_quiet" = "1" ] || ui_warn "当前没有多用户记录。"
    return 0
  fi

  ensure_user_ports
  ensure_user_traffic_rules_ready || {
    [ "$traffic_quiet" = "1" ] || ui_error "无法准备 iptables 统计规则。请检查容器 NET_ADMIN 权限。"
    return 1
  }
  had_traffic_snapshot=1
  [ -f "$TRAFFIC_DB" ] || had_traffic_snapshot=0
  [ -f "$TRAFFIC_DB" ] || reset_user_traffic_snapshot
  chmod 600 "$TRAFFIC_DB"
  tmp_current="$(make_temp "$CONFIG_DIR/traffic-current.XXXXXX")"
  tmp_deltas="$(make_temp "$CONFIG_DIR/traffic-delta.XXXXXX")"
  tmp_users="$(make_temp "$CONFIG_DIR/users.XXXXXX")"

  ipt="$(iptables_cmd)" || {
    rm -f "$tmp_current" "$tmp_deltas" "$tmp_users"
    [ "$traffic_quiet" = "1" ] || ui_error "未找到 iptables，无法读取 IPv4 流量统计。"
    return 1
  }
  ip6t=""
  if traffic_ipv6_enabled; then
    ip6t="$(ip6tables_cmd)" || {
      rm -f "$tmp_current" "$tmp_deltas" "$tmp_users"
      [ "$traffic_quiet" = "1" ] || ui_error "IPv6 已开启，但未找到 ip6tables，无法读取 IPv6 流量统计。"
      return 1
    }
  fi
  {
    traffic_counter_lines_for_cmd "$ipt"
    if [ -n "$ip6t" ]; then
      traffic_counter_lines_for_cmd "$ip6t"
    fi
  } | awk -F'|' '
    {
      total[$1] += $2
    }
    END {
      for (port in total) print port "|" int(total[port])
    }
  ' > "$tmp_current"

  if [ ! -s "$tmp_current" ]; then
    rm -f "$tmp_current" "$tmp_deltas" "$tmp_users"
    [ "$traffic_quiet" = "1" ] || ui_warn "当前没有可读取的用户端口计数。请确认用户端口已有连接，并检查 iptables 权限。"
    return 1
  fi

  if [ "$had_traffic_snapshot" = "0" ]; then
    mv "$tmp_current" "$TRAFFIC_DB"
    chmod 600 "$TRAFFIC_DB"
    rm -f "$tmp_deltas" "$tmp_users"
    [ "$traffic_quiet" = "1" ] || ui_warn "已建立端口流量快照。请在用户产生流量后再次刷新，才会累计增量。"
    return 0
  fi

  awk -F'|' '
    BEGIN { OFS = FS }
    NR == FNR {
      previous[$1] = $2
      next
    }
    {
      current = $2 + 0
      old = (($1 in previous) ? previous[$1] : 0) + 0
      delta = current - old
      if (delta > 0) add[$1] += delta
    }
    END {
      for (user in add) print user, int(add[user])
    }
  ' "$TRAFFIC_DB" "$tmp_current" > "$tmp_deltas" 2>/dev/null

  if [ ! -s "$tmp_deltas" ]; then
    mv "$tmp_current" "$TRAFFIC_DB"
    chmod 600 "$TRAFFIC_DB"
    rm -f "$tmp_deltas" "$tmp_users"
    [ "$traffic_quiet" = "1" ] || ui_warn "已保存当前连接快照。本次没有新的可累计流量，请稍后再次刷新。"
    return 0
  fi

  changed_count="$(awk -F'|' '
    NR == FNR {
      delta[$1] = $2 + 0
      next
    }
    BEGIN { OFS = FS }
    NF >= 9 {
      user_delta = 0
      if (NF >= 11 && $11 in delta) user_delta += delta[$11]
      if (user_delta > 0) {
        old = $7 + 0
        quota = $6 + 0
        enabled = $8
        new_used = int(old + user_delta)
        if (enabled == "1" && quota > 0 && new_used >= quota) crossed++
        $7 = new_used
        changed++
  }
}

    { print }
    END {
      printf "%d|%d", changed, crossed > "/dev/stderr"
    }
  ' "$tmp_deltas" "$USERS_DB" > "$tmp_users" 2>"$tmp_users.count")"
  count_text="$(cat "$tmp_users.count" 2>/dev/null || printf '0|0')"
  rm -f "$tmp_users.count"
  IFS='|' read -r changed_count quota_crossed_count <<EOF
$count_text
EOF
  changed_count="${changed_count:-0}"
  quota_crossed_count="${quota_crossed_count:-0}"

  if [ "${changed_count:-0}" = "0" ]; then
    mv "$tmp_current" "$TRAFFIC_DB"
    chmod 600 "$TRAFFIC_DB"
    rm -f "$tmp_deltas" "$tmp_users"
    [ "$traffic_quiet" = "1" ] || ui_warn "iptables 返回了端口流量，但未匹配到 users.db 中的用户端口。请确认连接走的是用户独立端口。"
    return 1
  fi

  mv "$tmp_users" "$USERS_DB"
  chmod 600 "$USERS_DB"
  mv "$tmp_current" "$TRAFFIC_DB"
  chmod 600 "$TRAFFIC_DB"
  rm -f "$tmp_deltas"

  [ "$traffic_quiet" = "1" ] || ui_success "已更新 $changed_count 个用户的流量用量。"
  [ "$traffic_quiet" = "1" ] || list_multi_users
  if [ "$quota_crossed_count" != "0" ]; then
    if [ "$traffic_enforce" != "1" ]; then
      [ "$traffic_quiet" = "1" ] || ui_warn "检测到 $quota_crossed_count 个用户达到流量配额，本次只记录用量，不重启 Mihomo。"
      return 0
    fi
    render_config || return 1
    restart_service || return 1
    refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
    [ "$traffic_quiet" = "1" ] || ui_success "检测到 $quota_crossed_count 个用户达到流量配额，已重载服务并移除对应 listener。"
  else
    [ "$traffic_quiet" = "1" ] || ui_success "未触发新的配额限制，本次未重启 Mihomo。"
  fi
}

update_user_traffic_from_iptables() {
  acquire_traffic_lock || {
    [ "${1:-0}" = "1" ] || ui_warn "已有流量统计任务正在运行，本次刷新已跳过。"
    return 0
  }
  _update_user_traffic_from_iptables "$@"
  traffic_result=$?
  release_traffic_lock
  return "$traffic_result"
}

update_user_traffic_from_connections() {
  update_user_traffic_from_iptables "${1:-0}" "${2:-1}"
}

traffic_auto_cron_line() {
  printf '*/10 * * * * %s traffic-auto >/dev/null 2>&1 # %s\n' "$CLI_PATH" "$TRAFFIC_CRON_MARK"
}

traffic_auto_enabled() {
  command -v crontab >/dev/null 2>&1 || return 1
  crontab -l 2>/dev/null | grep -q "$TRAFFIC_CRON_MARK"
}

run_traffic_auto_refresh() {
  need_root
  ensure_installed
  ensure_multi_user_enabled
  update_user_traffic_from_connections 1 1
}

enable_traffic_auto_refresh() {
  ensure_multi_user_enabled
  ensure_cron_service || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/cron.XXXXXX")"
  crontab -l 2>/dev/null | grep -v "$TRAFFIC_CRON_MARK" > "$tmp_file" || true
  traffic_auto_cron_line >> "$tmp_file"
  crontab "$tmp_file" || {
    rm -f "$tmp_file"
    ui_error "写入 crontab 失败。"
    return 1
  }
  rm -f "$tmp_file"
  ui_success "已启用每 10 分钟自动刷新流量统计。"
}

disable_traffic_auto_refresh() {
  if ! command -v crontab >/dev/null 2>&1; then
    ui_success "未检测到 crontab，无需关闭自动刷新。"
    return 0
  fi
  tmp_file="$(make_temp "$CONFIG_DIR/cron.XXXXXX")"
  crontab -l 2>/dev/null | grep -v "$TRAFFIC_CRON_MARK" > "$tmp_file" || true
  crontab "$tmp_file" || {
    rm -f "$tmp_file"
    ui_error "更新 crontab 失败。"
    return 1
  }
  rm -f "$tmp_file"
  ui_success "已关闭自动刷新流量统计。"
}

cleanup_traffic_auto_refresh() {
  command -v crontab >/dev/null 2>&1 || return 0
  tmp_file="$(make_temp /tmp/mh-cron.XXXXXX)"
  crontab -l 2>/dev/null | grep -v "$TRAFFIC_CRON_MARK" > "$tmp_file" || true
  crontab "$tmp_file" >/dev/null 2>&1 || true
  rm -f "$tmp_file"
  rm -f "$TRAFFIC_LOCK_DIR/pid"
  rmdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || true
}

traffic_auto_refresh_menu() {
  ensure_multi_user_enabled
  screen_title "自动刷新流量统计"
  if command -v crontab >/dev/null 2>&1 && traffic_auto_enabled; then
    auto_status="已启用"
  else
    auto_status="未启用"
  fi
  cat <<EOF
 当前状态：$auto_status

 ${C_GREEN}1.${C_RESET} 启用每 10 分钟自动刷新
 ${C_GREEN}2.${C_RESET} 关闭自动刷新
 ${C_GREEN}0.${C_RESET} => 返回上一级
${C_CYAN}====================================================${C_RESET}
EOF
  ui_prompt "请输入数字选择 (0-2)："
  read -r auto_choice || true
  case "$auto_choice" in
    1) enable_traffic_auto_refresh ;;
    2) disable_traffic_auto_refresh ;;
    0) return 0 ;;
    *) ui_error "无效选择。" ;;
  esac
}

reset_multi_user_traffic() {
  ensure_multi_user_enabled
  screen_title "重置用户流量"
  list_multi_users || return 0
  ui_prompt "请输入要重置流量的用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi
  IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra <<EOF
$user_record
EOF
  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  tmp_traffic="$(make_temp "$CONFIG_DIR/traffic.XXXXXX")"
  awk -F'|' -v n="$user_choice" '
    BEGIN { OFS = FS }
    NF >= 9 {
      i++
      if (i == n) { $7 = 0 }
    }
    { print }
  ' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  if [ -s "$TRAFFIC_DB" ]; then
    awk -F'|' -v p="$user_port" '
      BEGIN { seen = 0 }
      $1 == p { print p "|0"; seen = 1; next }
      { print }
      END { if (p != "" && seen == 0) print p "|0" }
    ' "$TRAFFIC_DB" > "$tmp_traffic"
    mv "$tmp_traffic" "$TRAFFIC_DB"
  else
    rm -f "$tmp_traffic"
    reset_user_traffic_snapshot
  fi
  chmod 600 "$TRAFFIC_DB"
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 的已用流量已重置。"
}

edit_multi_user_port() {
  ensure_multi_user_enabled
  screen_title "修改用户端口"
  list_multi_users || return 0
  ui_prompt "请输入要修改端口的用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi
  IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra <<EOF
$user_record
EOF

  ui_prompt "请输入新的用户监听端口（当前 ${user_port:-未分配}，留空自动生成）："
  read -r new_port || true
  if [ -z "$new_port" ]; then
    new_port="$(unique_port)"
  else
    case "$new_port" in
      ''|*[!0-9]*)
        ui_error "端口必须是数字。"
        return 1
        ;;
    esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      ui_error "端口范围必须为 1-65535。"
      return 1
    fi
    if [ "$new_port" != "${user_port:-}" ] && port_in_use "$new_port"; then
      ui_error "端口 $new_port 已被其他节点或用户占用。"
      return 1
    fi
  fi

  state_transaction_begin || return 1
  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v n="$user_choice" -v port="$new_port" '
    BEGIN { OFS = FS }
    NF >= 9 {
      i++
      if (i == n) {
        while (NF < 11) { $(NF + 1) = "" }
        $11 = port
      }
    }
    { print }
  ' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  reset_user_traffic_snapshot
  state_transaction_apply || return 1
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 的端口已更新为 $new_port，流量快照已重置。"
}

show_user_subscription() {
  ensure_multi_user_enabled
  screen_title "分发用户订阅"
  list_multi_users || return 0
  ui_prompt "请输入要分发订阅的用户编号（0 返回）："
  read -r user_choice || true
  case "$user_choice" in
    0) return 0 ;;
    ''|*[!0-9]*)
      ui_error "请输入有效数字。"
      return 1
      ;;
  esac

  user_record="$(user_record_by_index "$user_choice")"
  if [ -z "$user_record" ]; then
    ui_error "未找到用户编号 $user_choice。"
    return 1
  fi

  IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra <<EOF
$user_record
EOF

  if ! is_user_active "$user_enabled" "$user_expire" "$user_quota" "$user_used"; then
    ui_warn "用户 $user_name 当前未启用、已过期或已超出流量配额，订阅链接可能无法连接。"
  fi

  node_record="$(node_record_by_name_proto "$user_node" "$user_proto")"
  if [ -z "$node_record" ]; then
    ui_error "找不到用户绑定的原始节点：$user_node / $user_proto"
    return 1
  fi

  IFS='|' read -r node_proto node_name node_port value1 value2 value3 value4 value5 value6 <<EOF
$node_record
EOF

  SHARE_SERVER_IP="$(public_ip)"
  export SHARE_SERVER_IP
  case "${user_port:-}" in
    ''|*[!0-9]*)
      render_config || return 1
      user_record="$(user_record_by_index "$user_choice")"
      IFS='|' read -r user_name user_node user_proto user_credential user_expire user_quota user_used user_enabled user_created user_note user_port user_extra <<EOF
$user_record
EOF
      ;;
  esac

  user_link="$(node_share_link "$user_proto" "$user_name" "$user_port" "$user_credential" "$value2" "$value3" "$value4" "$value5" "$value6")"
  sub_base64="$(printf '%s\n' "$user_link" | base64_one_line)"

  cat <<EOF

${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[+] 用户信息${C_RESET}
 用户：$user_name
 节点：$user_node
 协议：$user_proto
 用户端口：$user_port
 绑定节点端口：$node_port

 ${C_GREEN}[+] 用户节点链接${C_RESET}
$user_link

 ${C_GREEN}[+] 用户订阅 Base64${C_RESET}
$sub_base64
${C_CYAN}----------------------------------------------------${C_RESET}
EOF
}

multi_user_panel() {
  need_root
  ensure_installed
  ensure_multi_user_enabled
  while true; do
    screen_title "多用户管理面板"
    cat <<EOF
 ${C_GREEN}1.${C_RESET} 添加用户
 ${C_GREEN}2.${C_RESET} 查看用户
 ${C_GREEN}3.${C_RESET} 删除用户
 ${C_GREEN}4.${C_RESET} 禁用用户
 ${C_GREEN}5.${C_RESET} 启用用户
 ${C_GREEN}6.${C_RESET} 修改到期时间/流量配额
 ${C_GREEN}7.${C_RESET} 刷新用户状态
 ${C_GREEN}8.${C_RESET} 刷新流量统计
 ${C_GREEN}9.${C_RESET} 重置用户流量
 ${C_GREEN}10.${C_RESET} 分发用户订阅
 ${C_GREEN}11.${C_RESET} 修改用户端口
 ${C_GREEN}12.${C_RESET} 自动刷新流量统计
 ${C_GREEN}0.${C_RESET} => 返回主菜单
${C_CYAN}====================================================${C_RESET}
EOF
    ui_prompt "请输入数字选择 (0-12)："
    read -r user_panel_choice || true
    case "$user_panel_choice" in
      1) add_multi_user; pause ;;
      2) list_multi_users; pause ;;
      3) delete_multi_user; pause ;;
      4) set_multi_user_enabled_state 0 "禁用用户"; pause ;;
      5) set_multi_user_enabled_state 1 "启用用户"; pause ;;
      6) edit_multi_user_limits; pause ;;
      7) refresh_multi_user_status; pause ;;
      8) update_user_traffic_from_connections; pause ;;
      9) reset_multi_user_traffic; pause ;;
      10) show_user_subscription; pause ;;
      11) edit_multi_user_port; pause ;;
      12) traffic_auto_refresh_menu; pause ;;
      0) return 0 ;;
      *) ui_error "无效选择，请输入 0-12。"; pause ;;
    esac
  done
}

show_config() {
  need_root
  ensure_installed
  screen_title "查看 YAML 配置文件"
  ui_warn "配置文件路径：$CONFIG_FILE"
  ui_dash
  if command -v less >/dev/null 2>&1; then
    less "$CONFIG_FILE"
  else
    cat "$CONFIG_FILE"
  fi
}

show_logs() {
  ensure_installed
  screen_title "查看服务实时日志"
  ui_warn "按 Ctrl+C 可停止查看日志并返回终端。"
  ui_dash
  manager="$(service_manager)"
  case "$manager" in
    systemd) journalctl -u "$SERVICE_NAME" -f --no-pager ;;
    openrc)
      touch "$LOG_DIR/${SERVICE_NAME}.log" "$LOG_DIR/${SERVICE_NAME}.err"
      tail -F "$LOG_DIR/${SERVICE_NAME}.log" "$LOG_DIR/${SERVICE_NAME}.err"
      ;;
    *)
      red "未找到 systemd 或 OpenRC，无法查看服务日志。"
      return 1
      ;;
  esac
}

apply_runtime_service() {
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      write_systemd_service
      ;;
    openrc)
      write_openrc_service
      ;;
    *)
      red "未找到 systemd 或 OpenRC，无法应用性能参数。"
      return 1
      ;;
  esac
}

apply_saved_runtime_service() {
  need_root
  ensure_installed
  detect_os
  load_runtime_tuning
  recommended="$(recommended_runtime)"
  recommended_mem="${recommended%%|*}"
  recommended_rest="${recommended#*|}"
  recommended_gogc="${recommended_rest%%|*}"
  recommended_gomaxprocs="${recommended_rest#*|}"
  [ "$recommended_gomaxprocs" = "$recommended_rest" ] && recommended_gomaxprocs="$(effective_cpu_count)"

  [ -n "$MIHOMO_GOMEMLIMIT" ] || MIHOMO_GOMEMLIMIT="$recommended_mem"
  [ -n "$MIHOMO_GOGC" ] || MIHOMO_GOGC="$recommended_gogc"
  [ -n "$MIHOMO_GOMAXPROCS" ] || MIHOMO_GOMAXPROCS="$recommended_gomaxprocs"
  [ -n "$MIHOMO_GODEBUG" ] || MIHOMO_GODEBUG="$MIHOMO_GODEBUG_DEFAULT"

  validate_runtime_tuning
  write_runtime_tuning
  apply_runtime_service
}

performance_tuning_menu() {
  need_root
  ensure_installed
  detect_os
  load_runtime_tuning
  recommended="$(recommended_runtime)"
  recommended_mem="${recommended%%|*}"
  recommended_rest="${recommended#*|}"
  recommended_gogc="${recommended_rest%%|*}"
  recommended_gomaxprocs="${recommended_rest#*|}"
  [ "$recommended_gomaxprocs" = "$recommended_rest" ] && recommended_gomaxprocs="$(effective_cpu_count)"
  current_mem="${MIHOMO_GOMEMLIMIT:-未设置}"
  current_gogc="${MIHOMO_GOGC:-未设置}"
  current_gomaxprocs="${MIHOMO_GOMAXPROCS:-未设置}"
  current_godebug="${MIHOMO_GODEBUG:-$MIHOMO_GODEBUG_DEFAULT}"
  detected_memory_mib="$(memory_limit_mib)"
  case "$detected_memory_mib" in
    ''|*[!0-9]*) detected_memory_text="未检测到" ;;
    *) detected_memory_text="${detected_memory_mib}MiB" ;;
  esac
  cleanup_stats_mode=0
  cpu_limit_text="未检测到严重限制"
  cpu_milli="$(cpu_quota_milli | sed -n '1p')"
  case "$cpu_milli" in
    ''|*[!0-9]*)
      ;;
    *)
      cpu_core_text="$(awk -v milli="$cpu_milli" 'BEGIN { printf "%.2f", milli / 1000 }')"
      if [ "$cpu_milli" -lt 1000 ]; then
        cpu_limit_text="约 ${cpu_core_text} 核，已按 CPU 受限容器优化"
      else
        cpu_limit_text="约 ${cpu_core_text} 核"
      fi
      ;;
  esac

  resource_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
  throughput_gomaxprocs="$recommended_gomaxprocs"
  case "$detected_memory_mib" in
    ''|*[!0-9]*)
      case "${os_id:-}" in
        alpine)
          resource_mem="192MiB"
          resource_gogc="175"
          throughput_mem="256MiB"
          throughput_gogc="175"
          throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
          ;;
        *)
          resource_mem="384MiB"
          resource_gogc="200"
          throughput_mem="512MiB"
          throughput_gogc="200"
          throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
          ;;
      esac
      ;;
    *)
      resource_mem="$(memlimit_from_percent "$detected_memory_mib" 60 64 64 512)"
      throughput_mem="$(memlimit_from_percent "$detected_memory_mib" 70 128 64 1024)"
      if [ "$detected_memory_mib" -le 256 ]; then
        resource_gogc="175"
        throughput_gogc="150"
        throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
      elif [ "$detected_memory_mib" -le 512 ]; then
        resource_gogc="200"
        throughput_gogc="175"
        throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
      elif [ "$detected_memory_mib" -le 1024 ]; then
        resource_gogc="225"
        throughput_gogc="200"
        throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
      else
        resource_gogc="250"
        throughput_gogc="250"
        throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 4)"
      fi
      ;;
  esac
  if cpu_quota_severely_limited; then
    resource_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
    throughput_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
    [ "$resource_gogc" -lt 200 ] && resource_gogc="200"
    [ "$throughput_gogc" -lt 175 ] && throughput_gogc="175"
  fi
  normalize_runtime_profiles

  screen_title "性能优化菜单"
  cat <<EOF
 当前参数：GOMEMLIMIT=$current_mem  GOGC=$current_gogc  GOMAXPROCS=$current_gomaxprocs
 当前 GODEBUG：$current_godebug
 检测内存：$detected_memory_text
 CPU 配额：$cpu_limit_text
 系统推荐：GOMEMLIMIT=$recommended_mem  GOGC=$recommended_gogc  GOMAXPROCS=$recommended_gomaxprocs
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}1.${C_RESET} 省资源稳连模式      GOMEMLIMIT=$resource_mem  GOGC=$resource_gogc  GOMAXPROCS=$resource_gomaxprocs
 ${C_GREEN}2.${C_RESET} 系统推荐模式        GOMEMLIMIT=$recommended_mem  GOGC=$recommended_gogc  GOMAXPROCS=$recommended_gomaxprocs
 ${C_GREEN}3.${C_RESET} 高吞吐/跑满带宽     GOMEMLIMIT=$throughput_mem  GOGC=$throughput_gogc  GOMAXPROCS=$throughput_gomaxprocs
 ${C_GREEN}4.${C_RESET} 自定义参数
 ${C_GREEN}0.${C_RESET} => 返回主菜单
${C_CYAN}====================================================${C_RESET}
EOF
  case "$detected_memory_mib" in
    ''|*[!0-9]*)
      ui_warn "未检测到可信的 cgroup/容器内存上限；当前使用保守兜底档位，高吞吐模式前请确认实际可用内存。"
      ;;
  esac
  ui_prompt "请输入数字选择 (0-4)："
  read -r perf_choice || true

  case "$perf_choice" in
    1)
      ui_warn "省资源稳连模式会限制 Go 调度线程、提高 GOGC，并关闭自动流量统计以降低 CPU。"
      ui_prompt "确认应用省资源稳连模式？输入 y 确认："
      read -r resource_confirm || true
      case "$resource_confirm" in
        y|Y|yes|YES) ;;
        *)
          ui_warn "已取消省资源稳连模式。"
          return 0
          ;;
      esac
      MIHOMO_GOMEMLIMIT="$resource_mem"
      MIHOMO_GOGC="$resource_gogc"
      MIHOMO_GOMAXPROCS="$resource_gomaxprocs"
      cleanup_stats_mode=1
      ;;
    2)
      MIHOMO_GOMEMLIMIT="$recommended_mem"
      MIHOMO_GOGC="$recommended_gogc"
      MIHOMO_GOMAXPROCS="$recommended_gomaxprocs"
      ;;
    3)
      ui_warn "高吞吐/跑满带宽模式会关闭自动流量统计，并移除 iptables 统计规则以降低包路径开销。"
      ui_warn "流量配额不会实时累计；再次执行 mh traffic 会重建统计规则。"
      case "$detected_memory_mib" in
        ''|*[!0-9]*) ;;
        *)
          if [ "$detected_memory_mib" -le 512 ]; then
            ui_warn "当前总内存仅 ${detected_memory_mib}MiB；高吞吐模式可能挤压 cloudflared 和系统内存，不建议长期使用。"
          fi
          ;;
      esac
      ui_prompt "确认应用高吞吐/跑满带宽模式？输入 y 确认："
      read -r throughput_confirm || true
      case "$throughput_confirm" in
        y|Y|yes|YES) ;;
        *)
          ui_warn "已取消高吞吐/跑满带宽模式。"
          return 0
          ;;
      esac
      MIHOMO_GOMEMLIMIT="$throughput_mem"
      MIHOMO_GOGC="$throughput_gogc"
      MIHOMO_GOMAXPROCS="$throughput_gomaxprocs"
      cleanup_stats_mode=1
      ;;
    4)
      default_mem="${MIHOMO_GOMEMLIMIT:-$recommended_mem}"
      default_gogc="${MIHOMO_GOGC:-$recommended_gogc}"
      default_gomaxprocs="${MIHOMO_GOMAXPROCS:-$recommended_gomaxprocs}"
      ui_prompt "请输入 GOMEMLIMIT（默认 $default_mem）："
      read -r input_mem || true
      MIHOMO_GOMEMLIMIT="${input_mem:-$default_mem}"
      ui_prompt "请输入 GOGC（默认 $default_gogc）："
      read -r input_gogc || true
      MIHOMO_GOGC="${input_gogc:-$default_gogc}"
      ui_prompt "请输入 GOMAXPROCS（默认 $default_gomaxprocs）："
      read -r input_gomaxprocs || true
      MIHOMO_GOMAXPROCS="${input_gomaxprocs:-$default_gomaxprocs}"
      ;;
    0)
      ui_warn "已取消性能参数调整。"
      return 0
      ;;
    *)
      ui_error "无效选择。"
      return 1
      ;;
  esac

  validate_runtime_tuning
  write_runtime_tuning
  apply_runtime_service
  if [ "$cleanup_stats_mode" = "1" ]; then
    disable_traffic_auto_refresh >/dev/null 2>&1 || true
    cleanup_user_traffic_rules >/dev/null 2>&1 || true
    ui_success "已关闭自动流量统计并清理 iptables 统计规则，降低包路径 CPU 开销。"
  fi
  ui_success "性能参数已更新：GOMEMLIMIT=$MIHOMO_GOMEMLIMIT，GOGC=$MIHOMO_GOGC，GOMAXPROCS=$MIHOMO_GOMAXPROCS，GODEBUG=$MIHOMO_GODEBUG。"
}

apply_sysctl_value() {
  sysctl_key="$1"
  sysctl_value="$2"
  sysctl_tmp="$3"
  proc_path="/proc/sys/$(printf '%s' "$sysctl_key" | tr '.' '/')"

  if [ ! -e "$proc_path" ]; then
    ui_warn "$sysctl_key 当前内核不支持，已跳过。"
    return 1
  fi
  if [ ! -w "$proc_path" ]; then
    ui_warn "$sysctl_key 当前无写入权限，可能是 LXC 容器限制，已跳过。"
    return 1
  fi

  mkdir -p "$CONFIG_DIR"
  if ! awk -F'|' -v key="$sysctl_key" '$1 == key { found = 1 } END { exit found ? 0 : 1 }' "$SYSCTL_BACKUP_FILE" 2>/dev/null; then
    old_sysctl_value=""
    if command -v sysctl >/dev/null 2>&1; then
      old_sysctl_value="$(sysctl -n "$sysctl_key" 2>/dev/null || true)"
    fi
    [ -n "$old_sysctl_value" ] || old_sysctl_value="$(cat "$proc_path" 2>/dev/null || true)"
    [ -n "$old_sysctl_value" ] && printf '%s|%s\n' "$sysctl_key" "$old_sysctl_value" >> "$SYSCTL_BACKUP_FILE"
    chmod 600 "$SYSCTL_BACKUP_FILE" 2>/dev/null || true
  fi

  if command -v sysctl >/dev/null 2>&1 && sysctl -w "$sysctl_key=$sysctl_value" >/dev/null 2>&1; then
    printf '%s = %s\n' "$sysctl_key" "$sysctl_value" >> "$sysctl_tmp"
    ui_success "$sysctl_key=$sysctl_value"
    return 0
  fi

  if ( printf '%s\n' "$sysctl_value" > "$proc_path" ) 2>/dev/null; then
    printf '%s = %s\n' "$sysctl_key" "$sysctl_value" >> "$sysctl_tmp"
    ui_success "$sysctl_key=$sysctl_value"
    return 0
  fi

  ui_warn "$sysctl_key 写入失败，已跳过。"
  return 1
}

restore_sysctl_network() {
  restored=0
  failed=0
  if [ -s "$SYSCTL_BACKUP_FILE" ]; then
    while IFS='|' read -r restore_key restore_value; do
      [ -n "$restore_key" ] || continue
      if command -v sysctl >/dev/null 2>&1 && sysctl -w "$restore_key=$restore_value" >/dev/null 2>&1; then
        restored=$((restored + 1))
      else
        restore_path="/proc/sys/$(printf '%s' "$restore_key" | tr '.' '/')"
        if [ -w "$restore_path" ] && ( printf '%s\n' "$restore_value" > "$restore_path" ) 2>/dev/null; then
          restored=$((restored + 1))
        else
          failed=$((failed + 1))
        fi
      fi
    done < "$SYSCTL_BACKUP_FILE"
  fi
  rm -f "$SYSCTL_CONF_FILE" "$SYSCTL_BACKUP_FILE"
  if [ "$failed" -gt 0 ]; then
    ui_warn "已恢复 $restored 项 sysctl，另有 $failed 项受容器权限限制；重启后将不再加载本脚本配置。"
  elif [ "$restored" -gt 0 ]; then
    ui_success "已恢复 $restored 项 sysctl 原值。"
  else
    ui_warn "没有旧 sysctl 快照；已删除脚本配置文件，重启后不再应用。"
  fi
}

migrate_legacy_sysctl_config() {
  [ -r "$SYSCTL_CONF_FILE" ] || return 0
  if ! grep -Eq '67108864|netdev_max_backlog[[:space:]]*=[[:space:]]*250000|somaxconn[[:space:]]*=[[:space:]]*65535' "$SYSCTL_CONF_FILE"; then
    return 0
  fi

  legacy_sysctl_tmp="$(make_temp /tmp/mihomo-sysctl-migrate.XXXXXX)"
  printf '# Generated by Mihomo Lite - conservative verified settings\n' > "$legacy_sysctl_tmp"
  if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" = "bbr" ]; then
    printf 'net.ipv4.tcp_congestion_control = bbr\n' >> "$legacy_sysctl_tmp"
  fi
  mv "$legacy_sysctl_tmp" "$SYSCTL_CONF_FILE"
  chmod 644 "$SYSCTL_CONF_FILE"
  ui_success "已清理旧版激进 sysctl 持久化配置；当前运行参数未被更改。"
}

optimize_sysctl_network() {
  need_root
  screen_title "sysctl 网络优化"
  network_memory_mib="$(memory_limit_mib)"
  network_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
  network_available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf '未知')"
  network_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '由宿主机管理')"
  network_retrans="$(nstat -az 2>/dev/null | awk '$1 == "TcpRetransSegs" { print $2; exit }')"
  network_udp_errors="$(nstat -az 2>/dev/null | awk '$1 == "UdpRcvbufErrors" { print $2; exit }')"
  network_listen_drops="$(nstat -az 2>/dev/null | awk '$1 == "TcpExtListenDrops" { print $2; exit }')"
  [ -n "$network_retrans" ] || network_retrans="未知"
  [ -n "$network_udp_errors" ] || network_udp_errors="未知"
  [ -n "$network_listen_drops" ] || network_listen_drops="未知"

  printf ' 内存限制：%s MiB\n' "${network_memory_mib:-未知}"
  printf ' 拥塞控制：%s（可用：%s）\n' "$network_congestion" "$network_available"
  printf ' 队列算法：%s\n' "$network_qdisc"
  printf ' 累计指标：TCP 重传 %s，UDP 缓冲错误 %s，监听丢弃 %s\n' "$network_retrans" "$network_udp_errors" "$network_listen_drops"
  ui_warn "无损模式不会修改 TCP/UDP 缓冲、TIME_WAIT、Keepalive、端口范围或超大连接队列。"
  ui_warn "容器不可见的 net.core 参数由宿主机管理，脚本不会伪报优化成功。"
  ui_prompt "确认应用无损网络优化并清理旧版激进配置？输入 y 确认："
  read -r confirm || true
  case "$confirm" in
    y|Y|yes|YES) ;;
    *)
      ui_warn "已取消 sysctl 网络优化。"
      return 0
      ;;
  esac

  command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null || true

  tmp_file="$(make_temp /tmp/mihomo-sysctl.XXXXXX)"
  printf '# Generated by Mihomo Lite - conservative verified settings\n' > "$tmp_file"
  applied=0

  case " $network_available " in
    *' bbr '*)
      if [ "$network_congestion" = "bbr" ]; then
        printf 'net.ipv4.tcp_congestion_control = bbr\n' >> "$tmp_file"
        applied=$((applied + 1))
        ui_success "BBR 已经生效，仅保留安全持久化配置。"
      elif apply_sysctl_value "net.ipv4.tcp_congestion_control" "bbr" "$tmp_file"; then
        applied=$((applied + 1))
      fi
      ;;
    *) ui_warn "当前内核未提供 BBR，保持现有拥塞控制：$network_congestion。" ;;
  esac

  network_window_scaling="$(sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || printf '未知')"
  if [ "$network_window_scaling" = "0" ]; then
    if apply_sysctl_value "net.ipv4.tcp_window_scaling" "1" "$tmp_file"; then applied=$((applied + 1)); fi
  elif [ "$network_window_scaling" = "1" ]; then
    ui_success "TCP 窗口缩放已经启用，无需修改。"
  fi

  mkdir -p /etc/sysctl.d
  if mv "$tmp_file" "$SYSCTL_CONF_FILE"; then
    chmod 644 "$SYSCTL_CONF_FILE"
    if [ "$applied" -gt 0 ]; then
      ui_success "无损网络优化完成，已保存 $applied 项经过验证的设置。"
    else
      ui_success "未发现需要修改的内核参数；旧版激进配置已清理。"
    fi
  else
    rm -f "$tmp_file"
    ui_warn "当前参数已尝试应用，但无法保存到 $SYSCTL_CONF_FILE。"
  fi
}

ipv6_settings_menu() {
  need_root
  ensure_installed
  load_network_settings
  current_listen="$(listener_address)"
  if [ "$MIHOMO_IPV6" = "true" ]; then
    current_ipv6="已开启"
  else
    current_ipv6="已关闭"
  fi
  if [ "$MIHOMO_PREFER_IPV6" = "true" ]; then
    current_share="优先 IPv6"
  else
    current_share="优先 IPv4"
  fi

  screen_title "IPv6 支持设置"
  cat <<EOF
 当前状态：IPv6 $current_ipv6，分享链接 $current_share，监听地址 $current_listen
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}1.${C_RESET} 关闭 IPv6，恢复 IPv4 监听
 ${C_GREEN}2.${C_RESET} 开启 IPv6 监听，分享链接继续优先 IPv4
 ${C_GREEN}3.${C_RESET} 开启 IPv6 监听，分享链接优先 IPv6
 ${C_GREEN}4.${C_RESET} 手动设置分享 IP（IPv4 或 IPv6）
 ${C_GREEN}5.${C_RESET} 刷新公网 IP 缓存
 ${C_GREEN}0.${C_RESET} => 返回主菜单
${C_CYAN}====================================================${C_RESET}
EOF
  ui_prompt "请输入数字选择 (0-5)："
  read -r ipv6_choice || true

  case "$ipv6_choice" in
    1)
      MIHOMO_IPV6="false"
      MIHOMO_PREFER_IPV6="false"
      write_network_settings
      render_config || return 1
      restart_service || return 1
      ui_success "已关闭 IPv6，监听地址恢复为 0.0.0.0。"
      ;;
    2)
      MIHOMO_IPV6="true"
      MIHOMO_PREFER_IPV6="false"
      write_network_settings
      render_config || return 1
      restart_service || return 1
      ui_success "已开启 IPv6 监听，分享链接继续优先使用 IPv4。"
      ;;
    3)
      MIHOMO_IPV6="true"
      MIHOMO_PREFER_IPV6="true"
      write_network_settings
      render_config || return 1
      restart_service || return 1
      ui_success "已开启 IPv6 监听，分享链接将优先使用 IPv6。"
      ;;
    4)
      ui_prompt "请输入要写入分享链接的公网 IP（IPv4 或 IPv6）："
      read -r manual_ip || true
      manual_ip="$(printf '%s' "$manual_ip" | tr -d '[:space:]')"
      if is_ipv6 "$manual_ip"; then
        MIHOMO_IPV6="true"
        MIHOMO_PREFER_IPV6="true"
        write_network_settings
        cache_public_ip ipv6 "$manual_ip"
        render_config || return 1
        restart_service || return 1
        ui_success "已保存 IPv6 分享地址：$manual_ip。"
      elif is_ipv4 "$manual_ip"; then
        MIHOMO_PREFER_IPV6="false"
        write_network_settings
        cache_public_ip ipv4 "$manual_ip"
        render_config || return 1
        restart_service || return 1
        ui_success "已保存 IPv4 分享地址：$manual_ip。"
      else
        ui_error "IP 地址格式无效。"
        return 1
      fi
      ;;
    5)
      rm -f "$PUBLIC_IP_CACHE_FILE"
      ui_success "公网 IP 缓存已清空，下次查看或生成节点时会重新获取。"
      ;;
    0)
      ui_warn "已取消 IPv6 设置。"
      return 0
      ;;
    *)
      ui_error "无效选择。"
      return 1
      ;;
  esac
}

cloudflared_status_text() {
  if cloudflared_service_is_running; then
    printf '运行中'
  elif [ "$(service_manager)" = "unknown" ]; then
    printf '未知'
  else
    printf '未运行'
  fi
}

cloudflared_version_text() {
  if [ -x "$CLOUDFLARED_BIN" ]; then
    "$CLOUDFLARED_BIN" --version 2>/dev/null | sed -n '1p' | sed 's/^cloudflared version //'
  else
    printf '未安装'
  fi
}

cloudflared_connection_count() {
  if command -v nc >/dev/null 2>&1; then
    metrics_connections="$(
      printf 'GET /metrics HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' |
        run_with_timeout 2 nc -w 1 127.0.0.1 20241 2>/dev/null |
        awk '
          BEGIN { body = 0 }
          { sub(/\r$/, "") }
          body && /^cloudflared_tunnel_ha_connections([{ ]|$)/ { total += $NF; found = 1 }
          !body && $0 == "" { body = 1 }
          END { if (found) printf "%d", total }
        '
    )"
    case "$metrics_connections" in
      ''|*[!0-9]*) ;;
      *) printf '%s' "$metrics_connections"; return ;;
    esac
  fi
  command -v curl >/dev/null 2>&1 || { printf '不可用'; return; }
  metrics_data="$(curl -fsS --max-time 2 "$CLOUDFLARED_METRICS_URL" 2>/dev/null || true)"
  [ -n "$metrics_data" ] || { printf '未知（本地监控不可用）'; return; }
  printf '%s\n' "$metrics_data" | awk '
    /^cloudflared_tunnel_ha_connections([{ ]|$)/ { total += $NF; found = 1 }
    END { if (found) printf "%d", total; else printf "0" }
  '
}

cloudflared_process_is_running() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x cloudflared >/dev/null 2>&1 && return 0
  fi
  if command -v pidof >/dev/null 2>&1; then
    pidof cloudflared >/dev/null 2>&1 && return 0
  fi
  ps 2>/dev/null | awk '$0 ~ /[\/]usr[\/]local[\/]bin[\/]cloudflared/ && $0 !~ /supervise-daemon/ { found=1 } END { exit !found }'
}

cloudflared_service_is_running() {
  manager="$(service_manager)"
  case "$manager" in
    systemd) systemctl is-active --quiet "$CLOUDFLARED_SERVICE" 2>/dev/null && cloudflared_process_is_running ;;
    openrc) rc-service "$CLOUDFLARED_SERVICE" status >/dev/null 2>&1 && cloudflared_process_is_running ;;
    *) return 1 ;;
  esac
}

cloudflared_arch() {
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7) printf 'arm' ;;
    i386|i486|i586|i686) printf '386' ;;
    *) return 1 ;;
  esac
}

cloudflared_memory_limit() {
  cf_memory_mib="$(memory_limit_mib)"
  case "$cf_memory_mib" in
    ''|*[!0-9]*) printf '96MiB' ;;
    *)
      if [ "$cf_memory_mib" -le 192 ]; then
        printf '48MiB'
      elif [ "$cf_memory_mib" -le 256 ]; then
        printf '64MiB'
      elif [ "$cf_memory_mib" -le 512 ]; then
        printf '96MiB'
      else
        printf '128MiB'
      fi
      ;;
  esac
}

write_cloudflared_runner() {
  mkdir -p "$(dirname "$CLOUDFLARED_RUNNER")"
  cf_go_memory="$(cloudflared_memory_limit)"
  cat > "$CLOUDFLARED_RUNNER" <<EOF
#!/bin/sh
set -eu
TOKEN_FILE="$CLOUDFLARED_TOKEN_FILE"
[ -s "\$TOKEN_FILE" ] || { echo "Cloudflare Tunnel Token 不存在" >&2; exit 1; }
export GOMEMLIMIT="$cf_go_memory"
export GOGC="125"
export GODEBUG="madvdontneed=1"
exec "$CLOUDFLARED_BIN" tunnel --no-autoupdate --protocol http2 --metrics "$CLOUDFLARED_METRICS" run --token-file "$CLOUDFLARED_TOKEN_FILE"
EOF
  chmod 700 "$CLOUDFLARED_RUNNER"
}

write_cloudflared_service() {
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      cat > "/etc/systemd/system/${CLOUDFLARED_SERVICE}.service" <<EOF
[Unit]
Description=Cloudflare Tunnel for Mihomo Lite
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$CLOUDFLARED_RUNNER
Restart=always
RestartSec=5s
LimitNOFILE=262144
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable "$CLOUDFLARED_SERVICE" >/dev/null
      systemctl restart "$CLOUDFLARED_SERVICE"
      ;;
    openrc)
      cat > "/etc/init.d/${CLOUDFLARED_SERVICE}" <<EOF
#!/sbin/openrc-run
description="Cloudflare Tunnel for Mihomo Lite"
command="$CLOUDFLARED_RUNNER"
output_log="$CLOUDFLARED_LOG"
error_log="$CLOUDFLARED_LOG"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0
rc_ulimit="-n 262144"

depend() {
  need net
  after firewall
}
EOF
      chmod +x "/etc/init.d/${CLOUDFLARED_SERVICE}"
      rc-update add "$CLOUDFLARED_SERVICE" default >/dev/null
      rc-service "$CLOUDFLARED_SERVICE" restart
      ;;
    *)
      ui_error "未找到 systemd 或 OpenRC，无法创建 Tunnel 服务。"
      return 1
      ;;
  esac
}

restart_cloudflared_service() {
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      systemctl daemon-reload || return 1
      systemctl restart "$CLOUDFLARED_SERVICE" || return 1
      ;;
    openrc)
      rc-service "$CLOUDFLARED_SERVICE" restart || return 1
      ;;
    *) return 1 ;;
  esac
  cloudflared_wait=0
  while [ "$cloudflared_wait" -lt 15 ]; do
    cloudflared_service_is_running && return 0
    sleep 1
    cloudflared_wait=$((cloudflared_wait + 1))
  done
  return 1
}

install_cloudflared() {
  need_root
  detect_os
  check_internal_ports cloudflared || return 1
  ensure_curl
  cf_arch="$(cloudflared_arch)" || {
    ui_error "暂不支持当前 CPU 架构：$(uname -m)。"
    return 1
  }

  ui_prompt "请粘贴 Cloudflare Tunnel Token（输入时隐藏）："
  if [ -t 0 ]; then
    old_stty="$(stty -g 2>/dev/null || true)"
    stty -echo 2>/dev/null || true
    read -r tunnel_token || true
    [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null || true
    printf '\n'
  else
    read -r tunnel_token || true
  fi
  tunnel_token="$(printf '%s' "$tunnel_token" | tr -d '\r\n[:space:]')"
  if [ -z "$tunnel_token" ]; then
    ui_error "Token 不能为空。"
    return 1
  fi

  tmp_file="$(make_temp /tmp/cloudflared.XXXXXX)"
  cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
  ui_section "下载 cloudflared (${cf_arch})"
  if ! curl -fL --retry 3 --connect-timeout 15 "$cf_url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    ui_error "cloudflared 下载失败。"
    return 1
  fi
  verify_remote_checksum "$cf_url" "$tmp_file"
  verify_result=$?
  [ "$verify_result" -ne 1 ] || { rm -f "$tmp_file"; return 1; }
  chmod 755 "$tmp_file"
  if ! "$tmp_file" --version >/dev/null 2>&1; then
    rm -f "$tmp_file"
    ui_error "下载的 cloudflared 无法运行，已取消更新。"
    return 1
  fi
  if [ -x "$CLOUDFLARED_BIN" ]; then
    cp "$CLOUDFLARED_BIN" "$CLOUDFLARED_BACKUP_BIN"
    chmod 755 "$CLOUDFLARED_BACKUP_BIN"
  fi
  mv "$tmp_file" "$CLOUDFLARED_BIN"

  mkdir -p "$CLOUDFLARED_CONFIG_DIR"
  printf '%s\n' "$tunnel_token" > "$CLOUDFLARED_TOKEN_FILE"
  chmod 600 "$CLOUDFLARED_TOKEN_FILE"
  tunnel_token=""

  write_cloudflared_runner
  if ! write_cloudflared_service || ! cloudflared_service_is_running; then
    ui_error "cloudflared 新版本启动失败，正在恢复上一版本。"
    if [ -x "$CLOUDFLARED_BACKUP_BIN" ]; then
      cp "$CLOUDFLARED_BACKUP_BIN" "$CLOUDFLARED_BIN"
      restart_cloudflared_service >/dev/null 2>&1 || true
    fi
    return 1
  fi
  ui_success "Argo 固定隧道已安装并设为开机启动。"
  enable_tunnel_watchdog || ui_warn "自动恢复未能启用，可稍后在 Tunnel 菜单手动启用。"
  ui_warn "下一步：Cloudflare Tunnel 后台添加公共主机名，服务填写 http://127.0.0.1:Mihomo的VLESS-WS端口。"
  ui_warn "客户端使用域名:443、TLS、相同 Host 和 WebSocket Path；无需映射该 WS 端口，也无需 DDNS。"
}

restart_cloudflared() {
  need_root
  ensure_installed
  argo_record="$(awk -F'|' '$1 == "vless-ws" && $7 == "argo" { print; exit }' "$NODES_DB" 2>/dev/null)"
  if [ -n "$argo_record" ]; then
    IFS='|' read -r _ _ argo_port _ argo_path argo_host _ _ _ <<EOF
$argo_record
EOF
    if ! websocket_probe "http://127.0.0.1:$argo_port$argo_path" "$argo_host"; then
      ui_warn "本地 Argo 源站不可用，先重启 Mihomo。"
      restart_service || { ui_error "Mihomo 源站重启失败。"; return 1; }
    fi
  elif ! service_is_running; then
    ui_warn "Mihomo 未运行，先恢复 Mihomo 服务。"
    restart_service || return 1
  fi

  write_cloudflared_runner
  if ! write_cloudflared_service || ! cloudflared_service_is_running; then
    ui_error "Argo Tunnel 重启失败，正在输出故障诊断。"
    tunnel_diagnostics
    return 1
  fi
  connection_wait=0
  while [ "$connection_wait" -lt 12 ]; do
    cf_connections="$(cloudflared_connection_count)"
    case "$cf_connections" in ''|0|'未知'*|'不可用') sleep 1 ;; *) break ;; esac
    connection_wait=$((connection_wait + 1))
  done
  ui_success "Argo Tunnel 已重启，边缘连接：${cf_connections:-未知}。"
  tunnel_watchdog_enabled || enable_tunnel_watchdog || true
  if [ -n "$argo_record" ]; then
    websocket_probe "http://127.0.0.1:$argo_port$argo_path" "$argo_host" || true
  fi
}

tunnel_diagnostics() {
  screen_title "Tunnel 压力与故障诊断"
  printf ' Mihomo：%s | cloudflared：%s | 边缘连接：%s\n' \
    "$(service_status_text)" "$(cloudflared_status_text)" "$(cloudflared_connection_count)"
  if command -v free >/dev/null 2>&1; then
    ui_section "内存"
    free -m 2>/dev/null || true
  fi
  ui_section "进程资源（RSS 单位 KiB）"
  ps -eo pid,rss,vsz,comm 2>/dev/null | awk 'NR == 1 || $4 ~ /mihomo|cloudflared/' || true
  for memory_events in /sys/fs/cgroup/memory.events /sys/fs/cgroup/memory/memory.failcnt; do
    [ -r "$memory_events" ] || continue
    ui_section "$memory_events"
    sed -n '1,20p' "$memory_events" 2>/dev/null || true
  done
  ui_section "最近的 OOM / kill 记录"
  if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | grep -Ei 'out of memory|oom-kill|killed process' | tail -n 10 || ui_warn "未读取到 OOM 记录或容器禁止读取 dmesg。"
  fi
  ui_section "最近服务日志"
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      journalctl -u "$SERVICE_NAME" -u "$CLOUDFLARED_SERVICE" -n 30 --no-pager 2>/dev/null || true
      ;;
    openrc)
      tail -n 20 "$LOG_DIR/${SERVICE_NAME}.err" "$LOG_DIR/${SERVICE_NAME}.log" "$CLOUDFLARED_LOG" 2>/dev/null || true
      ;;
  esac
  ui_warn "若 oom/oom_kill 增长，说明多线程测速超过容器内存承载能力；优先使用菜单 44 的省资源稳连模式并降低测速线程数。"
}

tunnel_watchdog_cron_line() {
  printf '* * * * * %s tunnel-watchdog >/dev/null 2>&1 # %s\n' "$CLI_PATH" "$TUNNEL_WATCHDOG_CRON_MARK"
}

tunnel_watchdog_enabled() {
  command -v crontab >/dev/null 2>&1 || return 1
  crontab -l 2>/dev/null | grep -q "$TUNNEL_WATCHDOG_CRON_MARK"
}

tunnel_local_origin_healthy() {
  watchdog_record="$(awk -F'|' '$1 == "vless-ws" && $7 == "argo" { print; exit }' "$NODES_DB" 2>/dev/null)"
  [ -n "$watchdog_record" ] || return 0
  IFS='|' read -r _ _ watchdog_port _ watchdog_path watchdog_host _ _ _ <<EOF
$watchdog_record
EOF
  watchdog_status=""
  if command -v nc >/dev/null 2>&1; then
    watchdog_status="$(
      printf 'GET %s HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n' \
        "$watchdog_path" "$watchdog_host" |
        run_with_timeout 3 nc -w 2 127.0.0.1 "$watchdog_port" 2>/dev/null |
        sed -n '1{s/\r$//;p;q;}' || true
    )"
  fi
  if [ -z "$watchdog_status" ]; then
    watchdog_status="$(curl --http1.1 -sS -i -N --max-time 4 \
      -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
      -H "Host: $watchdog_host" "http://127.0.0.1:$watchdog_port$watchdog_path" 2>/dev/null | sed -n '1{s/\r$//;p;}' || true)"
  fi
  case "$watchdog_status" in *' 101 '*) return 0 ;; *) return 1 ;; esac
}

run_tunnel_watchdog() {
  [ -x "$CLOUDFLARED_BIN" ] && [ -s "$CLOUDFLARED_TOKEN_FILE" ] || return 0
  mkdir -p "$CLOUDFLARED_CONFIG_DIR" "$LOG_DIR"
  if [ -d "$TUNNEL_WATCHDOG_LOCK" ]; then
    watchdog_lock_pid="$(cat "$TUNNEL_WATCHDOG_LOCK/pid" 2>/dev/null || true)"
    case "$watchdog_lock_pid" in
      ''|*[!0-9]*) rm -rf "$TUNNEL_WATCHDOG_LOCK" ;;
      *) kill -0 "$watchdog_lock_pid" 2>/dev/null || rm -rf "$TUNNEL_WATCHDOG_LOCK" ;;
    esac
  fi
  mkdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || return 0
  printf '%s\n' "$$" > "$TUNNEL_WATCHDOG_LOCK/pid"
  trap 'rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true' 0 HUP INT TERM

  watchdog_failures=0
  watchdog_last_restart=0
  if [ -r "$TUNNEL_WATCHDOG_STATE" ]; then
    IFS='|' read -r watchdog_failures watchdog_last_restart < "$TUNNEL_WATCHDOG_STATE" || true
  fi
  case "$watchdog_failures" in ''|*[!0-9]*) watchdog_failures=0 ;; esac
  case "$watchdog_last_restart" in ''|*[!0-9]*) watchdog_last_restart=0 ;; esac

  watchdog_connections="$(cloudflared_connection_count)"
  watchdog_process_ok=0
  watchdog_origin_ok=0
  cloudflared_service_is_running && watchdog_process_ok=1
  tunnel_local_origin_healthy && watchdog_origin_ok=1
  case "$watchdog_connections" in ''|0|'未知'*|'不可用') watchdog_edge_ok=0 ;; *) watchdog_edge_ok=1 ;; esac

  if [ "$watchdog_process_ok" = "1" ] && [ "$watchdog_origin_ok" = "1" ] && [ "$watchdog_edge_ok" = "1" ]; then
    printf '0|%s\n' "$watchdog_last_restart" > "$TUNNEL_WATCHDOG_STATE"
    chmod 600 "$TUNNEL_WATCHDOG_STATE"
    rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true
    trap - 0 HUP INT TERM
    return 0
  fi

  watchdog_failures=$((watchdog_failures + 1))
  watchdog_now="$(date +%s 2>/dev/null || printf '0')"
  printf '%s|%s\n' "$watchdog_failures" "$watchdog_last_restart" > "$TUNNEL_WATCHDOG_STATE"
  chmod 600 "$TUNNEL_WATCHDOG_STATE"

  if [ "$watchdog_process_ok" = "1" ] && [ "$watchdog_failures" -lt 2 ]; then
    rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true
    trap - 0 HUP INT TERM
    return 0
  fi
  if [ "$watchdog_now" -gt 0 ] && [ $((watchdog_now - watchdog_last_restart)) -lt 300 ]; then
    rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true
    trap - 0 HUP INT TERM
    return 0
  fi

  printf '%s watchdog recovery: process=%s origin=%s edge=%s failures=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf unknown)" \
    "$watchdog_process_ok" "$watchdog_origin_ok" "$watchdog_edge_ok" "$watchdog_failures" >> "$TUNNEL_WATCHDOG_LOG"
  if [ "$watchdog_origin_ok" != "1" ]; then
    restart_service >> "$TUNNEL_WATCHDOG_LOG" 2>&1 || true
  fi
  restart_cloudflared_service >> "$TUNNEL_WATCHDOG_LOG" 2>&1 || true
  printf '0|%s\n' "$watchdog_now" > "$TUNNEL_WATCHDOG_STATE"
  chmod 600 "$TUNNEL_WATCHDOG_STATE"
  rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true
  trap - 0 HUP INT TERM
}

enable_tunnel_watchdog() {
  ensure_cron_service || return 1
  tmp_file="$(make_temp /tmp/mh-tunnel-cron.XXXXXX)"
  crontab -l 2>/dev/null | grep -v "$TUNNEL_WATCHDOG_CRON_MARK" > "$tmp_file" || true
  tunnel_watchdog_cron_line >> "$tmp_file"
  if ! crontab "$tmp_file"; then
    rm -f "$tmp_file"
    ui_error "自动恢复任务写入失败。"
    return 1
  fi
  rm -f "$tmp_file"
  ui_success "Tunnel 自动恢复已启用：每分钟检查，连续异常2次才修复，重启冷却5分钟。"
}

disable_tunnel_watchdog() {
  if command -v crontab >/dev/null 2>&1; then
    tmp_file="$(make_temp /tmp/mh-tunnel-cron.XXXXXX)"
    crontab -l 2>/dev/null | grep -v "$TUNNEL_WATCHDOG_CRON_MARK" > "$tmp_file" || true
    crontab "$tmp_file" >/dev/null 2>&1 || true
    rm -f "$tmp_file"
  fi
  rm -f "$TUNNEL_WATCHDOG_STATE"
  rmdir "$TUNNEL_WATCHDOG_LOCK" 2>/dev/null || true
  ui_success "Tunnel 自动恢复已关闭。"
}

tunnel_watchdog_menu() {
  if tunnel_watchdog_enabled; then
    ui_warn "Tunnel 自动恢复当前已启用。"
    ui_prompt "是否关闭？[y/N]："
    read -r watchdog_choice || true
    case "$watchdog_choice" in y|Y|yes|YES) disable_tunnel_watchdog ;; *) return 0 ;; esac
  else
    ui_warn "Tunnel 自动恢复当前未启用。"
    ui_prompt "是否启用？[Y/n]："
    read -r watchdog_choice || true
    case "$watchdog_choice" in n|N|no|NO) return 0 ;; *) enable_tunnel_watchdog ;; esac
  fi
}

rollback_cloudflared() {
  need_root
  [ -x "$CLOUDFLARED_BACKUP_BIN" ] || { ui_error "没有可回滚的 cloudflared 版本。"; return 1; }
  current_tmp="$(make_temp /tmp/cloudflared-current.XXXXXX)"
  cp "$CLOUDFLARED_BIN" "$current_tmp" 2>/dev/null || true
  cp "$CLOUDFLARED_BACKUP_BIN" "$CLOUDFLARED_BIN"
  chmod 755 "$CLOUDFLARED_BIN"
  if restart_cloudflared_service; then
    [ -s "$current_tmp" ] && mv "$current_tmp" "$CLOUDFLARED_BACKUP_BIN" || rm -f "$current_tmp"
    ui_success "cloudflared 已回滚并正常运行：$(cloudflared_version_text)"
  else
    [ -s "$current_tmp" ] && mv "$current_tmp" "$CLOUDFLARED_BIN" || true
    restart_cloudflared_service >/dev/null 2>&1 || true
    ui_error "回滚版本无法启动，已恢复回滚前版本。"
    return 1
  fi
}

show_cloudflared_logs() {
  ui_warn "按 Ctrl+C 停止查看日志。"
  manager="$(service_manager)"
  case "$manager" in
    systemd) journalctl -u "$CLOUDFLARED_SERVICE" -f --no-pager ;;
    openrc) touch "$CLOUDFLARED_LOG"; tail -F "$CLOUDFLARED_LOG" ;;
    *) ui_error "未找到服务管理器。"; return 1 ;;
  esac
}

uninstall_cloudflared() {
  need_root
  ui_prompt "确认卸载 Argo Tunnel？Mihomo 和节点不会被删除 [y/N]："
  read -r confirm || true
  case "$confirm" in y|Y|yes|YES) ;; *) ui_warn "已取消。"; return 0 ;; esac
  remove_cloudflared_files
  ui_success "Argo Tunnel 已卸载，Mihomo 未受影响。"
}

remove_cloudflared_files() {
  disable_tunnel_watchdog >/dev/null 2>&1 || true
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      systemctl disable --now "$CLOUDFLARED_SERVICE" 2>/dev/null || true
      rm -f "/etc/systemd/system/${CLOUDFLARED_SERVICE}.service"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-service "$CLOUDFLARED_SERVICE" stop 2>/dev/null || true
      rc-update del "$CLOUDFLARED_SERVICE" default 2>/dev/null || true
      rm -f "/etc/init.d/${CLOUDFLARED_SERVICE}"
      ;;
  esac
  rm -f "$CLOUDFLARED_BIN" "$CLOUDFLARED_BACKUP_BIN" "$CLOUDFLARED_RUNNER" "$CLOUDFLARED_TOKEN_FILE" "$CLOUDFLARED_LOG"
  rmdir "$CLOUDFLARED_CONFIG_DIR" 2>/dev/null || true
}

list_vless_ws_nodes() {
  [ -s "$NODES_DB" ] || { ui_warn "当前没有节点。"; return 1; }
  ws_count=0
  while IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6; do
    [ "$proto" = "vless-ws" ] || continue
    ws_count=$((ws_count + 1))
    ws_mode="${value4:-legacy}"
    printf ' %s%s.%s %s  local=%s  mode=%s\n' "$C_GREEN" "$ws_count" "$C_RESET" "$node_name" "$node_port" "$ws_mode"
  done < "$NODES_DB"
  [ "$ws_count" -gt 0 ] || { ui_warn "当前没有 VLESS-WS 节点。"; return 1; }
}

select_vless_ws_node() {
  list_vless_ws_nodes || return 1
  ui_prompt "请输入 VLESS-WS 节点编号（0 返回）："
  read -r ws_choice || true
  case "$ws_choice" in
    0) return 1 ;;
    ''|*[!0-9]*) ui_error "请输入有效数字。"; return 1 ;;
  esac
  SELECTED_WS_RECORD="$(awk -F'|' -v n="$ws_choice" '$1 == "vless-ws" { i++; if (i == n) { print; exit } }' "$NODES_DB")"
  [ -n "$SELECTED_WS_RECORD" ] || { ui_error "未找到编号 $ws_choice。"; return 1; }
  SELECTED_WS_INDEX="$ws_choice"
}

show_argo_nodes() {
  ensure_installed
  screen_title "查看 Argo 节点与路由信息"
  found=0
  SHARE_SERVER_IP="$(public_ip)"
  export SHARE_SERVER_IP
  while IFS='|' read -r proto node_name node_port value1 value2 value3 value4 value5 value6; do
    [ "$proto" = "vless-ws" ] || continue
    [ "${value4:-}" = "argo" ] || continue
    found=$((found + 1))
    node_link="$(node_share_link "$proto" "$node_name" "$node_port" "$value1" "$value2" "$value3" "$value4" "$value5" "$value6")"
    ui_section "$node_name"
    printf ' 公共主机名：%s\n 本地服务：http://127.0.0.1:%s\n WebSocket Path：%s\n 节点链接：%s\n\n' \
      "$value3" "$node_port" "$value2" "$node_link"
  done < "$NODES_DB"
  [ "$found" -gt 0 ] || ui_warn "当前没有 Argo 节点，请从主菜单 1 创建 VLESS-WS 并选择 Argo 模式。"
}

websocket_probe() {
  probe_url="$1"
  probe_host="$2"
  ensure_curl
  probe_file="$(make_temp /tmp/mh-ws-probe.XXXXXX)"
  curl --http1.1 -sS -i -N --max-time 6 \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    -H "Host: $probe_host" \
    "$probe_url" > "$probe_file" 2>/dev/null || true
  probe_status="$(sed -n '1{s/\r$//;p;}' "$probe_file")"
  rm -f "$probe_file"
  case "$probe_status" in
    *' 101 '*) ui_success "WebSocket 握手成功：$probe_status"; return 0 ;;
    *' 400 '*) ui_error "HTTP 400：Host、Path 或 WebSocket Upgrade 参数不匹配。"; return 1 ;;
    *' 404 '*) ui_error "HTTP 404：WebSocket Path 或 Tunnel 路由不正确。"; return 1 ;;
    *' 502 '*) ui_error "HTTP 502：Tunnel 无法连接本地 Mihomo，请核对 http://127.0.0.1:本地端口。"; return 1 ;;
    *' 521 '*) ui_error "HTTP 521：域名可能仍指向源站，请检查是否错误保留了 A/AAAA 记录。"; return 1 ;;
    '') ui_error "未收到响应：请检查 DNS、Tunnel 在线状态及本机网络。"; return 1 ;;
    *) ui_error "WebSocket 握手失败：$probe_status"; ui_warn "请依次核对 Tunnel 公共主机名、Host、Path 和本地服务端口。"; return 1 ;;
  esac
}

test_argo_node() {
  test_scope="$1"
  ensure_installed
  screen_title "检测 Argo WebSocket"
  select_vless_ws_node || return 0
  IFS='|' read -r proto node_name node_port node_uuid ws_path ws_host ws_mode ws_entry ws_entry_port <<EOF
$SELECTED_WS_RECORD
EOF
  [ "${ws_mode:-}" = "argo" ] || { ui_error "节点 $node_name 尚未配置为 Argo 模式。"; return 1; }
  case "$test_scope" in
    local)
      ui_warn "检测本地源站：http://127.0.0.1:$node_port$ws_path"
      websocket_probe "http://127.0.0.1:$node_port$ws_path" "$ws_host"
      ;;
    public)
      ui_warn "检测公网 Tunnel：https://$ws_host:443$ws_path"
      websocket_probe "https://$ws_host:443$ws_path" "$ws_host"
      ;;
  esac
}

cloudflared_menu() {
  while true; do
    screen_title "Argo / Cloudflare Tunnel 管理"
    cf_status="$(cloudflared_status_text)"
    cf_version="$(cloudflared_version_text)"
    cf_connections="$(cloudflared_connection_count)"
    tunnel_watchdog_enabled && watchdog_status="已启用" || watchdog_status="未启用"
    printf ' 当前状态：%s | 版本：%s | 活跃连接：%s | 自动恢复：%s\n' "$cf_status" "$cf_version" "$cf_connections" "$watchdog_status"
    ui_dash
    printf ' %s1.%s 安装 / 更新并配置 Tunnel Token\n' "$C_GREEN" "$C_RESET"
    printf ' %s2.%s 查看 Argo 节点、路由信息和链接\n' "$C_GREEN" "$C_RESET"
    printf ' %s3.%s 检测本地 WebSocket 101\n' "$C_GREEN" "$C_RESET"
    printf ' %s4.%s 检测公网 Tunnel WebSocket 101\n' "$C_GREEN" "$C_RESET"
    printf ' %s5.%s 重启 Tunnel\n' "$C_GREEN" "$C_RESET"
    printf ' %s6.%s 查看实时日志\n' "$C_GREEN" "$C_RESET"
    printf ' %s7.%s 回滚 cloudflared 到上一版本\n' "$C_GREEN" "$C_RESET"
    printf ' %s8.%s 压力 / OOM / 服务故障诊断\n' "$C_GREEN" "$C_RESET"
    printf ' %s9.%s 开启 / 关闭 Tunnel 自动恢复\n' "$C_GREEN" "$C_RESET"
    printf ' %s10.%s 卸载 Tunnel（不影响 Mihomo）\n' "$C_GREEN" "$C_RESET"
    printf ' %s0.%s 返回主菜单\n' "$C_GREEN" "$C_RESET"
    ui_dash
    ui_prompt "请输入数字选择 (0-10)："
    read -r cf_choice || return 0
    case "$cf_choice" in
      1) install_cloudflared; pause ;;
      2) show_argo_nodes; pause ;;
      3) test_argo_node local; pause ;;
      4) test_argo_node public; pause ;;
      5) restart_cloudflared; pause ;;
      6) show_cloudflared_logs ;;
      7) rollback_cloudflared; pause ;;
      8) tunnel_diagnostics; pause ;;
      9) tunnel_watchdog_menu; pause ;;
      10) uninstall_cloudflared; pause ;;
      0) return 0 ;;
      *) ui_error "无效选择。"; pause ;;
    esac
  done
}

update_script() {
  need_root
  ensure_curl

  screen_title "更新管理脚本"
  tmp_file="$(make_temp /tmp/mh-update.XXXXXX)"
  ui_warn "更新来源：$SCRIPT_RAW_URL"
  ui_section "下载最新脚本"
  curl -fsSL "$SCRIPT_RAW_URL" -o "$tmp_file" || {
    rm -f "$tmp_file"
    ui_error "更新失败：无法下载最新脚本。"
    return 1
  }
  verify_remote_checksum "$SCRIPT_RAW_URL" "$tmp_file"
  verify_result=$?
  [ "$verify_result" -ne 1 ] || { rm -f "$tmp_file"; return 1; }

  if ! grep -qi 'mihomo 一键配置管理面板' "$tmp_file"; then
    rm -f "$tmp_file"
    ui_error "更新失败：下载内容不像 mh 脚本，已取消替换。"
    return 1
  fi

  if ! sh -n "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    ui_error "更新失败：下载脚本语法检查未通过，已取消替换。"
    return 1
  fi

  chmod +x "$tmp_file"
  if [ -f "$CLI_PATH" ]; then
    cp "$CLI_PATH" "$CLI_BACKUP_PATH"
    chmod 700 "$CLI_BACKUP_PATH"
  fi
  mv "$tmp_file" "$CLI_PATH"
  ui_success "脚本更新完成。重新输入 mh 可打开新版管理面板。"
  if [ -x "$BIN_PATH" ] && [ -f "$CONFIG_FILE" ]; then
    if "$CLI_PATH" dns-migrate >/dev/null 2>&1; then
      ui_success "已自动检查并迁移 DNS 配置。"
    else
      ui_warn "DNS 自动迁移未完成，请执行 mh dns-migrate 查看详细原因。"
    fi
    if "$CLI_PATH" network-migrate >/dev/null 2>&1; then
      ui_success "已自动检查并迁移旧版网络优化配置。"
    else
      ui_warn "网络优化配置迁移未完成，请执行 mh network-migrate 查看详细原因。"
    fi
    ui_prompt "是否立即使用新版脚本重写服务运行参数并重启 Mihomo？[y/N]："
    read -r apply_runtime_confirm || true
    case "$apply_runtime_confirm" in
      y|Y|yes|YES)
        if "$CLI_PATH" apply-runtime >/dev/null 2>&1; then
          ui_success "已重写服务运行参数并重启 Mihomo。"
        else
          ui_warn "服务运行参数未自动应用，请手动执行 mh apply-runtime 或 mh 44。"
        fi
        ;;
      *)
        ui_warn "如本次更新包含运行参数或服务模板变化，请执行 mh apply-runtime 或 mh 44 后生效。"
        ;;
    esac
  fi
}

rollback_script() {
  need_root
  [ -f "$CLI_BACKUP_PATH" ] || { ui_error "没有可回滚的管理脚本版本。"; return 1; }
  sh -n "$CLI_BACKUP_PATH" 2>/dev/null || { ui_error "上一版脚本语法检查失败，拒绝回滚。"; return 1; }
  rollback_tmp="$(make_temp /tmp/mh-current.XXXXXX)"
  cp "$CLI_PATH" "$rollback_tmp" 2>/dev/null || true
  cp "$CLI_BACKUP_PATH" "$CLI_PATH"
  chmod 700 "$CLI_PATH"
  [ -s "$rollback_tmp" ] && mv "$rollback_tmp" "$CLI_BACKUP_PATH" || rm -f "$rollback_tmp"
  ui_success "管理脚本已回滚。重新输入 mh 使用上一版本。"
}

version_rollback_menu() {
  screen_title "版本回滚"
  printf ' %s1.%s 回滚 Mihomo 内核\n' "$C_GREEN" "$C_RESET"
  printf ' %s2.%s 回滚 cloudflared\n' "$C_GREEN" "$C_RESET"
  printf ' %s3.%s 回滚 mh 管理脚本\n' "$C_GREEN" "$C_RESET"
  printf ' %s0.%s 返回\n' "$C_GREEN" "$C_RESET"
  ui_prompt "请输入数字选择 (0-3)："
  read -r rollback_choice || true
  case "$rollback_choice" in
    1) rollback_core ;;
    2) rollback_cloudflared ;;
    3) rollback_script ;;
    0) return 0 ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac
}

health_check() {
  screen_title "系统健康检查"
  health_errors=0
  health_warnings=0

  if [ -x "$BIN_PATH" ] && [ -f "$CONFIG_FILE" ] && "$BIN_PATH" -t -d "$CONFIG_DIR" -f "$CONFIG_FILE" >/dev/null 2>&1; then
    ui_success "Mihomo 配置语法正常。"
  else
    ui_error "Mihomo 配置自检失败或内核/配置不存在。"
    health_errors=$((health_errors + 1))
  fi
  if service_is_running; then
    ui_success "Mihomo 服务正在运行。"
  else
    ui_error "Mihomo 服务未运行。"
    health_errors=$((health_errors + 1))
  fi

  health_memory_current="$(cat /sys/fs/cgroup/memory.current 2>/dev/null || true)"
  health_memory_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
  case "$health_memory_current:$health_memory_max" in
    *[!0-9:]*|:*) ;;
    *)
      health_memory_current_mib=$((health_memory_current / 1048576))
      health_memory_max_mib=$((health_memory_max / 1048576))
      if [ "$health_memory_max" -gt 0 ]; then
        health_memory_percent=$((health_memory_current * 100 / health_memory_max))
        if [ "$health_memory_percent" -ge 90 ]; then
          ui_warn "容器内存使用 ${health_memory_current_mib}/${health_memory_max_mib} MiB（${health_memory_percent}%），余量较低。"
          health_warnings=$((health_warnings + 1))
        else
          ui_success "容器内存使用 ${health_memory_current_mib}/${health_memory_max_mib} MiB（${health_memory_percent}%）。"
        fi
      fi
      ;;
  esac

  health_oom_kill="$(awk '$1 == "oom_kill" { print $2; exit }' /sys/fs/cgroup/memory.events 2>/dev/null || true)"
  case "$health_oom_kill" in
    ''|*[!0-9]*) ;;
    *)
      health_previous_oom="$(cat "$OOM_STATE_FILE" 2>/dev/null || true)"
      case "$health_previous_oom" in ''|*[!0-9]*) health_previous_oom="$health_oom_kill" ;; esac
      if [ "$health_oom_kill" -gt "$health_previous_oom" ]; then
        ui_warn "检测到新增 OOM Kill：$((health_oom_kill - health_previous_oom)) 次（累计 $health_oom_kill 次）。"
        health_warnings=$((health_warnings + 1))
      elif [ "$health_oom_kill" -gt 0 ] && [ ! -s "$OOM_STATE_FILE" ]; then
        ui_warn "检测到历史 OOM Kill：累计 $health_oom_kill 次；已记录当前基线。"
        health_warnings=$((health_warnings + 1))
      else
        ui_success "本次检查未发现新增 OOM Kill（累计 $health_oom_kill 次）。"
      fi
      printf '%s\n' "$health_oom_kill" > "$OOM_STATE_FILE"
      chmod 600 "$OOM_STATE_FILE"
      ;;
  esac

  dns_upstreams="$(configured_dns_servers | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if configured_dns_works; then
    ui_success "DNS 上游可完成解析：${dns_upstreams:-未列出地址}。"
  else
    ui_error "DNS 上游不可达：${dns_upstreams:-配置缺失}。这是 DNS 故障，不代表节点监听故障。"
    health_errors=$((health_errors + 1))
  fi
  probe_public_dns
  if [ -n "$dns_public_udp" ]; then
    ui_success "公共 DNS UDP/53 可用：$dns_public_udp。"
  else
    ui_warn "公共 DNS UDP/53 均不可用；将优先使用系统有效 DNS。"
    health_warnings=$((health_warnings + 1))
  fi
  if [ -n "$dns_public_tcp" ]; then
    ui_success "公共 DNS TCP/53 可用：$dns_public_tcp。"
  else
    ui_warn "公共 DNS TCP/53 均不可用或系统缺少可用探测工具。"
    health_warnings=$((health_warnings + 1))
  fi

  malformed_nodes="$(awk -F'|' 'NF && NF != 9 { count++ } END { print count + 0 }' "$NODES_DB" 2>/dev/null)"
  duplicate_names="$(awk -F'|' 'NF { count[$2]++ } END { for (n in count) if (count[n] > 1) duplicate++ ; print duplicate + 0 }' "$NODES_DB" 2>/dev/null)"
  duplicate_ports="$(awk -F'|' 'NF { count[$3]++ } END { for (p in count) if (count[p] > 1) duplicate++ ; print duplicate + 0 }' "$NODES_DB" 2>/dev/null)"
  malformed_nodes="${malformed_nodes:-0}"
  duplicate_names="${duplicate_names:-0}"
  duplicate_ports="${duplicate_ports:-0}"
  if [ "$malformed_nodes" = "0" ] && [ "$duplicate_names" = "0" ] && [ "$duplicate_ports" = "0" ]; then
    ui_success "节点数据库结构、名称和端口未发现冲突。"
  else
    ui_error "节点数据库异常：格式错误 $malformed_nodes，重名 $duplicate_names，重复端口 $duplicate_ports。"
    health_errors=$((health_errors + 1))
  fi

  missing_listeners=0
  wrong_listener_owner=0
  exposed_argo_listeners=0
  if [ -s "$NODES_DB" ]; then
    while IFS='|' read -r check_proto check_name check_port check_value1 check_value2 check_value3 check_value4 check_value5 check_value6; do
      case "$check_port" in ''|*[!0-9]*) continue ;; esac
      if ! system_port_in_use "$check_port"; then
        missing_listeners=$((missing_listeners + 1))
        continue
      fi
      if command -v ss >/dev/null 2>&1 && ! port_owned_by_process "$check_port" "mihomo"; then
        wrong_listener_owner=$((wrong_listener_owner + 1))
      fi
      if [ "$check_proto" = "vless-ws" ] && [ "${check_value4:-}" = "argo" ]; then
        if ! port_bound_to_loopback "$check_port"; then
          exposed_argo_listeners=$((exposed_argo_listeners + 1))
        fi
      fi
    done < "$NODES_DB"
  fi
  if [ "$missing_listeners" -eq 0 ] && [ "$wrong_listener_owner" -eq 0 ] && [ "$exposed_argo_listeners" -eq 0 ]; then
    ui_success "节点端口均由 Mihomo 正确监听，Argo 节点仅绑定本机。"
  else
    ui_error "监听异常：未监听 $missing_listeners，非 Mihomo 占用 $wrong_listener_owner，Argo 暴露公网 $exposed_argo_listeners。"
    health_errors=$((health_errors + 1))
  fi

  malformed_users="$(awk -F'|' 'NF && NF < 11 { count++ } END { print count + 0 }' "$USERS_DB" 2>/dev/null)"
  duplicate_user_names="$(awk -F'|' 'NF { count[$1]++ } END { for (n in count) if (count[n] > 1) duplicate++; print duplicate + 0 }' "$USERS_DB" 2>/dev/null)"
  duplicate_user_ports="$(awk -F'|' 'NF >= 11 { count[$11]++ } END { for (p in count) if (p != "" && count[p] > 1) duplicate++; print duplicate + 0 }' "$USERS_DB" 2>/dev/null)"
  if [ "${malformed_users:-0}" = "0" ] && [ "${duplicate_user_names:-0}" = "0" ] && [ "${duplicate_user_ports:-0}" = "0" ]; then
    [ -s "$USERS_DB" ] && ui_success "用户数据库结构、名称和端口未发现冲突。"
  else
    ui_error "用户数据库异常：格式错误 ${malformed_users:-0}，重名 ${duplicate_user_names:-0}，重复端口 ${duplicate_user_ports:-0}。"
    health_errors=$((health_errors + 1))
  fi

  if [ -x "$CLOUDFLARED_BIN" ] || [ -s "$CLOUDFLARED_TOKEN_FILE" ]; then
    if cloudflared_service_is_running; then
      ui_success "cloudflared 正在运行，活跃连接：$(cloudflared_connection_count)。"
    else
      ui_error "检测到 Tunnel 配置，但 cloudflared 未运行。"
      health_errors=$((health_errors + 1))
    fi
    token_mode="$(stat -c '%a' "$CLOUDFLARED_TOKEN_FILE" 2>/dev/null || true)"
    token_owner="$(stat -c '%u' "$CLOUDFLARED_TOKEN_FILE" 2>/dev/null || true)"
    if [ "$token_mode" = "600" ] && [ "$token_owner" = "0" ]; then
      ui_success "Tunnel Token 属于 root，权限为 600。"
    else
      ui_warn "Tunnel Token 权限或所有者不安全（mode=${token_mode:-未知}, uid=${token_owner:-未知}）。"
      health_warnings=$((health_warnings + 1))
    fi
  fi

  for internal_port in 7890 9090 1053; do
    if ! system_port_in_use "$internal_port"; then
      ui_error "Mihomo 内部端口 $internal_port 未监听。"
      health_errors=$((health_errors + 1))
    elif command -v ss >/dev/null 2>&1 && ! port_owned_by_process "$internal_port" "mihomo"; then
      ui_error "内部端口 $internal_port 被非 Mihomo 进程占用。"
      health_errors=$((health_errors + 1))
    fi
  done
  if system_port_in_use 20241 && command -v ss >/dev/null 2>&1 && ! port_owned_by_process 20241 "cloudflared"; then
    ui_error "内部监控端口 20241 被非 cloudflared 进程占用。"
    health_errors=$((health_errors + 1))
  fi

  if [ -d "$STATE_LOCK_DIR" ]; then
    lock_pid="$(cat "$STATE_LOCK_DIR/pid" 2>/dev/null || true)"
    ui_warn "发现配置修改锁（PID ${lock_pid:-未知}）；若没有其他 mh 进程，下次修改时会自动恢复。"
    health_warnings=$((health_warnings + 1))
  fi

  ui_dash
  if [ "$health_errors" -eq 0 ]; then
    ui_success "健康检查完成：0 个错误，$health_warnings 个警告。"
    return 0
  fi
  ui_error "健康检查完成：$health_errors 个错误，$health_warnings 个警告。"
  return 1
}

uninstall_all() {
  need_root
  screen_title "彻底卸载脚本"
  printf ' %s1.%s 卸载 Mihomo 与管理脚本，保留 Argo Tunnel\n' "$C_GREEN" "$C_RESET"
  printf ' %s2.%s 完整卸载 Mihomo、Argo Tunnel，并恢复 sysctl\n' "$C_GREEN" "$C_RESET"
  printf ' %s0.%s 取消\n' "$C_GREEN" "$C_RESET"
  ui_prompt "请输入数字选择 (0-2)："
  read -r uninstall_mode || true
  case "$uninstall_mode" in
    1|2) ;;
    0) ui_warn "已取消卸载。"; return 0 ;;
    *) ui_error "无效选择。"; return 1 ;;
  esac
  ui_warn "此操作会永久删除 Mihomo 节点配置。"
  ui_prompt "再次输入 DELETE 确认："
  read -r confirm || true
  [ "$confirm" = "DELETE" ] || { ui_warn "确认文字不匹配，已取消。"; return 0; }

  manager="$(service_manager)"
  case "$manager" in
    systemd)
      systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
      rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-service "$SERVICE_NAME" stop 2>/dev/null || true
      rc-update del "$SERVICE_NAME" default 2>/dev/null || true
      rm -f "/etc/init.d/${SERVICE_NAME}"
      ;;
  esac

  cleanup_user_traffic_rules
  cleanup_traffic_auto_refresh
  [ "$uninstall_mode" = "2" ] && remove_cloudflared_files
  restore_sysctl_network
  rm -f "$LOGROTATE_FILE"
  rm -f "$BIN_PATH" "$BIN_BACKUP_PATH" "$CLI_PATH" "$CLI_BACKUP_PATH"
  rm -rf "$CONFIG_DIR" "$LOG_DIR"
  if [ "$uninstall_mode" = "2" ]; then
    ui_success "Mihomo、Argo Tunnel 与脚本数据已完整删除，sysctl 已恢复或取消持久化。"
  else
    ui_success "Mihomo 与管理脚本已删除；Argo Tunnel 保持运行。"
  fi
}

prepare_home_dashboard() {
  dashboard_mihomo="$(service_status_text)"
  if [ ! -x "$CLOUDFLARED_BIN" ] && [ ! -s "$CLOUDFLARED_TOKEN_FILE" ]; then
    dashboard_tunnel="未安装"
  else
    dashboard_tunnel="$(cloudflared_status_text)"
  fi
  dashboard_connections="-"
  if cloudflared_service_is_running; then
    dashboard_connections="$(cloudflared_connection_count)"
  fi

  dashboard_nodes="$(awk -F'|' 'NF { count++ } END { print count + 0 }' "$NODES_DB" 2>/dev/null)"
  dashboard_argo="$(awk -F'|' '$1 == "vless-ws" && $7 == "argo" { count++ } END { print count + 0 }' "$NODES_DB" 2>/dev/null)"
  dashboard_users="关闭"
  if multi_user_enabled; then
    dashboard_users="$(awk -F'|' 'NF { count++ } END { print count + 0 }' "$USERS_DB" 2>/dev/null)"
  fi

  dashboard_memory="未知"
  dashboard_memory_current="$(cat /sys/fs/cgroup/memory.current 2>/dev/null || true)"
  dashboard_memory_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
  case "$dashboard_memory_current:$dashboard_memory_max" in
    *[!0-9:]*|:*) ;;
    *)
      if [ "$dashboard_memory_max" -gt 0 ]; then
        dashboard_memory="$(awk -v current="$dashboard_memory_current" -v maximum="$dashboard_memory_max" 'BEGIN { printf "%d/%d MiB（%d%%）", current / 1048576, maximum / 1048576, current * 100 / maximum }')"
      fi
      ;;
  esac

  dashboard_oom_current="$(awk '$1 == "oom_kill" { print $2; exit }' /sys/fs/cgroup/memory.events 2>/dev/null || true)"
  dashboard_oom_previous="$(cat "$OOM_STATE_FILE" 2>/dev/null || true)"
  case "$dashboard_oom_current" in
    ''|*[!0-9]*) dashboard_oom="未知" ;;
    0) dashboard_oom="0" ;;
    *)
      case "$dashboard_oom_previous" in
        ''|*[!0-9]*) dashboard_oom="历史 ${dashboard_oom_current} 次" ;;
        *)
          if [ "$dashboard_oom_current" -gt "$dashboard_oom_previous" ]; then
            dashboard_oom="新增 $((dashboard_oom_current - dashboard_oom_previous)) 次（累计 ${dashboard_oom_current}）"
          else
            dashboard_oom="无新增（累计 ${dashboard_oom_current}）"
          fi
          ;;
      esac
      ;;
  esac
  dashboard_dns="$(configured_dns_servers | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  [ -n "$dashboard_dns" ] || dashboard_dns="未配置"
}

menu() {
  while true; do
    clear 2>/dev/null || true
    prepare_home_dashboard
    multi_user_menu_line=""
    menu_choices="0-11/22/33/44/55/66/88"
    invalid_choices="0-11、22、33、44、55、66 或 88"
    if multi_user_enabled; then
      multi_user_menu_line="   ${C_GREEN}77.${C_RESET} 多用户管理面板"
      menu_choices="0-11/22/33/44/55/66/77/88"
      invalid_choices="0-11、22、33、44、55、66、77 或 88"
    fi
    
    cat <<EOF
${C_CYAN}====================================================${C_RESET}
 [*] ${C_BOLD}Mihomo 一键配置管理面板${C_RESET}
${C_CYAN}====================================================${C_RESET}
  >  ${C_BOLD}原作者${C_RESET}：${C_PURPLE}${SCRIPT_AUTHOR}${C_RESET}
  >  ${C_BOLD}Argo 优化${C_RESET}：${C_PURPLE}${SCRIPT_OPTIMIZER}${C_RESET}
  >  ${C_BOLD}版本${C_RESET}：${C_PURPLE}${SCRIPT_VERSION}${C_RESET}
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[+] 状态概览${C_RESET}
   Mihomo：${dashboard_mihomo}  |  Tunnel：${dashboard_tunnel}  |  边缘连接：${dashboard_connections}
   节点：${dashboard_nodes}（Argo ${dashboard_argo}）  |  多用户：${dashboard_users}
   内存：${dashboard_memory}  |  OOM Kill：${dashboard_oom}
   DNS：${dashboard_dns}
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[+] 节点管理${C_RESET}
   ${C_GREEN}1.${C_RESET} 一键生成代理节点
   ${C_GREEN}2.${C_RESET} 查看所有节点链接
   ${C_GREEN}3.${C_RESET} 编辑 / 删除节点

  ${C_YELLOW}[+] 核心管理${C_RESET}
   ${C_GREEN}4.${C_RESET} 一键安装 Mihomo 内核
   ${C_GREEN}5.${C_RESET} 更新管理脚本
   ${C_GREEN}6.${C_RESET} 彻底卸载脚本
   ${C_GREEN}10.${C_RESET} 版本回滚（内核/cloudflared/脚本）
   
  ${C_YELLOW}[+] 服务运维${C_RESET}
   ${C_GREEN}7.${C_RESET} 查看 YAML 配置文件
   ${C_GREEN}8.${C_RESET} 重启 Mihomo 服务
   ${C_GREEN}9.${C_RESET} 查看服务实时日志
   ${C_GREEN}11.${C_RESET} 一键系统健康检查

  ${C_YELLOW}[+] 其他功能${C_RESET}
   ${C_GREEN}22.${C_RESET} 一键生成 Reality + Hysteria2 + AnyTLS
   ${C_GREEN}33.${C_RESET} 一键重命名所有节点
   ${C_GREEN}44.${C_RESET} 性能优化菜单
   ${C_GREEN}55.${C_RESET} sysctl 网络优化
   ${C_GREEN}66.${C_RESET} IPv6 支持设置
$multi_user_menu_line
   ${C_GREEN}88.${C_RESET} Argo / Cloudflare Tunnel 管理
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}0.${C_RESET} => 退出脚本面板
${C_CYAN}====================================================${C_RESET}
EOF
    printf "${C_BOLD}请输入数字选择 ($menu_choices)：${C_RESET}"
    read -r choice || exit 0

    case "$choice" in
      1) add_node; pause ;;
      2) show_all_nodes; pause ;;
      3) node_management_menu; pause ;;
      4) install_core; pause ;;
      5) update_script; pause ;;
      6) uninstall_all; pause ;;
      7) show_config; pause ;;
      8) need_root; ensure_installed; clear 2>/dev/null || true; ui_title "重启 Mihomo 服务"; if restart_service; then ui_success "服务已重启。"; else ui_error "服务重启失败，请查看日志。"; fi; pause ;;
      9) show_logs ;;
      10) version_rollback_menu; pause ;;
      11) health_check; pause ;;
      22) add_combo_nodes; pause ;;
      33) rename_all_nodes; pause ;;
      44) performance_tuning_menu; pause ;;
      55) optimize_sysctl_network; pause ;;
      66) ipv6_settings_menu; pause ;;
      88) cloudflared_menu ;;
      77)
        if multi_user_enabled; then
          multi_user_panel; pause
        else
          ui_error "多用户管理未启用。"; pause
        fi
        ;;
      0) clear; exit 0 ;;
      *) ui_error "无效选择，请输入 $invalid_choices。"; pause ;;
    esac
  done
}

case "${1:-}" in
  install) install_core ;;
  add) add_node ;;
  combo|batch|22) add_combo_nodes ;;
  rename|rename-all|33) rename_all_nodes ;;
  perf|performance|tune|44) performance_tuning_menu ;;
  apply-runtime|runtime-apply) apply_saved_runtime_service ;;
  sysctl|netopt|55) optimize_sysctl_network ;;
  network-migrate|net-migrate) need_root; migrate_legacy_sysctl_config ;;
  ipv6|ip6|66) ipv6_settings_menu ;;
  argo|tunnel|cloudflared|88) cloudflared_menu ;;
  tunnel-watchdog) run_tunnel_watchdog ;;
  tunnel-watchdog-on) need_root; enable_tunnel_watchdog ;;
  tunnel-watchdog-off) need_root; disable_tunnel_watchdog ;;
  traffic|usage) need_root; ensure_installed; update_user_traffic_from_connections ;;
  traffic-auto) run_traffic_auto_refresh ;;
  traffic-cron|auto-traffic|traffic-auto-menu) need_root; ensure_installed; traffic_auto_refresh_menu ;;
  sub-user|user-sub|user-subscription) need_root; ensure_installed; show_user_subscription ;;
  users|user|multi-user|77) multi_user_panel ;;
  list|nodes) show_all_nodes ;;
  config) show_config ;;
  delete|del|remove) delete_node ;;
  restart) need_root; ensure_installed; restart_service ;;
  dns-migrate|dns-repair) need_root; ensure_installed; dns_preflight_repair && restart_service 1 ;;
  logs|log) show_logs ;;
  update) update_script ;;
  rollback) version_rollback_menu ;;
  check|health|doctor) health_check ;;
  uninstall) uninstall_all ;;
  *) menu ;;
esac
