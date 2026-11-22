# Mercury Vx 1.50 Super Aggressive

Profil scalper eksperimental untuk Strategy Tester MT5. Sasaran pengujian adalah kenaikan ekuitas **≥50% pada setiap hari server yang memiliki tick**. Win rate dan risk:reward tetap dilaporkan dan tidak menjadi syarat kelulusan profil ini. **Kedua profil gagal pada pengujian yang dilaporkan di sini.**

## Hasil di luar periode pemilihan

Replay lokal menggunakan 158.436.857 tick Bid/Ask dari arsip publik Exness untuk Juli–Oktober 2024 dan Januari–Oktober 2026. Setiap baris di bawah adalah satu pengujian berkelanjutan dengan modal awal US$1.000. [Arsip tick Exness](https://www.exness.com/tick-history/)

| Profil | Periode | Trade | Hari untung | Hari rugi | Hari datar | Hari ≥50% | Laba bersih | Drawdown ekuitas |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| XAUUSDm M3 | Jan–Okt 2026 | 342 | 70 | 97 | 92 | **0/259** | −US$162,85 | 17,61% |
| BTCUSDm M3 | Jan–Okt 2026 | 32 | 1 | 5 | 296 | **0/302** | −US$489,46 | 49,99% |
| XAUUSDm M3 | Jul–Okt 2024 | 186 | 28 | 52 | 26 | **0/106** | −US$287,28 | 29,53% |
| BTCUSDm M3 | Jul–Okt 2024 | 25 | 0 | 7 | 116 | **0/123** | −US$499,68 | 49,97% |

Pada tes Januari–Oktober 2026, hari terbaik kandidat XAUUSDm **+1,52%** dan kandidat BTCUSDm **+2,95%**. Biaya tambahan yang lebih tinggi menghasilkan rugi **US$215,70** pada emas dan **US$493,44** pada Bitcoin. Profil tambahan XAUUSDm M1 dengan risiko nominal 20% menghasilkan rugi **US$497,03** dan **0/259** hari mencapai target.

### Diagnostik dengan saldo direset setiap hari

Untuk mengukur apakah batas drawdown kumulatif menjelaskan hasil tersebut, setiap hari Januari–Oktober 2026 juga diuji dengan saldo independen US$1.000. Pengujian ini hanya diagnostik. Hasil tiap hari tidak mewakili pertumbuhan satu rekening.

| Profil | Hari ≥50% | Hari rugi | Hari terbaik |
|---|---:|---:|---:|
| XAUUSDm M3, risiko nominal 2% | 0/259 | 101 | +2,22% |
| XAUUSDm M1, risiko nominal 20% | 1/259 | 155 | +52,28% |
| BTCUSDm M3, risiko nominal 20% | 2/302 | 278 | +55,42% |

Lihat [hasil_super_aggressive.csv](hasil_super_aggressive.csv) untuk semua pengujian. Kolom laba bersih pada baris `fresh_daily_tick` menjumlahkan hasil tes independen, dan kolom drawdown adalah maksimum intrahari yang diamati.

### Cara pengujian

- Sebanyak 1.296 kombinasi per simbol disaring pada bar satu menit untuk dua paruh 2025. Grid mencakup enam pola di M1 dan M3, tiga lookback, tiga jarak SL, tiga rasio TP terhadap SL, dan risiko nominal 2%, 6%, 12%, atau 20% per posisi. Mode scalper memakai maksimal 180 detik per posisi.
- Tidak ada konfigurasi dengan sedikitnya 25 trade per paruh yang mencatat laba bersih positif di kedua paruh. Untuk replay lanjut, kandidat dengan sedikitnya 25 trade per paruh dipilih berdasarkan jumlah hari ≥50%, kemudian hasil di paruh terlemah. Pada penyaringan, Bitcoin mencapai paling banyak satu hari ≥50% per paruh. Emas tidak mencapai target pada paruh mana pun. Kandidat dikunci sebelum pengujian tick periode lain.
- Replay memakai Bid/Ask historis, posisi tunggal, lot minimum dan langkah lot 0,01, leverage simulasi 1:100, margin maks. 80% dari saldo saat entri, dan pendekatan biaya tambahan 0,5 kali spread masuk. Tes stres memakai satu kali spread. Posisi yang menyeberangi tengah malam dikenai pendekatan biaya inap 0,035 R per hari. Komisi broker, stop level, delay, margin historis, dan aturan penutupan paksa di MT5 dapat berbeda. Gap harga dapat menyebabkan rugi melewati batas yang disetel.
- Logika sinyal, konfigurasi profil, harga TP, dan syarat kelulusan diperiksa dengan uji C++. Kompilasi native dan hasil Strategy Tester MT5 belum diverifikasi.

## Profil dan pengujian di MT5

| Simbol | Profil otomatis | Timeframe | Stop loss | Target harga | Risiko nominal |
|---|---|---|---:|---:|---:|
| XAUUSDm | Pembalikan setelah gerak ekstrem, lookback 16 | M3 | 2,00 ATR | 1:1,35 | 2% |
| BTCUSDm | Pembalikan wick, lookback 8 | M3 | 0,80 ATR | 1:0,80 | 20% |

EA membatasi ukuran posisi menggunakan anggaran risiko, lot minimum, margin, dan spread. Batas bawaan adalah rugi ekuitas harian 25% dan drawdown kumulatif dari puncak ekuitas 50%. Risiko nominal 20% dapat menyebabkan kerugian besar dalam beberapa transaksi. Waktu tunggu antarposisi 30 detik. EA berhenti membuka posisi pada hari itu jika ekuitas telah mencapai +50% dan posisi sudah tertutup. Profil Super Aggressive berjalan hanya di Strategy Tester.

1. Ekstrak `Mercury_Vx_MT5.zip`. Di MT5 buka **File → Open Data Folder**, salin `Mercury_Vx.mq5` ke folder `MQL5/Experts/Advisors` jika versi lama ada di sana. Buka file lewat MetaEditor, lalu tekan **F7** untuk membuat file `.ex5`. [Kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
2. Tekan **Ctrl+R**. Pilih **Mercury_Vx**, simbol **XAUUSDm** atau **BTCUSDm**, dan timeframe **M3**. Pilih **Every tick based on real ticks** serta **Optimization → Disabled**. Untuk skenario serupa replay, setel deposit **US$1.000** dan leverage **1:100**. [Model tick MT5](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
3. Di **Inputs** gunakan `SignalModel = SUPER_AGGRESSIVE`. Untuk simbol lain atau pengaturan manual gunakan `SUPER_AGGRESSIVE_CUSTOM`. Pilih M1 atau M3 dan atur risiko simulator. Untuk meniru tes tambahan emas 20%, gunakan `EXHAUSTION_REVERSAL`, M1, lookback 16, SL 2,00 ATR, dan TP 0,80 kali SL. Profil v1.40 tetap tersedia lewat `RESEARCH_BY_SYMBOL`.
4. Di **Date → Custom period**, tentukan tanggal yang akan diuji. Untuk mereplikasi tes utama gunakan **1 Januari 2026–1 November 2026**. Untuk tes 1–20 tahun, pilih tanggal sesuai cakupan data tick simbol. Paket menyertakan konverter untuk arsip Bid/Ask. Detail impor ada di [panduan versi 1.40](https://github.com/edracode/HYPERION-OMEGA/blob/58dc6394d53be090340d8bce25d3d70744647dc6/Mercury-Vx/README.md#impor-riwayat). [Cakupan data di Tester](https://www.metatrader5.com/en/terminal/help/algotrading/test_preparation)
5. Klik **Start**, lalu baca `Daily50Targets`, `DaysAt50Pct` dan `Daily outcomes` di **Journal**. `PASS` memerlukan laba bersih positif, semua hari bertick mencapai +50%, dan sampel bawaan minimal 100 trade serta 20 hari. Hari tanpa transaksi yang memiliki tick tetap dihitung. CSV harian dan tahunan diaktifkan secara bawaan. Lokasi berkas tercatat di Journal.
