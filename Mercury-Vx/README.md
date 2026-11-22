# Mercury Vx 1.52 — Pengujian risiko terkendali

Profil bawaan `CONTROLLED_RISK` menguji strategi M5 dengan risiko awal 3% per posisi, batas rugi ekuitas harian 8%, dan batas drawdown dari puncak ekuitas 25%. Pada simulasi BTC, profil ini menurunkan drawdown dibanding kandidat v1.51. **Target +85% dalam 12 bulan dan +50% pada setiap hari bertick belum tercapai.**

## Perubahan di EA

- Risiko turun secara bertahap saat drawdown mencapai 8% dan menjadi seperempat risiko awal pada drawdown 18% dengan setelan bawaan. Anggaran lot juga dibatasi oleh sisa ruang hingga batas rugi harian dan drawdown. Gap dan eksekusi order dapat melewati batas yang ditetapkan.
- Filter entri menolak spread di atas 20% dari jarak Stop Loss. Sinyal otomatis menggunakan pullback tren untuk BTC M5 dan kelanjutan tren untuk XAU M5. Keduanya memakai lookback 8 dan jarak TP sebesar 2 kali jarak SL. SL BTC 0,90 ATR dan SL XAU 1,40 ATR.
- Batas umur posisi dan penutupan menjelang tengah malam tetap nonaktif secara bawaan. Stop Loss, Take Profit, dan penutupan karena batas risiko tetap aktif. Profil `SUPER_AGGRESSIVE` dan `SUPER_AGGRESSIVE_CUSTOM` tersedia untuk mengulang penelitian terdahulu.
- Ukuran lot menggunakan spesifikasi simbol dan mata uang akun. Laporan `ResearchGate` memerlukan kelulusan harian, sampel minimum sesuai input, dan setidaknya +85% bersih pada cakupan 12 bulan. Pemeriksaan cakupan mencari 12 bulan kalender berturut-turut dengan toleransi tiga hari pada tepi rentang. Rentang lain menampilkan `Annual85=COVERAGE_UNVERIFIED`. Cek juga `Coverage` dan riwayat pada Strategy Tester untuk melihat kualitas data.

## Replay November 2025–Oktober 2026

Saldo awal tiap pengujian setara US$1.000. Replay membaca tick Bid/Ask masing-masing simbol Standard dan Cent. Biaya komisi tambahan nol dan swap awal dimodelkan nol. Uji stres menambahkan 0,25 kali spread saat masuk dan biaya inap 0,035 kali risiko harga per pergantian hari UTC. Leverage simulasi 1:100. Biaya, margin, dan eksekusi broker di MT5 dapat berbeda dari asumsi replay. [Sumber arsip tick Exness](https://www.exness.com/tick-history/)

| Simbol | Hasil bersih v1.52 | Hasil dengan biaya stres | Drawdown dasar | Hari mencapai +50% |
|---|---:|---:|---:|---:|
| BTCUSDm Standard | +21,77% | +18,83% | 24,99% | 0/363 |
| BTCUSDc Cent | +16,38% | +14,05% | 25,00% | 0/364 |
| XAUUSDm Standard | −1,60% | −1,50% | 23,61% | 0/310 |
| XAUUSDc Cent | +12,52% | +6,03% | 23,58% | 0/308 |

Kandidat BTC M5 v1.51 pada periode yang sama mencapai +37,54% di Standard dan +51,44% di Cent dengan drawdown sekitar 50%. Replay v1.52 juga menguji konfigurasi yang hanya mengubah pengendalian ukuran posisi dan batas risiko agar pengaruh filter spread bisa diperiksa. Pada pengujian terpisah Januari–Desember 2024, BTCUSDm v1.52 rugi **19,13%** dengan drawdown **24,92%**. Dengan biaya stres hasilnya **−19,46%**. Periode 2024 memuat 83.315.072 tick BTCUSDm. Empat bulan di tahun tersebut pernah dipakai untuk menguji kandidat sebelumnya. Delapan bulan lainnya baru ditambahkan dalam pengujian tahunan ini.

Angka dari **15 replay** tersedia di [hasil_uji_152.csv](hasil_uji_152.csv). Semua periode memakai saldo awal baru. Angka laba persentase memakai saldo awal penuh dan tanpa penyetoran ulang.

## Memeriksa di MT5

1. Ekstrak ZIP. Salin `Mercury_Vx.mq5` melalui **MT5 → File → Open Data Folder → MQL5 → Experts**. Buka di MetaEditor lalu tekan **F7**. Uji logika C++ lokal memeriksa pengurangan risiko, ukuran lot, aturan exit, dan batas cakupan kalender. Kompilasi native belum diverifikasi.
2. Tekan **Ctrl+R** dan pilih EA, timeframe **M5**, simbol Standard bersufiks `m` atau simbol Cent bersufiks `c`, dan **Every tick based on real ticks**. Untuk mengulang replay terbaru, gunakan rentang **1 November 2025–1 November 2026**, leverage 1:100, dan deposit setara US$1.000. Jika mata uang akun yang dipilih **USC**, masukkan **100.000 USC**. [Mode pengujian MetaTrader 5](https://www.metatrader5.com/en/automated-trading/strategy-tester)
3. Pada **Inputs**, gunakan `SignalModel = CONTROLLED_RISK`, `AggressiveMaxHoldSeconds = 0`, dan `AggressiveCloseBeforeMidnightMinutes = 0`. Jaga `SessionStartHour` dan `SessionEndHour` sama untuk tes semua jam. Periksa `RiskThrottle`, `ResearchGate`, dan `AcceptedTimeExitRequests` di Journal. Untuk data arsip, ikuti [panduan impor v1.40](https://github.com/edracode/HYPERION-OMEGA/blob/58dc6394d53be090340d8bce25d3d70744647dc6/Mercury-Vx/README.md#impor-riwayat).
