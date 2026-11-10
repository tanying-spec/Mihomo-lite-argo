#!/bin/sh
# Run with sh tests/runtime_profiles.sh; never touch host services or sysctls.
set -eu
cd "$(dirname "$0")/.."
definitions="$(mktemp)"
fixture_dir="$(mktemp -d)"
trap 'rm -f "$definitions"; rm -rf "$fixture_dir"' EXIT HUP INT TERM
sed '/^case "${1:-}" in/,$d' mh.sh > "$definitions"
. "$definitions"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
memory_limit_mib() { printf '%s\n' "$test_memory"; }
effective_cpu_count() { printf '8\n'; }
cpu_quota_severely_limited() { [ "$test_cpu_limited" = 1 ]; }
os_id=alpine

for test_memory in 64 96 128 183 192 256 384 512 1024 4096; do
  for test_cpu_limited in 0 1; do
    result="$(recommended_runtime)"
    recommended_mem="${result%%|*}"
    rest="${result#*|}"
    recommended_gogc="${rest%%|*}"
    recommended_gomaxprocs="${rest#*|}"
    limit="$(memlimit_mib_value "$recommended_mem")"
    [ "$limit" -lt "$test_memory" ] || fail "budget exceeds $test_memory MiB: $result"
    if [ "$test_memory" -le 192 ]; then
      [ "$recommended_gogc" = 50 ] || fail "small-memory GC overridden: $result"
    elif [ "$test_memory" -le 256 ]; then
      [ "$recommended_gogc" = 75 ] || fail "256 MiB GC overridden: $result"
    elif [ "$test_memory" -le 512 ]; then
      [ "$recommended_gogc" = 125 ] || fail "512 MiB GC overridden: $result"
    fi
    if [ "$test_cpu_limited" = 1 ] || [ "$test_memory" -le 256 ]; then
      [ "$recommended_gomaxprocs" = 1 ] || fail "CPU cap missing: $result"
    fi
    resource_mem="$recommended_mem"
    resource_gogc=200
    throughput_mem="$recommended_mem"
    throughput_gogc=50
    normalize_runtime_profiles
    [ "$resource_gogc" -le "$recommended_gogc" ] || fail "resource profile delays GC"
    [ "$throughput_gogc" -gt "$recommended_gogc" ] || fail "throughput GC ordering"
  done
done

# Saved legacy values must be replaced by the explicit migration, while ordinary
# apply-runtime continues to preserve user-selected settings.
test_memory=183
test_cpu_limited=1
MIHOMO_GOMEMLIMIT=64MiB
MIHOMO_GOGC=175
MIHOMO_GOMAXPROCS=8
MIHOMO_GODEBUG=madvdontneed=1
RUNTIME_ENV_FILE="$definitions.missing"
need_root() { :; }
ensure_installed() { :; }
detect_os() { :; }
write_runtime_tuning() { :; }
apply_runtime_service() { :; }
apply_memory_safe_runtime >/dev/null
[ "$MIHOMO_GOMEMLIMIT" = 64MiB ] || fail "migration memory budget"
[ "$MIHOMO_GOGC" = 50 ] || fail "legacy GC persisted after migration"
[ "$MIHOMO_GOMAXPROCS" = 1 ] || fail "migration CPU cap"

test_memory=183
[ "$(cloudflared_memory_limit)" = 40MiB ] || fail "Tunnel small-memory budget"

[ "$(low_memory_socket_cap)" = 4194304 ] || fail "183 MiB socket cap"
test_memory=128
[ "$(low_memory_socket_cap)" = 2097152 ] || fail "128 MiB socket cap"
test_memory=512
[ "$(low_memory_socket_cap)" = 8388608 ] || fail "512 MiB socket cap"
test_memory=1024
[ "$(low_memory_socket_cap)" = 0 ] || fail "large VPS unexpectedly capped"
[ "$(cap_socket_memory_value '4096 87380 33554432' 4194304)" = '4096 87380 4194304' ] || fail "TCP vector clamp"
[ "$(cap_socket_memory_value '4096 8388608 33554432' 4194304)" = '4096 4194304 4194304' ] || fail "TCP default clamp"
[ "$(cap_socket_memory_value '4096 65536 1048576' 4194304)" = '4096 65536 1048576' ] || fail "smaller budget raised"
[ "$(cap_socket_memory_value '33554432' 4194304)" = 4194304 ] || fail "socket scalar clamp"
if cap_socket_memory_value 'max' 4194304 >/dev/null; then fail 'invalid socket value accepted'; fi
if cap_socket_memory_value '4096 2048 65536' 4194304 >/dev/null; then fail 'unordered TCP vector accepted'; fi

# Exercise persistence and migration with fake sysctls; host kernel untouched.
SYSCTL_CONF_FILE="$fixture_dir/sysctl.conf"
SYSCTL_BACKUP_FILE="$fixture_dir/sysctl.previous"
sysctl() {
  [ "$1" = -n ] || return 1
  if [ "$2" = net.ipv4.tcp_congestion_control ]; then printf 'bbr\n'; return 0; fi
  cat "$fixture_dir/$2"
}
apply_sysctl_value() {
  printf '%s\n' "$2" > "$fixture_dir/$1"
  printf '%s = %s\n' "$1" "$2" >> "$3"
}
for key in net.ipv4.tcp_rmem net.ipv4.tcp_wmem; do
  printf '4096 65536 33554432\n' > "$fixture_dir/$key"
  printf '%s = 4096 65536 67108864\n' "$key" >> "$SYSCTL_CONF_FILE"
done
for key in net.core.rmem_max net.core.wmem_max; do
  printf '33554432\n' > "$fixture_dir/$key"
done
test_memory=183
apply_low_memory_network_budget >/dev/null
! grep -Eq '33554432|67108864' "$SYSCTL_CONF_FILE" || fail 'obsolete persistent limits remained'
[ "$(grep -c '^net.ipv4.tcp_rmem ' "$SYSCTL_CONF_FILE")" = 1 ] || fail 'duplicate socket key'
apply_low_memory_network_budget >/dev/null
[ "$(grep -c '^net.ipv4.tcp_rmem ' "$SYSCTL_CONF_FILE")" = 1 ] || fail 'budget not idempotent'
printf 'net.core.netdev_max_backlog = 250000\n' >> "$SYSCTL_CONF_FILE"
migrate_legacy_sysctl_config >/dev/null
! grep -q 250000 "$SYSCTL_CONF_FILE" || fail 'legacy queue remained'
grep -q '^net.ipv4.tcp_rmem = 4096 65536 4194304$' "$SYSCTL_CONF_FILE" || fail 'migration lost socket persistence'
test_memory=1024
before="$(cksum "$SYSCTL_CONF_FILE")"
apply_low_memory_network_budget >/dev/null
[ "$before" = "$(cksum "$SYSCTL_CONF_FILE")" ] || fail 'large VPS settings changed'
printf 'PASS: 20 memory/CPU combinations, profiles, legacy runtime, socket persistence and migration\n'
