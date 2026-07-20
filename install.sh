#!/bin/sh

set -u

RAW_BASE="${MH_RAW_BASE:-https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/main}"
CLI_PATH="/usr/local/bin/mh"
CLI_BACKUP_PATH="/usr/local/bin/mh.previous"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

need_root() {
  if [ "$(id -u)" != "0" ]; then
    red "请使用 root 权限运行安装脚本：curl -fsSL <install.sh> | sudo sh"
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
if [ -f "./mh.sh" ]; then
  cp ./mh.sh "$tmp_file"
else
  curl -fsSL "$RAW_BASE/mh.sh" -o "$tmp_file" || {
    rm -f "$tmp_file"
    exit 1
  }
  checksum_file="$(make_temp /tmp/mh-install-sha.XXXXXX)"
  if curl -fsSL "$RAW_BASE/mh.sh.sha256" -o "$checksum_file"; then
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
green "安装完成。现在可以输入 mh 打开管理面板。"
