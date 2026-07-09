#!/bin/sh

set -u

SCRIPT_AUTHOR="oKafuChino"
SCRIPT_VERSION="1.9.9"
BIN_PATH="/usr/local/bin/mihomo"
CLI_PATH="/usr/local/bin/mh"
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
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
LOG_DIR="/var/log/mihomo"
SERVICE_NAME="mihomo"
RUNTIME_ENV_FILE="$CONFIG_DIR/runtime.env"
NETWORK_ENV_FILE="$CONFIG_DIR/network.env"
FEATURES_ENV_FILE="$CONFIG_DIR/features.env"
MULTI_USER_FLAG="$CONFIG_DIR/multi-user.enabled"
PUBLIC_IP_CACHE_FILE="$CONFIG_DIR/public.ip"
SYSCTL_CONF_FILE="/etc/sysctl.d/99-mihomo-lite.conf"
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
SCRIPT_RAW_URL="${MH_SCRIPT_RAW_URL:-https://raw.githubusercontent.com/oKafuChino/Mihomo-lite/main/mh.sh}"

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
    red "请使用 root 权限运行：sudo mh"
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

memory_limit_bytes() {
  best_memory_limit=""
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

recommended_runtime() {
  cpu_count="$(effective_cpu_count)"
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
      printf '%s|%s|%s' "$recommended_mem" "$recommended_gogc" "$cpu_count"
      return 0
      ;;
  esac

  case "${os_id:-}" in
    alpine) printf '192MiB|125|%s' "$cpu_count" ;;
    debian|ubuntu) printf '384MiB|200|%s' "$cpu_count" ;;
    *) printf '256MiB|150|%s' "$cpu_count" ;;
  esac
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
    /^[0-9]+[Gg]$/ { sub(/[Gg]$/, ""); print $1 * 1024 * 1024 * 1024; exit 0 }
    /^[0-9]+[Mm]$/ { sub(/[Mm]$/, ""); print $1 * 1024 * 1024; exit 0 }
    /^[0-9]+[Kk]$/ { sub(/[Kk]$/, ""); print $1 * 1024; exit 0 }
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
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$user_name" "$user_node" "$user_proto" "$user_credential" "$user_expire" "$user_quota" "${user_used:-0}" "${user_enabled:-1}" "$user_created" "$user_note" "$user_port"
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
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
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
  if [ -r "$PUBLIC_IP_CACHE_FILE" ]; then
    cache_ip="$(awk -F= -v family="$cache_family" '$1 == family { value = $2 } END { print value }' "$PUBLIC_IP_CACHE_FILE" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$cache_ip" ]; then
      case "$cache_family" in
        ipv6) is_ipv6 "$cache_ip" || return 1 ;;
        *) is_ipv4 "$cache_ip" || return 1 ;;
      esac
      printf '%s' "$cache_ip"
      return 0
    fi

    cache_ip="$(sed -n '1p' "$PUBLIC_IP_CACHE_FILE" 2>/dev/null | tr -d '[:space:]')"
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
  if [ -r "$PUBLIC_IP_CACHE_FILE" ]; then
    awk -F= -v family="$cache_family" '$1 != family && $1 ~ /^ipv[46]$/ { print }' "$PUBLIC_IP_CACHE_FILE" > "$tmp_file" 2>/dev/null || : > "$tmp_file"
  else
    : > "$tmp_file"
  fi
  printf '%s=%s\n' "$cache_family" "$cache_ip" >> "$tmp_file"
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
      cat <<EOF
  - name: "$render_user_name_yaml"
    type: vless
    port: $render_user_port
    listen: "$render_listen_address_yaml"
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
    - 1.1.1.1
    - 8.8.8.8
EOF

  if [ "$cfg_ipv6" = "true" ]; then
    cat >> "$tmp_file" <<'EOF'
    - 2606:4700:4700::1111
    - 2001:4860:4860::8888
EOF
  fi

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
          cat >> "$tmp_file" <<EOF
  - name: "$cfg_node_name_yaml"
    type: vless
    port: $cfg_node_port
    listen: "$cfg_listen_address_yaml"
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

  mv "$tmp_file" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
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
  systemctl restart "$SERVICE_NAME"
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
  rc-service "$SERVICE_NAME" restart
}

restart_service() {
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      systemctl daemon-reload
      systemctl restart "$SERVICE_NAME"
      ;;
    openrc)
      rc-service "$SERVICE_NAME" restart
      ;;
    *)
      red "未找到 systemd 或 OpenRC，无法管理 mihomo 服务。"
      exit 1
      ;;
  esac
}

install_core() {
  need_root
  screen_title "一键安装 Mihomo 内核"
  detect_os
  prompt_runtime_tuning
  prompt_multi_user_feature
  ui_section "安装系统依赖"
  install_packages curl gzip openssl
  mkdir -p "$CONFIG_DIR" "$LOG_DIR"

  download_url="$(latest_download_url)"
  tmp_file="$(make_temp /tmp/mihomo.XXXXXX)"
  bin_tmp="$(make_temp /tmp/mihomo-bin.XXXXXX)"

  ui_warn "下载地址：$download_url"
  ui_section "下载并安装 Mihomo 内核"
  curl -fL "$download_url" -o "$tmp_file" || {
    rm -f "$tmp_file" "$bin_tmp"
    exit 1
  }
  gzip -dc "$tmp_file" > "$bin_tmp" || {
    rm -f "$tmp_file" "$bin_tmp"
    exit 1
  }
  chmod +x "$bin_tmp"
  mv "$bin_tmp" "$BIN_PATH"
  rm -f "$tmp_file"
  chmod +x "$BIN_PATH"

  [ -f "$NODES_DB" ] || : > "$NODES_DB"
  chmod 600 "$NODES_DB"
  if multi_user_enabled; then
    [ -f "$USERS_DB" ] || : > "$USERS_DB"
    chmod 600 "$USERS_DB"
  fi
  render_config

  manager="$(service_manager)"
  case "$manager" in
    systemd) write_systemd_service ;;
    openrc) write_openrc_service ;;
    *)
      ui_error "未找到 systemd 或 OpenRC，mihomo 已安装但服务未创建。"
      exit 1
      ;;
  esac

  ui_success "mihomo 内核安装完成，服务已启动。"
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

  [ -s "$USERS_DB" ] || return 1
  awk -F'|' -v p="$port" '
    NF >= 11 && $11 == p { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$USERS_DB" 2>/dev/null
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
  default_name="$proto_prefix"
  ui_prompt "请输入节点名称（默认 $default_name）："
  read -r node_name || true
  if [ -z "$node_name" ]; then
    node_name="$default_name"
  fi
  node_name="$(printf '%s' "$node_name" | tr -cd 'A-Za-z0-9_.-')"
  if [ -z "$node_name" ]; then
    red "节点名称无效，只能包含字母、数字、下划线、点和短横线。"
    exit 1
  fi

  if node_name_exists "$node_name"; then
    red "节点 $node_name 已存在。"
    exit 1
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
      exit 1
      ;;
  esac
  if [ "$node_port" -lt 1 ] || [ "$node_port" -gt 65535 ]; then
    red "端口范围必须为 1-65535。"
    exit 1
  fi

  if port_in_use "$node_port"; then
    red "端口 $node_port 已被脚本内的其他节点使用。"
    exit 1
  fi
  SELECTED_NODE_PORT="$node_port"
}

append_node() {
  printf '%s\n' "$1" >> "$NODES_DB"
  chmod 600 "$NODES_DB"
  render_config
  restart_service
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
      ws_host="${value3:-$server_host}"
      ws_host_query="$(url_query "$ws_host")"
      printf 'vless://%s@%s:%s?encryption=none&security=none&type=ws&host=%s&path=%s#%s\n' \
        "$node_uuid" "$server_host" "$node_port" "$ws_host_query" "$ws_path" "$link_name"
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
  cat <<EOF

${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[!]${C_RESET} 请确认 VPS 防火墙和云厂商安全组已放行 TCP/UDP ${C_BOLD}$node_port${C_RESET}

 ${C_GREEN}[+] 节点链接${C_RESET}
$node_link
${C_CYAN}----------------------------------------------------${C_RESET}
EOF
}

add_vless_reality_node() {
  screen_title "创建 VLESS + Reality 节点"
  prompt_node_name vless-reality
  node_name="$SELECTED_NODE_NAME"
  prompt_port
  node_port="$SELECTED_NODE_PORT"
  ui_prompt "请输入 Reality SNI（默认 www.amd.com）："
  read -r sni || true
  [ -n "$sni" ] || sni="www.amd.com"
  sni="$(sanitize_sni_field "$sni")"
  [ -n "$sni" ] || sni="www.amd.com"
  dest="${sni}:443"
  node_uuid="$(new_uuid)"
  key_pair="$(create_reality_keypair)" || exit 1
  private_key="${key_pair%%|*}"
  public_key="${key_pair#*|}"
  short_id="$(rand_hex 8)"
  append_node "vless-reality|$node_name|$node_port|$node_uuid|$sni|$dest|$private_key|$public_key|$short_id"
  ui_success "VLESS + Reality 节点已生成并重启服务。"
  print_node_link vless-reality "$node_name" "$node_port" "$node_uuid" "$sni" "$dest" "$private_key" "$public_key" "$short_id"
}

add_hysteria2_node() {
  screen_title "创建 Hysteria2 节点"
  prompt_node_name hy2
  node_name="$SELECTED_NODE_NAME"
  prompt_port
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
  cert_pair="$(ensure_tls_cert "$node_name" "$sni")" || exit 1
  cert_file="${cert_pair%%|*}"
  key_file="${cert_pair#*|}"
  append_node "hysteria2|$node_name|$node_port|$node_password|$sni|$cert_file|$key_file|$salamander_password|"
  ui_success "Hysteria2 节点已生成并重启服务。"
  print_node_link hysteria2 "$node_name" "$node_port" "$node_password" "$sni" "$cert_file" "$key_file" "$salamander_password" ""
}

add_anytls_node() {
  screen_title "创建 AnyTLS 节点"
  prompt_node_name anytls
  node_name="$SELECTED_NODE_NAME"
  prompt_port
  node_port="$SELECTED_NODE_PORT"
  ui_prompt "请输入 TLS SNI / 证书域名（默认 www.amd.com）："
  read -r sni || true
  [ -n "$sni" ] || sni="www.amd.com"
  sni="$(sanitize_sni_field "$sni")"
  [ -n "$sni" ] || sni="www.amd.com"
  node_password="$(rand_alnum 32)"
  cert_pair="$(ensure_tls_cert "$node_name" "$sni")" || exit 1
  cert_file="${cert_pair%%|*}"
  key_file="${cert_pair#*|}"
  append_node "anytls|$node_name|$node_port|$node_password|$sni|$cert_file|$key_file||"
  ui_success "AnyTLS 节点已生成并重启服务。"
  print_node_link anytls "$node_name" "$node_port" "$node_password" "$sni" "$cert_file" "$key_file" "" ""
}

add_vless_ws_node() {
  screen_title "创建 VLESS + WebSocket 节点"
  prompt_node_name vless-ws
  node_name="$SELECTED_NODE_NAME"
  prompt_port
  node_port="$SELECTED_NODE_PORT"
  server_ip="$(public_ip)"
  ui_prompt "请输入 WebSocket 域名/Host（你托管在Cloudflare的域名）："
  read -r ws_host || true
  [ -n "$ws_host" ] || ws_host="$server_ip"
  ws_host="$(sanitize_db_field "$ws_host")"
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
  append_node "vless-ws|$node_name|$node_port|$node_uuid|$ws_path|$ws_host|||"
  ui_success "VLESS + WS 节点已生成并重启服务。"
  print_node_link vless-ws "$node_name" "$node_port" "$node_uuid" "$ws_path" "$ws_host" "" "" ""
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
  reality_key_pair="$(create_reality_keypair)" || exit 1
  reality_private_key="${reality_key_pair%%|*}"
  reality_public_key="${reality_key_pair#*|}"
  reality_short_id="$(rand_hex 8)"
  reality_dest="${sni}:443"

  hy2_name="$(unique_node_name hy2)"
  hy2_port="$(unique_port)"
  hy2_password="$(rand_alnum 32)"
  hy2_cert_pair="$(ensure_tls_cert "$hy2_name" "$sni")" || exit 1
  hy2_cert_file="${hy2_cert_pair%%|*}"
  hy2_key_file="${hy2_cert_pair#*|}"

  anytls_name="$(unique_node_name anytls)"
  anytls_port="$(unique_port)"
  anytls_password="$(rand_alnum 32)"
  anytls_cert_pair="$(ensure_tls_cert "$anytls_name" "$sni")" || exit 1
  anytls_cert_file="${anytls_cert_pair%%|*}"
  anytls_key_file="${anytls_cert_pair#*|}"

  append_node_record "vless-reality|$reality_name|$reality_port|$reality_uuid|$sni|$reality_dest|$reality_private_key|$reality_public_key|$reality_short_id"
  append_node_record "hysteria2|$hy2_name|$hy2_port|$hy2_password|$sni|$hy2_cert_file|$hy2_key_file||"
  append_node_record "anytls|$anytls_name|$anytls_port|$anytls_password|$sni|$anytls_cert_file|$anytls_key_file||"
  render_config
  restart_service

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
    exit 1
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
      exit 1
    fi
  fi

  ui_prompt "请输入服务商名称："
  read -r provider || true
  provider="$(sanitize_label "$provider")"
  if [ -z "$provider" ]; then
    ui_error "服务商名称不能为空。"
    exit 1
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
  render_config
  restart_service
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
    *) red "无效选择。"; exit 1 ;;
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
      exit 1
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
    : > "$NODES_DB"
    chmod 600 "$NODES_DB"
    render_config
    restart_service
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
    exit 1
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
  render_config
  restart_service
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
  printf '%s|%s|%s|%s|%s|%s|0|1|%s||%s\n' \
    "$user_name" "$user_node_name" "$user_proto" "$user_credential" "$user_expire" "$user_quota" "$user_created" "$user_port" >> "$USERS_DB"
  chmod 600 "$USERS_DB"
  render_config
  restart_service
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

  tmp_file="$(make_temp "$CONFIG_DIR/users.XXXXXX")"
  awk -F'|' -v n="$user_choice" 'NF >= 9 { i++; if (i == n) next } { print }' "$USERS_DB" > "$tmp_file"
  mv "$tmp_file" "$USERS_DB"
  chmod 600 "$USERS_DB"
  render_config
  restart_service
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
  render_config
  restart_service
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
  render_config
  restart_service
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "用户 $user_name 的到期/配额已更新。"
}

refresh_multi_user_status() {
  ensure_multi_user_enabled
  screen_title "刷新用户状态"
  render_config
  restart_service
  refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
  ui_success "已重新渲染配置。过期、禁用或超额用户不会写入独立 listener。"
}

update_user_traffic_from_iptables() {
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
    quota_crossed_count="$(quota_exceeded_user_count)"
    if [ "$traffic_enforce" = "1" ] && [ "${quota_crossed_count:-0}" != "0" ]; then
      render_config
      restart_service
      refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
      [ "$traffic_quiet" = "1" ] || ui_success "检测到 $quota_crossed_count 个用户已达到流量配额，已重载服务并移除对应 listener。"
      return 0
    fi
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
    render_config
    restart_service
    refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
    [ "$traffic_quiet" = "1" ] || ui_success "检测到 $quota_crossed_count 个用户达到流量配额，已重载服务并移除对应 listener。"
  else
    [ "$traffic_quiet" = "1" ] || ui_success "未触发新的配额限制，本次未重启 Mihomo。"
  fi
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
  if ! mkdir "$TRAFFIC_LOCK_DIR" 2>/dev/null; then
    if [ -f "$TRAFFIC_LOCK_DIR/pid" ]; then
      lock_pid="$(cat "$TRAFFIC_LOCK_DIR/pid" 2>/dev/null || printf '')"
      case "$lock_pid" in
        ''|*[!0-9]*) ;;
        *)
          kill -0 "$lock_pid" 2>/dev/null && exit 0
          ;;
      esac
    fi
    rm -f "$TRAFFIC_LOCK_DIR/pid"
    rmdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || exit 0
    mkdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || exit 0
  fi
  printf '%s\n' "$$" > "$TRAFFIC_LOCK_DIR/pid"
  trap 'rm -f "$TRAFFIC_LOCK_DIR/pid"; rmdir "$TRAFFIC_LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
  update_user_traffic_from_connections 1 0
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
  render_config
  restart_service
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
  render_config
  restart_service
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
      render_config
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
      exit 1
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
      exit 1
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
  bandwidth_mode=0
  cpu_mode=0

  stable_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
  bandwidth_gomaxprocs="$recommended_gomaxprocs"
  cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
  case "$detected_memory_mib" in
    ''|*[!0-9]*)
      case "${os_id:-}" in
        alpine)
          stable_mem="128MiB"
          stable_gogc="75"
          high_mem="256MiB"
          high_gogc="150"
          bandwidth_mem="192MiB"
          bandwidth_gogc="150"
          bandwidth_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
          cpu_mem="192MiB"
          cpu_gogc="150"
          cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
          ;;
        *)
          stable_mem="192MiB"
          stable_gogc="100"
          high_mem="512MiB"
          high_gogc="200"
          bandwidth_mem="384MiB"
          bandwidth_gogc="175"
          bandwidth_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
          cpu_mem="384MiB"
          cpu_gogc="175"
          ;;
      esac
      ;;
    *)
      stable_mem="$(memlimit_from_percent "$detected_memory_mib" 50 64 64 384)"
      high_mem="$(memlimit_from_percent "$detected_memory_mib" 70 128 64 1024)"
      bandwidth_mem="$(memlimit_from_percent "$detected_memory_mib" 60 96 96 768)"
      cpu_mem="$(memlimit_from_percent "$detected_memory_mib" 60 96 96 768)"
      if [ "$detected_memory_mib" -le 256 ]; then
        bandwidth_mem="$(memlimit_from_percent "$detected_memory_mib" 60 64 64 512)"
        cpu_mem="$bandwidth_mem"
        stable_gogc="75"
        high_gogc="125"
        bandwidth_gogc="125"
        cpu_gogc="125"
        bandwidth_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
        cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
      elif [ "$detected_memory_mib" -le 512 ]; then
        stable_gogc="100"
        high_gogc="150"
        bandwidth_gogc="150"
        cpu_gogc="150"
        bandwidth_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
        cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 1)"
      elif [ "$detected_memory_mib" -le 1024 ]; then
        stable_gogc="125"
        high_gogc="175"
        bandwidth_gogc="175"
        cpu_gogc="175"
        cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
      else
        stable_gogc="125"
        high_gogc="200"
        bandwidth_gogc="200"
        cpu_gogc="200"
        cpu_gomaxprocs="$(cap_cpu_count "$recommended_gomaxprocs" 2)"
      fi
      ;;
  esac

  screen_title "性能优化菜单"
  cat <<EOF
 当前参数：GOMEMLIMIT=$current_mem  GOGC=$current_gogc  GOMAXPROCS=$current_gomaxprocs
 当前 GODEBUG：$current_godebug
 检测内存：$detected_memory_text
 系统推荐：GOMEMLIMIT=$recommended_mem  GOGC=$recommended_gogc  GOMAXPROCS=$recommended_gomaxprocs
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}1.${C_RESET} 低内存稳连模式      GOMEMLIMIT=$stable_mem  GOGC=$stable_gogc   GOMAXPROCS=$stable_gomaxprocs
 ${C_GREEN}2.${C_RESET} 系统推荐模式        GOMEMLIMIT=$recommended_mem  GOGC=$recommended_gogc  GOMAXPROCS=$recommended_gomaxprocs
 ${C_GREEN}3.${C_RESET} 高吞吐模式          GOMEMLIMIT=$high_mem  GOGC=$high_gogc  GOMAXPROCS=$recommended_gomaxprocs
 ${C_GREEN}4.${C_RESET} Alpine/LXC 稳速跑满带宽  GOMEMLIMIT=$bandwidth_mem  GOGC=$bandwidth_gogc  GOMAXPROCS=$bandwidth_gomaxprocs
 ${C_GREEN}5.${C_RESET} 低 CPU 模式         GOMEMLIMIT=$cpu_mem  GOGC=$cpu_gogc  GOMAXPROCS=$cpu_gomaxprocs
 ${C_GREEN}6.${C_RESET} 自定义参数
 ${C_GREEN}0.${C_RESET} => 返回主菜单
${C_CYAN}====================================================${C_RESET}
EOF
  ui_prompt "请输入数字选择 (0-6)："
  read -r perf_choice || true

  case "$perf_choice" in
    1)
      MIHOMO_GOMEMLIMIT="$stable_mem"
      MIHOMO_GOGC="$stable_gogc"
      MIHOMO_GOMAXPROCS="$stable_gomaxprocs"
      ;;
    2)
      MIHOMO_GOMEMLIMIT="$recommended_mem"
      MIHOMO_GOGC="$recommended_gogc"
      MIHOMO_GOMAXPROCS="$recommended_gomaxprocs"
      ;;
    3)
      MIHOMO_GOMEMLIMIT="$high_mem"
      MIHOMO_GOGC="$high_gogc"
      MIHOMO_GOMAXPROCS="$recommended_gomaxprocs"
      ;;
    4)
      ui_warn "跑满带宽模式会关闭自动流量统计，并移除 iptables 统计规则以降低包路径开销。"
      ui_warn "流量配额不会实时累计；再次执行 mh traffic 会重建统计规则。"
      ui_prompt "确认应用跑满带宽模式？输入 y 确认："
      read -r bandwidth_confirm || true
      case "$bandwidth_confirm" in
        y|Y|yes|YES) ;;
        *)
          ui_warn "已取消跑满带宽模式。"
          return 0
          ;;
      esac
      MIHOMO_GOMEMLIMIT="$bandwidth_mem"
      MIHOMO_GOGC="$bandwidth_gogc"
      MIHOMO_GOMAXPROCS="$bandwidth_gomaxprocs"
      bandwidth_mode=1
      ;;
    5)
      ui_warn "低 CPU 模式会提高 GOGC、限制 Go 调度线程，并重建轻量流量统计规则。"
      ui_warn "如果需要极限压测带宽，优先使用 4 号模式关闭统计链。"
      ui_prompt "确认应用低 CPU 模式？输入 y 确认："
      read -r cpu_confirm || true
      case "$cpu_confirm" in
        y|Y|yes|YES) ;;
        *)
          ui_warn "已取消低 CPU 模式。"
          return 0
          ;;
      esac
      MIHOMO_GOMEMLIMIT="$cpu_mem"
      MIHOMO_GOGC="$cpu_gogc"
      MIHOMO_GOMAXPROCS="$cpu_gomaxprocs"
      cpu_mode=1
      ;;
    6)
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
  if [ "$bandwidth_mode" = "1" ]; then
    disable_traffic_auto_refresh >/dev/null 2>&1 || true
    cleanup_user_traffic_rules >/dev/null 2>&1 || true
    ui_success "已关闭自动流量统计并清理 iptables 统计规则。"
  fi
  if [ "$cpu_mode" = "1" ]; then
    if multi_user_enabled; then
      refresh_user_traffic_rules_if_available >/dev/null 2>&1 || true
      ui_success "已按协议重建轻量流量统计规则。"
    else
      ui_success "多用户管理未启用，无需重建流量统计规则。"
    fi
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

optimize_sysctl_network() {
  need_root
  screen_title "sysctl 网络优化"
  ui_warn "该功能会尝试优化 BBR、队列、TCP/UDP 缓冲和端口范围。"
  ui_warn "LXC 容器可能无法写入部分内核参数，脚本会逐项跳过无权限项目。"
  ui_prompt "确认应用网络优化？输入 y 确认："
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
  printf '# Generated by Mihomo Lite\n' > "$tmp_file"
  applied=0

  if apply_sysctl_value "net.core.default_qdisc" "fq" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_congestion_control" "bbr" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.rmem_max" "67108864" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.wmem_max" "67108864" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.rmem_default" "262144" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.wmem_default" "262144" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.optmem_max" "65536" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.somaxconn" "65535" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.core.netdev_max_backlog" "250000" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_max_syn_backlog" "65535" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_rmem" "4096 87380 67108864" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_wmem" "4096 65536 67108864" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_window_scaling" "1" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_fastopen" "3" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_mtu_probing" "1" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_slow_start_after_idle" "0" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_tw_reuse" "1" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_fin_timeout" "15" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.tcp_keepalive_time" "600" "$tmp_file"; then applied=$((applied + 1)); fi
  if apply_sysctl_value "net.ipv4.ip_local_port_range" "1024 65535" "$tmp_file"; then applied=$((applied + 1)); fi

  if [ "$applied" -eq 0 ]; then
    rm -f "$tmp_file"
    ui_warn "没有成功应用任何 sysctl 参数，当前环境可能限制较多。"
    return 1
  fi

  mkdir -p /etc/sysctl.d
  if mv "$tmp_file" "$SYSCTL_CONF_FILE"; then
    chmod 644 "$SYSCTL_CONF_FILE"
    ui_success "已应用 $applied 项网络参数，并保存到 $SYSCTL_CONF_FILE。"
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
      render_config
      restart_service
      ui_success "已关闭 IPv6，监听地址恢复为 0.0.0.0。"
      ;;
    2)
      MIHOMO_IPV6="true"
      MIHOMO_PREFER_IPV6="false"
      write_network_settings
      render_config
      restart_service
      ui_success "已开启 IPv6 监听，分享链接继续优先使用 IPv4。"
      ;;
    3)
      MIHOMO_IPV6="true"
      MIHOMO_PREFER_IPV6="true"
      write_network_settings
      render_config
      restart_service
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
        render_config
        restart_service
        ui_success "已保存 IPv6 分享地址：$manual_ip。"
      elif is_ipv4 "$manual_ip"; then
        MIHOMO_PREFER_IPV6="false"
        write_network_settings
        cache_public_ip ipv4 "$manual_ip"
        render_config
        restart_service
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
    exit 1
  }

  if ! grep -q 'mihomo 一键配置管理面板' "$tmp_file"; then
    rm -f "$tmp_file"
    ui_error "更新失败：下载内容不像 mh 脚本，已取消替换。"
    exit 1
  fi

  if ! sh -n "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    ui_error "更新失败：下载脚本语法检查未通过，已取消替换。"
    exit 1
  fi

  chmod +x "$tmp_file"
  mv "$tmp_file" "$CLI_PATH"
  ui_success "脚本更新完成。重新输入 mh 可打开新版管理面板。"
  if [ -x "$BIN_PATH" ] && [ -f "$CONFIG_FILE" ]; then
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

uninstall_all() {
  need_root
  screen_title "彻底卸载脚本"
  ui_warn "将停止服务，并删除 mihomo 内核、配置目录、日志目录和 mh 命令。"
  ui_prompt "确认卸载 mihomo、删除配置和 mh 命令？输入 y 确认："
  read -r confirm || true
  case "$confirm" in
    y|Y|yes|YES) ;;
    *)
      ui_warn "已取消卸载。"
      return 0
      ;;
  esac

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
  rm -f "$BIN_PATH" "$CLI_PATH"
  rm -rf "$CONFIG_DIR" "$LOG_DIR"
  ui_success "卸载完成。"
}

menu() {
  while true; do
    clear 2>/dev/null || true
    current_status="$(service_status_text)"
    multi_user_menu_line=""
    menu_choices="0-9/22/33/44/55/66"
    invalid_choices="0-9、22、33、44、55 或 66"
    if multi_user_enabled; then
      multi_user_menu_line="   ${C_GREEN}77.${C_RESET} 多用户管理面板"
      menu_choices="0-9/22/33/44/55/66/77"
      invalid_choices="0-9、22、33、44、55、66 或 77"
    fi
    
    cat <<EOF
${C_CYAN}====================================================${C_RESET}
 [*] ${C_BOLD}Mihomo 一键配置管理面板${C_RESET}
${C_CYAN}====================================================${C_RESET}
  >  ${C_BOLD}作者${C_RESET}：${C_PURPLE}${SCRIPT_AUTHOR}${C_RESET}
  >  ${C_BOLD}版本${C_RESET}：${C_PURPLE}${SCRIPT_VERSION}${C_RESET}
  >  ${C_BOLD}状态${C_RESET}：${current_status}
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_YELLOW}[+] 节点管理${C_RESET}
   ${C_GREEN}1.${C_RESET} 一键生成代理节点
   ${C_GREEN}2.${C_RESET} 查看所有节点链接
   ${C_GREEN}3.${C_RESET} 删除特定节点

  ${C_YELLOW}[+] 核心管理${C_RESET}
   ${C_GREEN}4.${C_RESET} 一键安装 Mihomo 内核
   ${C_GREEN}5.${C_RESET} 更新管理脚本
   ${C_GREEN}6.${C_RESET} 彻底卸载脚本
   
  ${C_YELLOW}[+] 服务运维${C_RESET}
   ${C_GREEN}7.${C_RESET} 查看 YAML 配置文件
   ${C_GREEN}8.${C_RESET} 重启 Mihomo 服务
   ${C_GREEN}9.${C_RESET} 查看服务实时日志

  ${C_YELLOW}[+] 其他功能${C_RESET}
   ${C_GREEN}22.${C_RESET} 一键生成 Reality + Hysteria2 + AnyTLS
   ${C_GREEN}33.${C_RESET} 一键重命名所有节点
   ${C_GREEN}44.${C_RESET} 性能优化菜单
   ${C_GREEN}55.${C_RESET} sysctl 网络优化
   ${C_GREEN}66.${C_RESET} IPv6 支持设置
$multi_user_menu_line
${C_CYAN}----------------------------------------------------${C_RESET}
 ${C_GREEN}0.${C_RESET} => 退出脚本面板
${C_CYAN}====================================================${C_RESET}
EOF
    printf "${C_BOLD}请输入数字选择 ($menu_choices)：${C_RESET}"
    read -r choice || exit 0

    case "$choice" in
      1) add_node; pause ;;
      2) show_all_nodes; pause ;;
      3) delete_node; pause ;;
      4) install_core; pause ;;
      5) update_script; pause ;;
      6) uninstall_all; pause ;;
      7) show_config; pause ;;
      8) need_root; ensure_installed; clear 2>/dev/null || true; ui_title "重启 Mihomo 服务"; restart_service; ui_success "服务已重启。"; pause ;;
      9) show_logs ;;
      22) add_combo_nodes; pause ;;
      33) rename_all_nodes; pause ;;
      44) performance_tuning_menu; pause ;;
      55) optimize_sysctl_network; pause ;;
      66) ipv6_settings_menu; pause ;;
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
  ipv6|ip6|66) ipv6_settings_menu ;;
  traffic|usage) need_root; ensure_installed; update_user_traffic_from_connections ;;
  traffic-auto) run_traffic_auto_refresh ;;
  traffic-cron|auto-traffic|traffic-auto-menu) need_root; ensure_installed; traffic_auto_refresh_menu ;;
  sub-user|user-sub|user-subscription) need_root; ensure_installed; show_user_subscription ;;
  users|user|multi-user|77) multi_user_panel ;;
  list|nodes) show_all_nodes ;;
  config) show_config ;;
  delete|del|remove) delete_node ;;
  restart) need_root; ensure_installed; restart_service ;;
  logs|log) show_logs ;;
  update) update_script ;;
  uninstall) uninstall_all ;;
  *) menu ;;
esac
