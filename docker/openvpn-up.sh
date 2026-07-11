#!/usr/bin/env bash
# OpenVPN --up 脚本：把服务器 push 下来的 DNS/DOMAIN 写入 /etc/resolv.conf。
# 否则 redirect-gateway 把默认路由导入隧道后，容器仍用旧 DNS，域名解析失败 (EAI_AGAIN)。
set -eo pipefail

resolv=/etc/resolv.conf

pushed="$(env | sed -n \
  -e 's/^foreign_option_[0-9]*=dhcp-option DNS /nameserver /p' \
  -e 's/^foreign_option_[0-9]*=dhcp-option DOMAIN /search /p')"

[ -z "$pushed" ] && exit 0

{ printf '%s\n' "$pushed"; cat "$resolv"; } > "$resolv.vpn" && cat "$resolv.vpn" > "$resolv"
rm -f "$resolv.vpn"
exit 0
