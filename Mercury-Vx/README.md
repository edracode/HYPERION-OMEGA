# Mercury Vx 1.30 — Riset backtest

Build ini mengukur tiga target yang diminta. **Belum ada konfigurasi yang lolos.** Gunakan branch riset ini untuk membandingkan exit dan membaca hasil Strategy Tester. Pengaturan bawaan tetap `ExecutionMode = TESTER_ONLY`.

## Hasil yang dilaporkan pengguna

Laporan BTCUSDm menunjukkan modal USD 1.000, 351 trade, 165 pemenang (47,01%), laba kotor USD 408,03, rugi kotor USD 485,49, dan hasil bersih −USD 77,46. Rasio laba rata-rata USD 2,47 terhadap besar rugi rata-rata USD 2,61 memberi risk:reward terealisasi sekitar **1:0,95**. History Quality tercatat 86%. Metrik itu menilai kelengkapan dan konsistensi data menit. [Definisi laporan MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing_report)

## Exit dan penilaian target

- **`PROFILE_TIMED`** memakai SL, TP, dan batas waktu profil. Ini pengaturan bawaan untuk pembanding dengan v1.20.
- **`BRACKETS_ONLY`** mematikan exit berbasis waktu. Posisi tetap memakai SL/TP. Batas rugi harian, batas drawdown, dan penutupan oleh tester pada akhir tes masih berlaku. Posisi bisa bertahan lebih lama dan melewati pergantian hari.
- Jarak harga TP direncanakan **tiga kali** jarak SL dan disesuaikan setelah pengisian order. Spread, slippage, swap, komisi, pembulatan ukuran tick, dan exit oleh batas risiko bisa mengubah rasio uang yang akhirnya tercatat.
- Journal mencatat **`Targets=PASS`** hanya jika win rate **≥75%**, rata-rata laba dibagi besar rata-rata rugi **≥3**, kenaikan ekuitas **≥50% pada setiap hari server yang memiliki tick data**, laba bersih positif, serta jumlah trade dan hari memenuhi minimum yang dipilih. Rasio baru dapat dihitung jika ada setidaknya satu trade untung dan satu trade rugi. Hari dengan tick tanpa trade tetap termasuk dalam pengukuran. Journal menampilkan hasil target dan statistik harian sekalipun `ExportDailyCsv=false`. Batas awal sampel adalah 100 trade dan 20 hari dengan tick.
- Untuk membandingkan dua mode, jalankan dua tes dengan simbol, tanggal, tick, biaya, modal, dan pengaturan risiko yang sama. Pilih **`BRACKETS_ONLY`** di tab **Inputs** untuk tes kedua. Baca `Targets`, `Daily equity` dan `Exit deals` di **Journal**. [Statistik yang dipakai dari Strategy Tester](https://www.mql5.com/en/docs/constants/environment_state/Statistics)

## Replay tick publik Exness

Replay lokal memakai **134.240.231 tick** dari November 2025 sampai Oktober 2026, dengan modal awal USD 1.000 pada setiap tes, lot minimum dan langkah lot 0,01, risiko per trade 0,25%, batas rugi harian 2%, batas drawdown ekuitas 10%, serta leverage simulasi 1:100. Replay menggunakan Bid/Ask historis dengan tambahan biaya sensitivitas 25% dari spread masuk dan memperhitungkannya dalam estimasi ukuran lot. Swap, delay, dan komisi broker di luar biaya sensitivitas tersebut tidak dimodelkan. Hasil replay terpisah dari angka pada foto MT5. [Sumber tick Exness](https://www.exness.com/tick-history/)

| Simbol | Exit | Trade | Win rate | Risk:reward terealisasi | Laba bersih | Hari ≥50% |
|---|---|---:|---:|---:|---:|---:|
| BTCUSDm | Batas waktu profil | 287 | 45,99% | 1:0,96 | −USD 34,09 | 0/363 |
| BTCUSDm | Tanpa batas waktu | 235 | 20,43% | 1:2,77 | −USD 91,25 | 0/363 |
| XAUUSDm | Batas waktu profil | 503 | 30,02% | 1:2,05 | −USD 78,44 | 0/310 |
| XAUUSDm | Tanpa batas waktu | 180 | 18,33% | 1:2,87 | −USD 88,74 | 0/310 |

Sebanyak 18 konfigurasi baru dari tiga keluarga sinyal (breakout tren, pullback tren, dan breakout sesudah kompresi) ikut diuji. Pemilihan memakai November 2025–April 2026 dengan minimum 100 trade. Parameter terpilih lalu dibekukan untuk Mei–Oktober 2026 dan data terpisah Juli–Oktober 2024. Kandidat BTC terpilih rugi USD 96,31 pada Mei–Oktober 2026. Kandidat XAU terpilih menghasilkan USD 30,42 pada data pemilihan, memiliki nol transaksi pada Mei–Oktober 2026 dengan batas lot dan spread yang sama, serta rugi USD 96,93 pada data Juli–Oktober 2024. Tidak ada varian baru yang memenuhi tiga target. [Pengujian forward di MT5](https://www.metatrader5.com/en/automated-trading/strategy-tester)

Bagian logika target, pengelompokan hari, exit profil, serta penyelarasan harga TP 1:3 lulus uji lokal. Build ini masih perlu dikompilasi dengan MetaEditor dan diuji di Strategy Tester MT5 untuk memverifikasi eksekusi native.

## Pasang dan uji 1–20 tahun

1. Di MT5 klik **File → Open Data Folder**. Salin `Mercury_Vx.mq5` ke folder `MQL5/Experts` tempat versi lama dipasang, lalu timpa file lama. Buka di MetaEditor dan tekan **F7**. Kompilasi yang berhasil membuat ulang `Mercury_Vx.ex5`. [Dokumentasi kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
2. Buka **Strategy Tester** dengan **Ctrl+R**. Pilih **Mercury_Vx**, timeframe **M1**, **Optimization → Disabled**, dan mode **Every tick based on real ticks**. Mode visual bisa dimatikan agar tes panjang lebih mudah dijalankan. [Pengaturan Strategy Tester](https://www.metatrader5.com/en/terminal/help/algotrading/testing)
3. Pilih simbol yang mau diuji, misalnya **XAUUSDm**, **BTCUSDm**, atau **EURUSDm** di Exness Standard. Jalankan tes terpisah untuk tiap simbol. Gunakan `ExecutionMode = TESTER_ONLY`, `SignalModel = AUTO_BY_SYMBOL`, `ExitPolicy = PROFILE_TIMED`, dan spesifikasi akun yang ingin disimulasikan. [Sufiks simbol Exness](https://get.exness.help/hc/en-us/articles/360014560220-Account-type-suffixes)
4. Pada **Date → Custom period**, tentukan tanggal awal dan akhir. Contoh tes setahun untuk data yang dipakai dalam replay di bawah adalah **1 November 2025 → 1 November 2026**. Untuk emas, pilih rentang 5, 10, atau 20 tahun jika sumber Anda memiliki tick yang diperlukan. Bitcoin diluncurkan pada 2009 dan perdagangan awalnya pada 2010, sehingga 20 tahun tick BTC aktual belum mungkin pada 2026. [Tanggal custom di MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing) · [Sejarah Bitcoin dari CME Group](https://www.cmegroup.com/articles/2025/celebrating-bitcoins-16th-birthday-a-look-at-achievements-in-the-crypto-space.html)
5. Klik **Start**. Di **Journal**, periksa `Mercury Vx 1.30` dan baris `Coverage`. Bandingkan `FirstTick` dan `LastTick` dengan tanggal yang dipilih, lalu lihat `FirstEntry` dan `LastExit`. MT5 juga menampilkan **History Quality** dalam laporan Backtest. MT5 bisa menghasilkan tick untuk bar yang riwayat tick aslinya kosong. [Cakupan dan data tester](https://www.metatrader5.com/en/terminal/help/algotrading/test_preparation) · [Tick asli dan sintetis](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)

## Saat grafik perdagangan berakhir lebih awal

Batas drawdown kumulatif bawaan **10%** bisa menghentikan entri sebelum tanggal akhir. Di dekat batas, lot minimum broker juga bisa lebih besar dari sisa anggaran risiko. Tanggal di ujung grafik harus dibaca bersama `LastTick` dan `LastExit` di Journal. `MinLotAboveDrawdownBudget` menunjukkan jumlah kandidat entri yang gagal pada batas tersebut.

- `ExportAnnualCsv = true` menulis CSV dengan satu baris per tahun server yang memiliki tick. Kolomnya memuat cakupan tick, jumlah deal masuk/keluar, ekuitas awal/akhir, perubahan ekuitas, return, dan drawdown ekuitas di tahun itu. Tahun pertama dan terakhir bisa parsial. Deal dapat berjumlah lebih banyak daripada posisi jika ada pengisian parsial.
- `ExportDailyCsv = false` adalah bawaan. Batas rugi harian tetap dihitung sebagai bagian dari pengendalian risiko.
- Pada **Strategy Tester**, jalankan pembanding dengan `MaxEquityDrawdownPct = 0` jika Anda ingin mengukur sinyal tanpa penghentian drawdown kumulatif. Batas risiko per posisi, rugi harian, dan lot minimum tetap berlaku. Jika ekuitas menyusut, batas lot minimum masih bisa mengurangi aktivitas. Simpan hasil tes dengan batas 10% dan 0% secara terpisah.

Lokasi laporan dicetak di Journal dan biasanya berada di **MetaQuotes → Terminal → Common → Files**.

## Jika server belum menyediakan tick yang dibutuhkan

Cari Bid/Ask historis dari sumber yang sesuai. Untuk replay setahun ini, file bulanan tersedia di arsip publik Exness. Cakupan di arsip publik dapat berbeda dari server akun Anda. [Arsip tick publik Exness](https://www.exness.com/tick-history/) · [Penjelasan sumber riwayat tick Exness](https://get.exness.help/hc/id/articles/360021547851-Riwayat-tick)

1. Di **Market Watch → Symbols → Create Custom Symbol**, buat simbol dengan nama unik seperti `XAUUSDm_HIST`. Salin spesifikasi dari simbol broker yang sesuai. Cocokkan **Digits**, ukuran tick, kontrak, lot minimum, langkah lot, mata uang, margin, dan sesi trading sebelum impor. [Custom Symbol MT5](https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments)
2. Untuk arsip Exness, jalankan konverter yang disertakan dari folder hasil ekstrak dengan Python 3. Contoh untuk emas dengan 3 digit:

   ```powershell
   py .\convert_ticks_mt5.py .\Exness_XAUUSDm_2026_10.zip --digits 3
   ```

   Untuk BTC yang dikutip dengan 2 digit, gunakan `--digits 2`. Cocokkan angka dengan spesifikasi simbol Anda. Konverter menghasilkan file `_ticks.csv` dan `_m1.csv` dengan pemisah tab dalam folder `mt5_import`. Data teks mengikuti format impor MT5 dan waktunya tetap UTC. Untuk file sumber lain, sesuaikan data dengan format Bars dan Ticks di dokumentasi MT5. [Format impor harga MT5](https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments)
3. Di **Symbols → Bars**, impor file `_m1.csv` sebagai M1. Di **Symbols → Ticks**, impor `_ticks.csv`. Pilih **Tab** sebagai pemisah dan lewati satu baris header jika diperlukan. Periksa pratinjau agar baris data pertama tampil dan gunakan **Shift = 0** bila riwayat serta sesi simbol Anda memakai UTC. Ulangi per bulan secara berurutan, kemudian pilih custom symbol itu di Strategy Tester. [Impor riwayat ke custom symbol](https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments)

Untuk uji emas hingga 20 tahun, dokumentasi dukascopy-node mencantumkan tick XAU/USD sejak Mei 2003. Pilih **tick** dan **CSV**, unduh per bagian, lalu gunakan `py .\convert_ticks_mt5.py .\file.csv --symbol XAUUSD --digits 3` jika file memiliki kolom `timestamp`, `bidPrice`, dan `askPrice`. Periksa celah riwayat dan gunakan nama custom symbol seperti `XAUUSD_DUKA` agar sumber feed tercatat. Spread dan hasil dari feed ini dapat berbeda dari Exness. [Cakupan XAU/USD Dukascopy](https://www.dukascopy-node.app/instrument/xauusd) · [Unduh tick Bid/Ask](https://www.dukascopy-node.app/downloading-tick-data)

## Profil sinyal dan risiko

| Profil | Cara memilih | Keluar berbasis waktu |
|---|---|---:|
| `XAU_MEAN_REVERSION` | Otomatis untuk XAU/USD. Menilai jarak terhadap rata-rata M1 dan tanda awal pembalikan. | 12 menit |
| `BTC_WICK_RECLAIM` | Otomatis untuk BTC/USD. Menilai penolakan harga setelah menembus range 48 bar M1. | 5 menit |
| `LEGACY_MICRO` | Otomatis untuk simbol lain seperti EURUSD atau dipilih manual untuk membandingkan v1.10. Menggunakan RSI, ATR, momentum tick, dan model indikator versi sebelumnya. | 3 menit secara bawaan |

`AUTO_BY_SYMBOL` memakai mata uang dasar dan mata uang profit dari spesifikasi, jadi nama bersufiks maupun custom symbol yang spesifikasinya disalin dapat memakai profil yang sesuai. Profil emas dan BTC menilai bar M1 selesai dan memeriksa entri pada tick pertama bar berikutnya. Input `MaxHoldSeconds`, `StopAtrMultiple` dan `MaxSpreadToRisk` mengatur profil lama. Profil emas dan BTC memakai parameter tetap yang dibekukan untuk pengujian ini.

SL/TP dirancang dengan jarak harga **1:3**. Spread, slippage, komisi, dan exit lebih awal bisa mengubah rasio hasil aktual. Risiko bawaan **0,25% per posisi**, batas rugi harian **2%**, dan batas drawdown **10%**. Lot dihitung dari spesifikasi simbol dan anggaran risiko yang tersisa. Eksekusi pada harga yang tersedia dapat membuat batas terlewati.

