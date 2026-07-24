#!/bin/sh

set -u

DEFAULT_RAW_BASE="https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/main"
RAW_BASE="${MH_RAW_BASE:-$DEFAULT_RAW_BASE}"
COMMIT_API="${MH_COMMIT_API:-https://api.github.com/repos/tanying-spec/Mihomo-lite-argo/commits/main}"
LOCAL_SCRIPT="${MH_LOCAL_SCRIPT:-}"
CLI_PATH="/usr/local/bin/mh"
CLI_BACKUP_PATH="/usr/local/bin/mh.previous"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

need_root() {
  if [ "$(id -u)" != "0" ]; then
    red "安装需要 root 权限。"
    if command -v sudo >/dev/null 2>&1; then
      red "请重新执行：curl -fsSL <install.sh> | sudo sh"
    else
      red "当前系统没有 sudo。请先执行 su - 切换到 root，再运行：curl -fsSL <install.sh> | sh"
    fi
    exit 1
  fi
}

install_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi

  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl
  else
    red "未找到 apk 或 apt-get，无法自动安装 curl。"
    exit 1
  fi
}

make_temp() {
  mktemp "$1" 2>/dev/null || {
    red "无法创建临时文件：$1"
    exit 1
  }
}

need_root
install_curl

tmp_file="$(make_temp /tmp/mh-install.XXXXXX)"
if [ -n "$LOCAL_SCRIPT" ]; then
  if [ ! -f "$LOCAL_SCRIPT" ]; then
    rm -f "$tmp_file"
    red "MH_LOCAL_SCRIPT 指定的文件不存在：$LOCAL_SCRIPT"
    exit 1
  fi
  cp "$LOCAL_SCRIPT" "$tmp_file"
else
  script_url="$RAW_BASE/mh.sh"
  checksum_url="$RAW_BASE/mh.sh.sha256"
  case "$RAW_BASE" in
    http://*|https://*)
      install_nonce="$(date +%s 2>/dev/null || printf 0)"
      script_url="${script_url}?mh=${install_nonce}"
      checksum_url="${checksum_url}?mh=${install_nonce}"
      ;;
  esac
  if [ "$RAW_BASE" = "$DEFAULT_RAW_BASE" ]; then
    commit_json="$(curl -fsSL --max-time 15 "${COMMIT_API}?mh=${install_nonce:-0}" 2>/dev/null || true)"
    install_commit_sha="$(printf '%s\n' "$commit_json" | sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-fA-F]*\)".*/\1/p' | head -n 1)"
    case "$install_commit_sha" in
      ''|*[!0-9a-fA-F]*) install_commit_sha="" ;;
    esac
    if [ "${#install_commit_sha}" -ge 40 ] && [ "${#install_commit_sha}" -le 64 ]; then
      script_url="https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/${install_commit_sha}/mh.sh"
      checksum_url="https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/${install_commit_sha}/mh.sh.sha256"
    fi
  fi
  curl -fsSL "$script_url" -o "$tmp_file" || {
    rm -f "$tmp_file"
    red "下载 mh.sh 失败。请检查网络、DNS 或 GitHub 访问是否正常。"
    red "如果同时看到 curl: (23)，通常是管道右侧命令提前退出，并非磁盘写入故障。"
    exit 1
  }
  checksum_file="$(make_temp /tmp/mh-install-sha.XXXXXX)"
  if curl -fsSL "$checksum_url" -o "$checksum_file"; then
    expected="$(awk 'NR == 1 { print $1 }' "$checksum_file")"
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "$tmp_file" | awk '{ print $1 }')"
    elif command -v openssl >/dev/null 2>&1; then
      actual="$(openssl dgst -sha256 "$tmp_file" | awk '{ print $NF }')"
    else
      actual=""
    fi
    if [ -z "$actual" ] || [ "$expected" != "$actual" ]; then
      rm -f "$tmp_file" "$checksum_file"
      red "安装失败：mh.sh SHA-256 校验不通过。"
      exit 1
    fi
  else
    red "警告：无法取得 SHA-256 文件，将仅执行脚本语法检查。"
  fi
  rm -f "$checksum_file"
fi

if ! sh -n "$tmp_file" 2>/dev/null; then
  rm -f "$tmp_file"
  red "安装失败：脚本语法检查未通过。"
  exit 1
fi

chmod +x "$tmp_file"
[ -f "$CLI_PATH" ] && cp "$CLI_PATH" "$CLI_BACKUP_PATH" && chmod 700 "$CLI_BACKUP_PATH"
mv "$tmp_file" "$CLI_PATH"
if [ -f /etc/mihomo/config.yaml ]; then
  "$CLI_PATH" network-migrate >/dev/null 2>&1 || true
fi
green "安装完成。现在可以输入 mh 打开管理面板。"
