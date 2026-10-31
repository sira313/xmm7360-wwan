#!/usr/bin/env bash
# Diagnostik WWAN. Jalankan: sudo ./scripts/diag.sh [--full]
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOG="${LOG:-/tmp/wwan-diag.log}"
FULL=0
[[ "${1:-}" == "--full" ]] && FULL=1

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "jalankan dengan sudo: sudo $0" >&2; exit 1; }
exec > >(tee "$LOG") 2>&1

echo "== tanggal =="; date
echo "== hardware =="
lspci -nnk 2>/dev/null | grep -A3 -i '8086:7360' || true
rfkill list 2>/dev/null | grep -A2 -i wwan || true

echo "== stop ModemManager =="
systemctl stop ModemManager 2>/dev/null || true
sleep 1

echo "== FCC unlock =="
if [[ -x /usr/local/bin/wwan-fcc-unlock ]]; then
  /usr/local/bin/wwan-fcc-unlock || true
else
  echo "wwan-fcc-unlock belum terpasang"
fi

echo "== AT probe =="
python3 - <<'PY'
import os, select, time

for dev in ("/dev/wwan0at1", "/dev/wwan0at0"):
    print("==", dev)
    try:
        fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
    except OSError as e:
        print("open gagal:", e)
        continue
    for cmd in (b"AT\r", b"AT+CPIN?\r", b"AT+CCID\r", b"AT+CSQ\r",
                b"AT+CGMM\r", b"AT+CFUN?\r", b"AT+COPS?\r"):
        try:
            os.write(fd, cmd)
        except OSError as e:
            print(cmd, "write gagal:", e)
            break
        time.sleep(0.3)
        out = b""
        while select.select([fd], [], [], 0.7)[0]:
            try:
                chunk = os.read(fd, 4096)
            except OSError as e:
                out += ("<err %s>" % e).encode()
                break
            if not chunk:
                break
            out += chunk
        print(cmd, "->", out[:400])
    os.close(fd)
PY

if [[ "$FULL" -eq 1 ]]; then
  echo "== ModemManager foreground debug 45s =="
  timeout 45 /usr/local/sbin/ModemManager --debug > /tmp/mm-debug.log 2>&1
  echo "rc=$?"
  tail -60 /tmp/mm-debug.log
fi

echo "== kernel =="
dmesg 2>/dev/null | grep -iE 'iosm|wwan|xmm' | tail -20 || true

echo "== start ModemManager =="
systemctl start ModemManager
sleep 20
mmcli -L 2>&1 || true
mmcli -m 0 2>&1 | sed -n '1,35p' || true

echo "== journal =="
journalctl -u ModemManager -b --no-pager -o cat 2>&1 | tail -25

echo "== selesai: $LOG =="
