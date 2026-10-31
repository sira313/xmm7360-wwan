# AGENTS.md

Panduan untuk agent/AI yang mengerjakan project ini.

## Tujuan

Membuat modem **Intel XMM7360 / Fibocom L850-GL** (`8086:7360`) bekerja di
Arch Linux lewat driver mainline `iosm`, ModemManager git main, dan
NetworkManager.

Project ini adalah kumpulan script + dokumentasi, bukan driver kernel.

## Struktur

```
.
├── README.md                  # panduan pengguna (Indonesia, awam)
├── AGENTS.md                  # file ini
├── config.env.example         # contoh konfigurasi (di-commit)
├── config.env                 # konfigurasi lokal (di-ignore)
├── scripts/
│   ├── install.sh             # build + install ModemManager git main
│   ├── lib.sh                 # helper bersama (di-source)
│   ├── wwan                   # CLI: up/down/status/sim/reset/diag
│   └── diag.sh                # diagnostik AT + log
└── systemd/
    ├── wwan-fcc-unlock        # wrapper FCC unlock
    ├── ModemManager-fcc-unlock.conf
    └── 99-wwan-nopm.rules
```

## Data sensitif

- `config.env` **di-ignore** karena bisa berisi PIN, APN, atau nama operator.
  Yang di-commit hanya `config.env.example` dengan nilai generik.
- Jangan pernah commit IMSI, ICCID, IMEI, nomor SIM, IP publik, atau log mentah.
- Log (`*.log`), build (`.build/`), dan lock file editor di-ignore.
- Dokumentasi memakai placeholder seperti `510xx <operator>` dan
  `<IP privat dari operator>`.

## Perintah penting

```bash
sudo ./scripts/install.sh          # install dependency + build + config
sudo ./scripts/wwan up             # aktifkan modem sampai connect
sudo ./scripts/wwan up --apn X --pin Y --metric 100
./scripts/wwan status              # read-only, tidak perlu root
sudo ./scripts/wwan sim
sudo ./scripts/wwan reset
sudo ./scripts/wwan diag
sudo ./scripts/diag.sh --full
```

## Fakta hardware

- PCI ID: `8086:7360`
- Driver kernel: `iosm` (mainline sejak 5.18)
- Port: `/dev/wwan0at0`, `/dev/wwan0at1`, `/dev/wwan0xmmrpc0`, net `wwan0`
- Modem memakai protokol **AT + XMMRPC**, bukan MBIM/QMI
- `reset_method` di mesin ini: `acpi bus`

## Aturan teknis (jangan diubah tanpa alasan)

1. **Jangan pakai paket repo `modemmanager` 1.24.2.** Versi itu belum mendukung
   XMM7360 RPC. Build dari git main (>= commit fix 2026-05-24, `87c88dc2`).
2. Build flag wajib:
   `-Dqmi=false -Dqrtr=false -Dmbim=false -Dplugin_qcom_soc=disabled
   -Dtests=false -Dexamples=false -Dman=false -Dintrospection=false
   -Dbash_completion=false`
3. Prefix `/usr/local`. Karena itu:
   - `/etc/ld.so.conf.d/local.conf` harus berisi `/usr/local/lib`, lalu
     `ldconfig`. Tanpa ini binary 1.25 memakai `libmm-glib` 1.24 dari
     `/usr/lib` dan gagal dengan `undefined symbol:
     mm_gdbus_modem_get_ignored_ports`.
   - Config D-Bus/polkit perlu symlink ke `/etc/dbus-1/system.d`,
     `/usr/share/dbus-1/system-services`, `/usr/share/polkit-1/actions`.
4. `-Dexamples=false` berarti script FCC unlock tidak ikut ter-install.
   Install manual dari `data/dispatcher-fcc-unlock/8086:7360` ke
   `$PREFIX/share/ModemManager/fcc-unlock.available.d/`.
5. FCC unlock dijalankan lewat `ExecStartPre` di drop-in systemd, **bukan**
   symlink di `/etc/ModemManager/fcc-unlock.d` (race di port RPC).
6. Udev rule `99-wwan-nopm.rules` wajib: PCI runtime PM bisa membuat firmware
   crash.
7. Jangan menambahkan QMI/MBIM dependency. XMM7360 tidak memakainya.

## Gotchas

- SIM **tidak** terdeteksi kalau dimasukkan saat sistem hidup. Solusi:
  shutdown penuh, cabut charger, tahan power 10 detik. Reboot biasa tidak
  memutus daya modem.
- `AT+CPIN?` → `+CME ERROR: 10` berarti SIM tidak terlihat modem, bukan salah
  driver.
- `Serial command timed out` / `PORT open refused, phase A-ROM` = firmware
  crash. Perlu power cycle penuh.
- `AT+CFUN: 4` = radio off. ModemManager akan set online saat init; kalau
  ModemManager crash sebelum itu, CFUN tetap 4.
- Model string di `mmcli` terlihat aneh (`L850 LTE Module","L850`) karena
  parsing `AT+CGMM`; kosmetik, bukan bug.
- Setelah `systemctl restart dbus-broker`, NetworkManager akan reconnect ke
  ModemManager otomatis.

## Verifikasi perubahan

Minimal:

```bash
bash -n scripts/*.sh scripts/wwan systemd/wwan-fcc-unlock
./scripts/wwan status
sudo ./scripts/wwan up
mmcli -m 0 -K | grep -E 'state|registration-state|operator-name|signal-quality'
nmcli device status | grep -E 'wwan|gsm'
ping -I wwan0 -c 3 1.1.1.1
```

Sukses = `registration-state: home`, `packet-service-state: attached`,
`wwan0` punya IP, ping 0% loss.

## Gaya

- Script: Bash, `set -euo pipefail`, idempotent, pesan error bahasa Indonesia.
- Jangan simpan PIN/APN rahasia di repo; `config.env` hanya default.
- Dokumentasi pengguna bahasa Indonesia, jelaskan istilah saat pertama muncul.
- Perubahan kecil, tanpa abstraksi yang tidak perlu.
