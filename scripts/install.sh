#!/usr/bin/env bash
# Install ModemManager git main + dukungan XMM7360 di Arch Linux.
# Jalankan: sudo ./scripts/install.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build/ModemManager}"
PREFIX="${PREFIX:-/usr/local}"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "jalankan dengan sudo: sudo $0"
command -v pacman >/dev/null 2>&1 || die "script ini untuk Arch Linux (pacman)"
command -v nmcli  >/dev/null 2>&1 || die "NetworkManager belum terpasang: sudo pacman -S networkmanager"
modinfo iosm >/dev/null 2>&1 || warn "modul kernel iosm tidak ditemukan; cek versi kernel (butuh >= 5.18)"

if ! lspci -nn 2>/dev/null | grep -q '8086:7360'; then
  warn "modem Intel XMM7360 (8086:7360) tidak terlihat. Lanjut, tapi cek hardware."
fi

log "1/8 paket yang dibutuhkan"
pacman -S --needed --noconfirm \
  base-devel meson ninja git pkgconf glib2-devel tinyxxd \
  libgudev polkit ppp mobile-broadband-provider-info

log "2/8 ambil sumber ModemManager (git main)"
mkdir -p "$(dirname -- "$BUILD_DIR")"
if [[ -d "$BUILD_DIR/.git" ]]; then
  git -C "$BUILD_DIR" fetch --depth 1 origin main
  git -C "$BUILD_DIR" reset --hard FETCH_HEAD
else
  git clone --depth 1 \
    https://gitlab.freedesktop.org/mobile-broadband/ModemManager.git \
    "$BUILD_DIR"
fi

log "3/8 build ModemManager"
cd "$BUILD_DIR"
rm -rf build
meson setup build \
  --prefix="$PREFIX" \
  -Dqmi=false \
  -Dqrtr=false \
  -Dmbim=false \
  -Dplugin_qcom_soc=disabled \
  -Dtests=false \
  -Dexamples=false \
  -Dman=false \
  -Dintrospection=false \
  -Dbash_completion=false
ninja -C build

log "4/8 install ke $PREFIX"
ninja -C build install

log "5/8 prioritaskan library $PREFIX/lib"
printf '%s\n' "$PREFIX/lib" > /etc/ld.so.conf.d/local.conf
ldconfig

log "6/8 sambungkan config D-Bus dan polkit"
if [[ "$PREFIX" != "/usr" ]]; then
  mkdir -p /etc/dbus-1/system.d /usr/share/dbus-1/system-services /usr/share/polkit-1/actions
  ln -sf "$PREFIX/etc/dbus-1/system.d/org.freedesktop.ModemManager1.conf" \
         /etc/dbus-1/system.d/org.freedesktop.ModemManager1.conf
  ln -sf "$PREFIX/share/dbus-1/system-services/org.freedesktop.ModemManager1.service" \
         /usr/share/dbus-1/system-services/org.freedesktop.ModemManager1.service
  ln -sf "$PREFIX/share/polkit-1/actions/org.freedesktop.ModemManager1.policy" \
         /usr/share/polkit-1/actions/org.freedesktop.ModemManager1.policy
fi

log "7/8 udev rule + FCC unlock"
install -Dm644 "$ROOT_DIR/systemd/99-wwan-nopm.rules" \
  /etc/udev/rules.d/99-wwan-nopm.rules
install -Dm755 "$BUILD_DIR/data/dispatcher-fcc-unlock/8086:7360" \
  "$PREFIX/share/ModemManager/fcc-unlock.available.d/8086:7360"
install -Dm755 "$ROOT_DIR/systemd/wwan-fcc-unlock" \
  "$PREFIX/bin/wwan-fcc-unlock"
mkdir -p /etc/systemd/system/ModemManager.service.d
cat > /etc/systemd/system/ModemManager.service.d/fcc-unlock.conf <<EOF
[Service]
ExecStartPre=-$PREFIX/bin/wwan-fcc-unlock
EOF

log "8/8 reload service"
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger /sys/bus/pci/devices/0000:04:00.0 2>/dev/null || true
if systemctl list-unit-files 2>/dev/null | grep -q '^dbus-broker.service'; then
  systemctl restart dbus-broker
else
  systemctl restart dbus
fi
systemctl enable --now ModemManager

cat <<EOF

Selesai.

Langkah berikutnya:
  1. Matikan total: sudo shutdown -h now
  2. Cabut charger, tahan tombol power 10 detik
  3. Pasang nano-SIM di tray combo (pastikan duduk benar)
  4. Nyalakan, edit $ROOT_DIR/config.env (APN/PIN)
  5. Aktifkan: sudo $ROOT_DIR/scripts/wwan up

Cek status kapan saja: $ROOT_DIR/scripts/wwan status
EOF
