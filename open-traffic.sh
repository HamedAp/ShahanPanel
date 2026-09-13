#!/bin/bash
set -u

LOG="/var/log/using_db_cron.log"
FILE="/var/db/ovpm/openvpn-status.log"
DB_NAME="ShaHaN"
MYSQL_CMD="/usr/bin/mysql"

mkdir -p "$(dirname "$LOG")"
exec 9>/var/lock/ssh-panel-open-traffic.lock
if ! flock -n 9; then
    echo "=== OpenVPN traffic skipped: another run is active at $(date) ===" >> "$LOG"
    exit 0
fi
echo "=== OpenVPN traffic started at $(date) ===" >> "$LOG"

mysql_query() {
    "$MYSQL_CMD" --batch --skip-column-names "$DB_NAME" -e "$1"
}

if ! mysql_query '
CREATE TABLE IF NOT EXISTS TrafficLast (
    user VARCHAR(50) NOT NULL,
    ip VARCHAR(50) NOT NULL,
    rx BIGINT UNSIGNED NOT NULL DEFAULT 0,
    tx BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (user, ip)
) ENGINE=InnoDB;
' >> "$LOG" 2>&1; then
    echo "ERROR: cannot create or access TrafficLast" >> "$LOG"
    exit 1
fi

if [[ ! -r "$FILE" ]]; then
    echo "WARNING: OpenVPN status file is missing or unreadable" >> "$LOG"
    exit 0
fi

snapshot=$(mktemp /tmp/ssh-panel-openvpn-status.XXXXXX) || exit 1
trap 'rm -f "$snapshot"' EXIT
if ! cp -- "$FILE" "$snapshot"; then
    echo "ERROR: cannot snapshot OpenVPN status file" >> "$LOG"
    exit 1
fi

processed=0
updated=0
while IFS=',' read -r user remote rx tx rest; do
    [[ "$rx" =~ ^[0-9]+$ && "$tx" =~ ^[0-9]+$ ]] || continue
    user="${user,,}"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || continue
    ip="${remote%:*}"
    ip="${ip#[}"
    ip="${ip%]}"
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || continue
    ((processed++))

    last=$(mysql_query "SELECT rx, tx FROM TrafficLast WHERE user='${user}' AND ip='${ip}' LIMIT 1;" 2>>"$LOG" || true)
    last_rx=0; last_tx=0
    if [[ "$last" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        last_rx="${BASH_REMATCH[1]}"; last_tx="${BASH_REMATCH[2]}"
    fi
    (( rx < last_rx )) && last_rx=$rx
    (( tx < last_tx )) && last_tx=$tx
    diff_rx=$((rx - last_rx)); diff_tx=$((tx - last_tx))
    dl_mb=$(awk -v n="$diff_rx" 'BEGIN { printf "%.6f", n/1048576 }')
    ul_mb=$(awk -v n="$diff_tx" 'BEGIN { printf "%.6f", n/1048576 }')
    total_mb=$(awk -v a="$dl_mb" -v b="$ul_mb" 'BEGIN { printf "%.6f", a+b }')

    sql="START TRANSACTION;
INSERT INTO Traffic (user, download, upload, total) VALUES ('${user}', ${dl_mb}, ${ul_mb}, ${total_mb})
ON DUPLICATE KEY UPDATE download=download+VALUES(download), upload=upload+VALUES(upload), total=total+VALUES(total);
INSERT INTO TrafficLast (user, ip, rx, tx) VALUES ('${user}', '${ip}', ${rx}, ${tx})
ON DUPLICATE KEY UPDATE rx=${rx}, tx=${tx};
COMMIT;"
    if mysql_query "$sql" >> "$LOG" 2>&1; then
        ((updated++))
    else
        echo "ERROR: failed to save OpenVPN traffic for ${user} (${ip})" >> "$LOG"
    fi
done < "$snapshot"

echo "=== OpenVPN traffic completed at $(date): processed=${processed}, updated=${updated} ===" >> "$LOG"
