# WWAN Intel XMM7360 / Fibocom L850 di Arch Linux

Panduan ini khusus untuk modem 4G bawaan laptop (Intel XMM7360, atau dikenal juga sebagai
Fibocom L850-GL) bisa dipakai di Arch Linux, lengkap dengan script otomasi.

## 1. Ringkasan

Device yang digunakan untuk testing adalah Thinkpad T495s, modem sudah dikenali di kernel:

```
04:00.0 Cellular controller/modem: Intel XMM7360 LTE Advanced Modem [8086:7360]
Kernel driver in use: iosm
```

Artinya driver dasar **sudah ada** sejak kernel 5.18. Yang kurang adalah aplikasi
pengelola modem (ModemManager) yang bisa berinteraksi dengan protokol khusus
XMM7360.

Masalah yang ditemukan dan diselesaikan:

| Gejala | Penyebab | Solusi |
|---|---|---|
| `mmcli` tidak ada / tidak menemukan modem | ModemManager belum terpasang | install ModemManager git |
| `SIM not inserted` padahal SIM terpasang | SIM dimasukkan saat sistem hidup; modem tidak scan ulang | shutdown penuh, cabut charger, tahan power 10 detik |
| `undefined symbol: mm_gdbus_modem_get_ignored_ports` | ModemManager 1.25 memakai library lama 1.24 di `/usr/lib` | prioritaskan `/usr/local/lib` lewat `ldconfig` |
| `Serial command timed out` | firmware modem macet setelah crash/reboot | shutdown penuh (bukan reboot) |
| Sudah connect tapi tidak ada internet | APN salah | isi APN yang benar di `config.env` |

Hasil akhir:

```
operator      : 510xx <operator>
registration  : home
packet service: attached
wwan0         : <IP privat dari operator>
ping via wwan0: 0% packet loss
```

## 2. Yang dibutuhkan

- Laptop dengan modem **Intel XMM7360 / Fibocom L850-GL**.
  Cek dengan:

  ```bash
  lspci -nn | grep 8086:7360
  ```

- Arch Linux (script menggunakan `pacman`).
- Koneksi internet sementara (WiFi/ethernet) untuk mengunduh paket.
- SIM **nano** dengan paket data aktif. Di ThinkPad T495s, slotnya
  berupa tray combo microSD/nano-SIM di bagian belakang laptop.
- Kernel 5.18 atau lebih baru. Cek dengan `uname -r`.

> Catatan: jika IMEI modem belum terdaftar di CEIR operator Indonesia, kartu
> bisa mendaftar ke jaringan tetapi data diblokir. Itu urusan registrasi IMEI,
> bukan driver.

## 3. Cara kerja singkat

Tiga lapisan yang terlibat:

1. **Kernel `iosm`** — driver PCIe untuk modem. Membuat port:
   `/dev/wwan0at0`, `/dev/wwan0at1`, `/dev/wwan0xmmrpc0`, dan interface `wwan0`.
2. **ModemManager** — menginisialisasi SIM, membuka PIN, mendaftar ke operator,
   dan membuat koneksi data. Versi repo Arch (1.24.2) belum mendukung protokol
   RPC XMM7360, jadi project ini membangun versi git terbaru (1.25.95).
3. **NetworkManager** — membuat profil GSM dan mengatur IP/route.

Project ini juga memasang **FCC unlock**. Tanpa itu, modem membatasi radio
(regulatory lock) dan tidak mau connect.

## 4. Instalasi

### 4.1 Masuk ke folder project

```bash
cd ~/Documents/Projects/xmm7360-wwan
cp config.env.example config.env
```
Edit file `config.env` seperti contoh

### 4.2 Jalankan installer

```bash
sudo ./scripts/install.sh
```

Installer akan:

- memasang paket: `base-devel`, `meson`, `ninja`, `git`, `pkgconf`,
  `glib2-devel`, `tinyxxd`, `libgudev`, `polkit`, `ppp`,
  `mobile-broadband-provider-info`
- mengunduh dan build ModemManager dari git main
- memasang ke `/usr/local`
- mengatur `/etc/ld.so.conf.d/local.conf` supaya library baru dipakai
- menyambungkan config D-Bus dan polkit
- memasang udev rule agar PCI power management tidak membuat firmware crash
- memasang script FCC unlock dan menjalankannya sebelum ModemManager start
- mengaktifkan service `ModemManager`

Proses build bisa 2–5 menit tergantung mesin.

### 4.3 Matikan total, jangan reboot

Ini bagian penting untuk deteksi SIM:

```bash
sudo shutdown -h now
```

Setelah mati:

1. Cabut charger.
2. Tahan tombol power 10 detik.
3. Cabut tray nano-SIM di belakang laptop, pasang SIM sampai klik, masukkan
   tray kembali sampai penuh.
4. Nyalakan laptop.

Reboot biasa **tidak** memutus daya modem, jadi harus shutdown.

### 4.4 Cek modem terdeteksi

```bash
mmcli -L
```

Harus muncul sesuatu seperti:

```
/org/freedesktop/ModemManager1/Modem/0 [Fibocom] L850 LTE Module
```

Kalau belum muncul, tunggu 20–30 detik lalu cek lagi.

---

## 5. Konfigurasi

Edit `config.env`:

```bash
nano config.env
```

Isi yang perlu disesuaikan:

| Variabel | Arti | Contoh |
|---|---|---|
| `APN` | Access Point Name operator | `internet` |
| `CONNECTION_NAME` | Nama profil NetworkManager | `wwan` |
| `ROUTE_METRIC` | Prioritas route; kecil = lebih utama | `700` |
| `PIN` | PIN SIM; kosongkan jika tidak ada | `1234` |
| `MODEM_ID` | Index modem, biasanya `0` | `0` |

### APN operator Indonesia

| Operator | APN |
|---|---|
| Telkomsel | `internet` |
| Indosat | `indosatgprs` |
| XL | `internet` |
| Tri (3) | `3gprs` |
| Smartfren | `internet` |
| by.U | `internet` |

Kalau tidak yakin, coba `internet` dulu, atau googling aja.

### Soal `ROUTE_METRIC`

- `700` → WiFi tetap jadi jalur utama, WWAN cadangan.
- `100` → WWAN dipakai sebagai jalur utama.

Bisa juga diubah sementara lewat opsi `--metric`.

## 6. Cara pakai

Semua perintah dijalankan dari folder project.

### Aktifkan dan connect

```bash
sudo ./scripts/wwan up
```

Yang dilakukan script:

1. memastikan service ModemManager hidup
2. menjalankan FCC unlock
3. menunggu modem siap
4. membuka PIN SIM kalau perlu
5. mendaftar ke jaringan
6. membuat/memperbarui profil NetworkManager
7. connect dan menampilkan IP
8. tes ping lewat `wwan0`

Contoh dengan opsi:

```bash
sudo ./scripts/wwan up --apn indosatgprs --pin 1234
sudo ./scripts/wwan up --metric 100
sudo ./scripts/wwan up --reset
sudo ./scripts/wwan up --no-ping
```

### Cek status

```bash
./scripts/wwan status
```

Menampilkan modem, sinyal, SIM, interface, dan route. Tidak perlu sudo.

### Lihat info SIM

```bash
sudo ./scripts/wwan sim
```

Kalau SIM memakai PIN dan `PIN` belum diisi, script akan memberi tahu.

### Putuskan koneksi

```bash
sudo ./scripts/wwan down
```

### Reset modem tanpa shutdown

```bash
sudo ./scripts/wwan reset
```

Memakai ACPI reset (`reset_method` = `acpi bus`). Berguna kalau modem macet
setelah suspend. Kalau firmware benar-benar crash, tetap perlu shutdown penuh.

### Diagnostik

```bash
sudo ./scripts/wwan diag
```

Mengumpulkan info hardware, AT command (`AT+CPIN?`, `AT+CSQ`, `AT+COPS?`), dan
log ModemManager ke `/tmp/wwan-diag.log`.

Untuk log debug ModemManager yang panjang:

```bash
sudo ./scripts/diag.sh --full
```

## 7. Cek manual (tanpa script)

```bash
# modem terdeteksi?
mmcli -L

# detail modem, SIM, operator, sinyal
mmcli -m 0

# daftar SIM
mmcli -i 0

# status interface
nmcli device status

# IP dan route
ip -br addr show wwan0
ip route | grep wwan0

# tes internet lewat modem
ping -I wwan0 -c 3 1.1.1.1
```

Scan operator:

```bash
mmcli -m 0 --3gpp-scan --timeout=60
```

## 8. Troubleshooting

### `error: couldn't find the ModemManager process in the bus`

Service mati atau crash.

```bash
systemctl status ModemManager
journalctl -u ModemManager -b --no-pager | tail -40
```

Kalau ada `undefined symbol: mm_gdbus_modem_get_ignored_ports`, jalankan ulang:

```bash
sudo ./scripts/install.sh
```

### SIM tidak terdeteksi (`+CME ERROR: 10`)

Artinya modem tidak melihat SIM.

1. Pasang ulang nano-SIM di tray, pastikan orientasi benar.
2. `sudo shutdown -h now`, cabut charger, tahan power 10 detik.
3. Nyalakan, lalu `sudo ./scripts/wwan up`.

### `Waiting for SIM init timed out`

Sama seperti di atas: SIM belum kontak atau modem perlu power cycle penuh.

### `Serial command timed out` / `PORT open refused, phase A-ROM`

Firmware modem crash. Warm reboot dan reload driver tidak cukup.

Lakukan shutdown penuh, cabut charger, tahan power 10 detik, nyalakan lagi.

### Connect tapi ping gagal

- Cek APN di `config.env`.
- Pastikan paket data SIM aktif.
- Cek sinyal: `mmcli -m 0 --signal-get`.
- Cek registrasi: `mmcli -m 0 -K | grep registration`.

### Sinyal 0% dan registrasi `idle`

- Pastikan antena WWAN terpasang ke modul (biasanya 2 kabel antena).
- Cek coverage operator.
- Coba scan: `mmcli -m 0 --3gpp-scan --timeout=60`.

### Trafik masih lewat WiFi

Lihat route:

```bash
ip route
```

Kalau `wwan0` metric lebih besar, ubah:

```bash
sudo ./scripts/wwan up --metric 100
```

### Modem mati setelah suspend

```bash
sudo ./scripts/wwan reset
```

Kalau sering terjadi, buat service resume reset (lihat referensi ArchWiki
`Intel XMM 7360`).

## 9. Uninstall

```bash
sudo systemctl disable --now ModemManager
sudo rm -f /etc/systemd/system/ModemManager.service.d/fcc-unlock.conf
sudo rm -f /etc/udev/rules.d/99-wwan-nopm.rules
sudo rm -f /usr/local/bin/wwan-fcc-unlock
sudo rm -f /usr/local/sbin/ModemManager /usr/local/bin/mmcli
sudo rm -rf /usr/local/lib/ModemManager /usr/local/share/ModemManager
sudo rm -f /etc/ld.so.conf.d/local.conf
sudo ldconfig
```

Setelah itu install ulang paket `modemmanager` dari repo kalau ingin versi stabil
(1.24.2), walaupun versi itu belum mendukung XMM7360.

## 10. Catatan teknis

- ModemManager dibangun dengan `-Dqmi=false -Dqrtr=false -Dmbim=false
  -Dplugin_qcom_soc=disabled` karena XMM7360 memakai AT + XMMRPC, bukan QMI/MBIM.
- Build memakai `-Dexamples=false`, jadi script FCC unlock dipasang manual dari
  `data/dispatcher-fcc-unlock/8086:7360`.
- Prefix install `/usr/local`, sehingga config D-Bus/polkit perlu symlink ke
  `/usr/share` dan `/etc`.
- `/etc/ld.so.conf.d/local.conf` wajib ada. Tanpa itu, binary 1.25 memakai
  `libmm-glib` 1.24 di `/usr/lib` dan crash.
- FCC unlock dijalankan lewat `ExecStartPre`, bukan symlink di
  `/etc/ModemManager/fcc-unlock.d`, untuk menghindari race di port RPC.
- Udev rule `99-wwan-nopm.rules` mematikan PCI runtime power management yang
  bisa membuat firmware XMM7360 crash.

## 11. Referensi

- ArchWiki: <https://wiki.archlinux.org/title/Intel_XMM_7360>
- ModemManager: <https://modemmanager.org/>
- libmbim / libqmi: <https://www.freedesktop.org/wiki/Software/libmbim/>
- Kernel iosm: <https://docs.kernel.org/networking/device_drivers/wwan/iosm.html>
- xmm7360-pci (alternatif out-of-tree): <https://github.com/xmm7360/xmm7360-pci>
