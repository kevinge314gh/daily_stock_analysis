#!/bin/sh
set -eu

APP_USER="dsa"
APP_GROUP="dsa"
APP_UID="1000"
APP_GID="1000"
WRITABLE_DIRS="/app/data /app/logs /app/reports /home/dsa/.longbridge /home/dsa/.claude"
DATABASE_FILE="${DATABASE_PATH:-/app/data/stock_analysis.db}"

warn() {
    printf '%s\n' "$*" >&2
}

can_write_dir_as_app_user() {
    gosu "$APP_USER:$APP_GROUP" sh -c '
        tmp="$1/.dsa-write-check.$$"
        : > "$tmp" && rm -f "$tmp"
    ' sh "$1"
}

can_write_file_as_app_user() {
    gosu "$APP_USER:$APP_GROUP" test -w "$1"
}

has_unwritable_mount_path() {
    dir="$1"

    if ! can_write_dir_as_app_user "$dir"; then
        return 0
    fi

    if [ "$dir" = "/app/data" ]; then
        for file in "$DATABASE_FILE" "$DATABASE_FILE-wal" "$DATABASE_FILE-shm"; do
            if [ -e "$file" ] && ! can_write_file_as_app_user "$file"; then
                return 0
            fi
        done
    fi

    return 1
}

directory_needs_repair() {
    dir="$1"

    if has_unwritable_mount_path "$dir"; then
        return 0
    fi

    mismatched_path="$(
        find "$dir" \
            \( ! -user "$APP_UID" -o ! -group "$APP_GID" \) \
            -print -quit 2>/dev/null || true
    )"
    if [ -n "$mismatched_path" ]; then
        return 0
    fi

    return 1
}

if [ "$(id -u)" = "0" ]; then
    # ---------- VPN（可选，仅当挂载了 OpenVPN 配置时启动） ----------
    OPENVPN_DIR="${OPENVPN_DIR:-/etc/openvpn}"
    TUN_TIMEOUT="${TUN_TIMEOUT:-60}"
    OVPN_PID=""

    find_vpn_config() {
        for _f in "$OPENVPN_DIR"/*.conf "$OPENVPN_DIR"/*.ovpn; do
            [ -f "$_f" ] && { echo "$_f"; return 0; }
        done
        return 1
    }

    wait_for_tun() {
        _i=0
        while [ "$_i" -lt "$TUN_TIMEOUT" ]; do
            if ip addr show tun0 >/dev/null 2>&1; then return 0; fi
            if [ -n "$OVPN_PID" ] && ! kill -0 "$OVPN_PID" 2>/dev/null; then
                warn "[entrypoint] OpenVPN 进程已退出"
                return 1
            fi
            sleep 1; _i=$((_i+1))
        done
        return 1
    }

    if VPN_CONF="$(find_vpn_config 2>/dev/null)"; then
        printf '%s\n' "[entrypoint] 找到 VPN 配置：$VPN_CONF"
        OVPN_AUTH_ARGS=""
        if [ -f "$OPENVPN_DIR/creds.txt" ]; then
            OVPN_AUTH_ARGS="--auth-user-pass $OPENVPN_DIR/creds.txt"
            printf '%s\n' "[entrypoint] 使用凭据文件：$OPENVPN_DIR/creds.txt"
        fi
        # shellcheck disable=SC2086
        openvpn --config "$VPN_CONF" $OVPN_AUTH_ARGS \
            --data-ciphers AES-256-GCM:AES-128-GCM:AES-128-CBC \
            --data-ciphers-fallback AES-128-CBC \
            --script-security 2 --up /usr/local/bin/openvpn-up.sh &
        OVPN_PID=$!
        printf '%s\n' "[entrypoint] OpenVPN 已后台启动 (pid=$OVPN_PID)，等待 tun0 (超时 ${TUN_TIMEOUT}s)..."
        if ! wait_for_tun; then
            warn "[entrypoint] 错误：tun0 未在 ${TUN_TIMEOUT}s 内就绪，退出。"
            kill "$OVPN_PID" 2>/dev/null || true
            exit 1
        fi
        printf '%s\n' "[entrypoint] VPN 隧道就绪 (tun0)。"
    fi
    # ---------- VPN 结束 ----------

    for dir in $WRITABLE_DIRS; do
        if ! mkdir -p "$dir"; then
            warn "WARN: unable to create $dir; application writes may fail for this path."
            continue
        fi

        if ! directory_needs_repair "$dir"; then
            continue
        fi

        if chown -R "$APP_UID:$APP_GID" "$dir"; then
            if ! chmod -R u+rwX "$dir"; then
                warn "WARN: unable to adjust owner permissions for $dir after ownership repair; check read-only, rootless, or NFS mount permissions if writes fail."
            fi
        else
            warn "WARN: unable to set ownership for $dir; skipping owner-only chmod because it would not grant writes to $APP_USER without ownership."
        fi

        if has_unwritable_mount_path "$dir"; then
            warn "WARN: $dir is still not writable by $APP_USER after permission repair; check host mount ownership or read-only, rootless, and NFS mount settings."
        fi
    done

    HOME="/home/dsa"
    export HOME
    exec gosu "$APP_USER:$APP_GROUP" "$@"
fi

exec "$@"
