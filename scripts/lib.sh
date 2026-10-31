#!/usr/bin/env bash
# Helper bersama untuk scripts/wwan. Di-source, bukan dijalankan langsung.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Default; bisa ditimpa config.env atau environment variable.
APN="${APN:-internet}"
CONNECTION_NAME="${CONNECTION_NAME:-wwan}"
ROUTE_METRIC="${ROUTE_METRIC:-700}"
PIN="${PIN:-}"
MODEM_ID="${MODEM_ID:-0}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"

CONFIG_FILE="$ROOT_DIR/config.env"
[[ -f "$CONFIG_FILE" ]] || CONFIG_FILE="$ROOT_DIR/config.env.example"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

modem_present() {
  have mmcli && mmcli -L 2>/dev/null | grep -q 'Modem/'
}

# Ambil satu nilai dari `mmcli -m N -K`.
mm_key() {
  mmcli -m "$MODEM_ID" -K 2>/dev/null \
    | awk -F': ' -v k="$1" '$1 ~ k {print $2; exit}'
}

wait_for_modem() {
  local timeout="${1:-60}" i state
  log "menunggu modem siap (maks ${timeout}s)"
  for ((i = 0; i < timeout; i++)); do
    if modem_present; then
      state="$(mm_key 'modem.generic.state')"
      case "$state" in
        enabled|registered|disconnected|connecting|connected) return 0 ;;
      esac
    fi
    sleep 1
  done
  return 1
}

wait_for_ip() {
  local timeout="${1:-30}" i
  for ((i = 0; i < timeout; i++)); do
    if ip -4 addr show wwan0 2>/dev/null | grep -q 'inet '; then
      ip -4 addr show wwan0 | awk '/inet /{print $2; exit}'
      return 0
    fi
    sleep 1
  done
  return 1
}

ensure_service() {
  [[ -x /usr/local/sbin/ModemManager ]] \
    || die "ModemManager belum terpasang. Jalankan: sudo $ROOT_DIR/scripts/install.sh"
  systemctl is-enabled --quiet ModemManager 2>/dev/null || systemctl enable ModemManager
  systemctl is-active --quiet ModemManager 2>/dev/null || systemctl start ModemManager
}

fcc_unlock() {
  if [[ -x /usr/local/bin/wwan-fcc-unlock ]]; then
    /usr/local/bin/wwan-fcc-unlock || true
  fi
}

unlock_sim() {
  local lock
  lock="$(mm_key 'modem.generic.unlock-required')"
  [[ -z "$lock" || "$lock" == "--" ]] && return 0
  [[ -n "$PIN" ]] || die "SIM terkunci ($lock). Isi PIN di config.env atau jalankan dengan --pin"
  log "membuka SIM ($lock)"
  mmcli -m "$MODEM_ID" --pin="$PIN" >/dev/null
}

enable_modem() {
  local state
  state="$(mm_key 'modem.generic.state')"
  if [[ "$state" == "disabled" ]]; then
    log "mengaktifkan modem"
    mmcli -m "$MODEM_ID" --enable >/dev/null
    sleep 3
  fi
}

register_home() {
  log "mendaftar ke jaringan (home)"
  mmcli -m "$MODEM_ID" --3gpp-register-home >/dev/null 2>&1 || true
}

wait_for_registration() {
  local timeout="${1:-60}" i reg
  for ((i = 0; i < timeout; i++)); do
    reg="$(mm_key 'modem.3gpp.registration-state')"
    case "$reg" in
      home|roaming) return 0 ;;
    esac
    sleep 1
  done
  return 1
}

connect_nm() {
  local apn="${1:-$APN}"
  if nmcli -t -f NAME connection show | grep -qx "$CONNECTION_NAME"; then
    log "memperbarui profil '$CONNECTION_NAME' (APN: $apn)"
    nmcli connection modify "$CONNECTION_NAME" \
      gsm.apn "$apn" \
      connection.autoconnect yes \
      connection.metered yes \
      ipv4.route-metric "$ROUTE_METRIC" >/dev/null
  else
    log "membuat profil '$CONNECTION_NAME' (APN: $apn)"
    nmcli connection add type gsm ifname '*' con-name "$CONNECTION_NAME" \
      gsm.apn "$apn" \
      connection.autoconnect yes \
      connection.metered yes \
      ipv4.route-metric "$ROUTE_METRIC" >/dev/null
  fi
  nmcli connection up "$CONNECTION_NAME" >/dev/null \
    || die "gagal mengaktifkan profil '$CONNECTION_NAME'. Cek APN/sinyal: sudo $0 diag"
}

print_signal() {
  mmcli -m "$MODEM_ID" --signal-get 2>/dev/null \
    | grep -E 'signal|rsrp|rsrq|s/n|rssi' || true
}
