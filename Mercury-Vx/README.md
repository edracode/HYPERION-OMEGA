# Mercury Vx 1.51 — Patch pengujian tanpa batas waktu posisi

Patch ini mengubah aturan exit dan ukuran lot untuk profil Super Aggressive. **Belum ada profil yang memenuhi target +50% setiap hari bertick dan +85% bersih dalam 12 bulan.** Profil Super Aggressive tersedia untuk Strategy Tester.

## Perubahan di EA

- `AggressiveMaxHoldSeconds = 0` mematikan penutupan berdasarkan umur posisi. `AggressiveCloseBeforeMidnightMinutes = 0` mematikan penutupan menjelang tengah malam. Stop Loss, Take Profit, batas ekuitas harian, dan batas drawdown tetap berlaku.
- `CommissionPerLotRoundTrip = 0` menetapkan asumsi komisi dalam perhitungan ukuran lot. `AggressiveSizingSpreadReserve = 0` mematikan cadangan spread tambahan pada estimasi risiko. EA tetap membaca Bid/Ask untuk transaksi, menyaring rasio spread terhadap jarak SL, dan menghormati biaya serta spesifikasi akun yang digunakan Strategy Tester.
- Profil otomatis mengenali XAU dan BTC dengan mata uang laba USD atau USC. Ukuran lot dihitung memakai `OrderCalcProfit` dan `OrderCalcMargin` dalam mata uang akun dengan volume minimum, maksimum, dan langkah lot yang dibaca dari simbol. Sebelum mengirim order, EA memeriksa kembali risiko volume yang telah dibulatkan. Journal mencetak mata uang akun, kontrak, dan satuan lot. [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit) · [OrderCalcMargin](https://www.mql5.com/en/docs/trading/ordercalcmargin)
- Profil manual menerima M1, M3, dan M5. Format Journal menampilkan `NetPct` bersama jumlah laba atau rugi dalam mata uang akun. Untuk tes beberapa tahun, ringkasan performa tahunan tersedia di CSV tahunan.

## Uji langsung pengaruh batas tiga menit

Periode **November 2025–Oktober 2026**. Setiap pengujian berjalan dengan saldo awal setara **US$1.000**. Untuk setiap baris, aturan sinyal dan persentase risiko sama sebelum dan sesudah. Kolom pertama memakai batas umur posisi 180 detik dan penutupan tiga menit sebelum pergantian hari. Kolom kedua menonaktifkan keduanya.

| Akun | Simbol | Exit berwaktu | Kedua batas waktu dimatikan | Hari ≥50% tanpa batas waktu |
|---|---|---:|---:|---:|
| Standard | XAUUSDm | −18,86% | −48,07% | 0/310 |
| Standard | BTCUSDm | −34,14% | −42,89% | 0/363 |
| Standard Cent | XAUUSDc | −22,88% | −47,29% | 0/308 |
| Standard Cent | BTCUSDc | −47,80% | −46,53% | 0/364 |

Pada Standard, saya juga mematikan batas umur posisi sambil mempertahankan penutupan menjelang tengah malam. Hasil XAUUSDm **−48,26%** dan BTCUSDm **−42,89%**. Pada empat tes utama tanpa exit berbasis waktu, log mencatat **nol penutupan karena umur posisi dan nol penutupan karena jam**.

## Uji alternatif tanpa batas waktu

Sebanyak 1.944 konfigurasi per simbol disaring pada data Standard Januari–Oktober 2025. Kandidat dikunci sebelum replay pada November 2025–Oktober 2026. Pencarian mencakup enam pola, M1/M3/M5, SL dan TP berbasis ATR, pilihan jam, dan risiko nominal 1%, 3%, atau 8%. Data Cent dipakai untuk replay kandidat terpilih, dengan tick dari simbol Cent.

| Kandidat BTC M5 | Laba bersih 12 bulan | Drawdown ekuitas | Hari ≥50% |
|---|---:|---:|---:|
| BTCUSDm, Standard | +37,54% | 50,00% | 1/363 |
| BTCUSDc, Standard Cent | +51,44% | 50,00% | 1/364 |
| BTCUSDc, biaya stres tambahan | +42,74% | 50,00% | 1/364 |

Kandidat ini memakai `TREND_PULLBACK`, lookback 8 bar, SL 0,90 ATR, target harga 2,00 kali jarak SL, risiko nominal 8%, dan semua jam. Kandidat yang sama rugi **43,43%** pada BTCUSDm Juli–Oktober 2024. Kandidat emas rugi **23,61%** pada Standard dan **22,37%** pada Cent dalam pengujian 12 bulan. Angka lengkap termasuk transaksi yang melewati tengah malam ada di [hasil_uji_151.csv](hasil_uji_151.csv).

### Asumsi dan cakupan

Replay lokal menggunakan 267.662.960 tick Bid/Ask dari arsip Exness, termasuk feed Standard dan Cent masing-masing. Pengujian utama menggunakan spread historis tanpa komisi tambahan dan dengan skenario swap nol. Model menggunakan leverage 1:100, lot minimum dan langkah lot 0,01 serta kontrak per simbol. Skenario biaya tambahan memakai 0,25 kali spread masuk dan beban inap sebesar 0,035 kali jarak risiko per pergantian hari UTC. Margin historis, swap dan delay broker dapat menghasilkan hasil berbeda di MT5. Gap harga dapat membuat drawdown melebihi batas yang disetel. [Arsip tick Exness](https://www.exness.com/tick-history/)

Exness mencantumkan spread akun Standard **mulai 0,2 pip** dan Standard Cent **mulai 0,3 pip**, keduanya bebas komisi. Itu adalah angka mulai untuk jenis akun. Replay membaca setiap perubahan spread pada tick simbol yang diuji. Exness memakai akhiran `m` untuk Standard dan `c` untuk Standard Cent, dengan BTCUSDc tersedia di MT5. [Spesifikasi akun Exness](https://get.exness.help/hc/id/articles/360013782240-Jenis-akun-trading) · [Akun Standard Cent](https://get.exness.help/hc/id/articles/17537782786588-Akun-Standar-Cent)

## Memeriksa di MT5

1. Ekstrak ZIP. Buka **MT5 → File → Open Data Folder** dan salin `Mercury_Vx.mq5` ke `MQL5/Experts/Advisors` jika versi lama ada di sana. Buka file di MetaEditor lalu tekan **F7**. Uji lokal C++ memeriksa logika inti, termasuk exit dengan input nol dan ukuran lot USD/USC. Kompilasi native belum diverifikasi.
2. Buka **Strategy Tester** dengan **Ctrl+R**. Pilih `Mercury_Vx` dan simbol Standard yang ingin diuji, misalnya `XAUUSDm` atau `BTCUSDm`. Pilih timeframe **M3**, **Every tick based on real ticks**, dan **Optimization → Disabled**. Pilih tanggal **1 November 2025–1 November 2026** untuk mereplikasi rentang tahunan, atau rentang sesuai riwayat simbol. [Model tick MT5](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
3. Di **Inputs**, pilih `SignalModel = SUPER_AGGRESSIVE`. Pastikan `AggressiveMaxHoldSeconds = 0` dan `AggressiveCloseBeforeMidnightMinutes = 0`. Dengan pengaturan ini, Journal menampilkan `Hold=0` dan `AcceptedTimeExitRequests=0`. Gunakan input **180** dan **3** untuk tes pembanding berwaktu. Untuk kandidat BTC M5, gunakan `SUPER_AGGRESSIVE_CUSTOM` dan nilai pada tabel riset.
4. Untuk tes Cent pilih simbol `XAUUSDc` atau `BTCUSDc` jika tersedia pada server atau melalui impor arsip. Bila mata uang simulasi **USC**, **100.000 USC = US$1.000**. Gunakan unit yang ditampilkan saat memasukkan deposit. Periksa `Coverage`, `Daily50Targets` dan `NetPct` di Journal. Salin CSV tahunan untuk mengecek setiap tahun lengkap. Panduan impor ada di [versi 1.40](https://github.com/edracode/HYPERION-OMEGA/blob/58dc6394d53be090340d8bce25d3d70744647dc6/Mercury-Vx/README.md#impor-riwayat).
