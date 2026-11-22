# Mercury Vx 1.20

Expert Advisor MQL5 untuk MetaTrader 5 desktop. Versi ini menyediakan **backtest dengan rentang tanggal bebas**, laporan tahunan, dan profil sinyal untuk emas, Bitcoin, serta simbol lainnya. Riwayat yang tersedia di Strategy Tester menentukan rentang data yang benar-benar dapat diuji.

## Pasang dan uji 1–20 tahun

1. Di MT5 klik **File → Open Data Folder**. Salin `Mercury_Vx.mq5` ke folder `MQL5/Experts` tempat versi lama dipasang, lalu timpa file lama. Buka di MetaEditor dan tekan **F7**. Kompilasi yang berhasil membuat ulang `Mercury_Vx.ex5`. [Dokumentasi kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
2. Buka **Strategy Tester** dengan **Ctrl+R**. Pilih **Mercury_Vx**, timeframe **M1**, **Optimization → Disabled**, dan mode **Every tick based on real ticks**. Mode visual bisa dimatikan agar tes panjang lebih mudah dijalankan. [Pengaturan Strategy Tester](https://www.metatrader5.com/en/terminal/help/algotrading/testing)
3. Pilih simbol yang mau diuji, misalnya **XAUUSDm**, **BTCUSDm**, atau **EURUSDm** di Exness Standard. Jalankan tes terpisah untuk tiap simbol. Gunakan `ExecutionMode = TESTER_ONLY`, `SignalModel = AUTO_BY_SYMBOL`, dan spesifikasi akun yang ingin disimulasikan. [Sufiks simbol Exness](https://get.exness.help/hc/en-us/articles/360014560220-Account-type-suffixes)
4. Pada **Date → Custom period**, tentukan tanggal awal dan akhir. Contoh tes setahun untuk data yang dipakai dalam replay di bawah adalah **1 November 2025 → 1 November 2026**. Untuk emas, pilih rentang 5, 10, atau 20 tahun jika sumber Anda memiliki tick yang diperlukan. Bitcoin diluncurkan pada 2009 dan perdagangan awalnya pada 2010, sehingga 20 tahun tick BTC aktual belum mungkin pada 2026. [Tanggal custom di MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing) · [Sejarah Bitcoin dari CME Group](https://www.cmegroup.com/articles/2025/celebrating-bitcoins-16th-birthday-a-look-at-achievements-in-the-crypto-space.html)
5. Klik **Start**. Di **Journal**, periksa `Mercury Vx 1.20` dan baris `Coverage`. Bandingkan `FirstTick` dan `LastTick` dengan tanggal yang dipilih, lalu lihat `FirstEntry` dan `LastExit`. MT5 juga menampilkan **History Quality** dalam laporan Backtest. MT5 bisa menghasilkan tick untuk bar yang riwayat tick aslinya kosong. [Cakupan dan data tester](https://www.metatrader5.com/en/terminal/help/algotrading/test_preparation) · [Tick asli dan sintetis](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)

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

## Hasil replay setahun

Replay lokal dari **1 November 2025 hingga akhir Oktober 2026** memakai **134.240.231 tick** Exness pada dua simbol, modal simulasi **USD 1.000**, lot minimum dan langkah lot **0,01**, dan batas drawdown **10%**. Margin disimulasikan 1:100. Spread memakai Bid/Ask yang direkam ditambah biaya sensitivitas sebesar 25% spread masuk. Komisi broker tambahan, swap, dan delay server tidak disimulasikan. [Data Exness](https://www.exness.com/tick-history/) · [Spesifikasi XAUUSD](https://get.exness.help/hc/en-us/articles/17854173039388-Commodities) · [Spesifikasi BTCUSD](https://get.exness.help/hc/en-us/articles/17854191888540-Cryptocurrencies)

| Simbol | Versi | Trade | Win rate | Hasil bersih | Drawdown maksimum |
|---|---|---:|---:|---:|---:|
| BTCUSDm | 1.10 | 352 | 35,51% | −USD 58,07 | 10,00% |
| BTCUSDm | 1.20 | 291 | 45,36% | −USD 41,34 | 4,36% |
| XAUUSDm | 1.10 | 262 | 30,15% | −USD 91,15 | 9,92% |
| XAUUSDm | 1.20 | 556 | 30,40% | −USD 74,21 | 9,94% |

**Kedua profil baru masih merugi.** Dalam tes terpisah Juli–Oktober 2026 dengan modal awal yang sama, hasilnya −USD 35,33 untuk BTCUSDm dan −USD 85,48 untuk XAUUSDm. Pada XAUUSDm, varian baru juga lebih rugi daripada versi lama di periode tersebut. EURUSDm dipakai untuk memeriksa pemilihan profil umum selama satu bulan. Sampelnya hanya 16 trade.

Paket berisi kode sumber MQL5, panduan, dan konverter Python. Pengujian lokal memeriksa pemilihan profil, replay setahun, agregasi laporan untuk 20 tahun dengan data sintetis, dan konversi arsip tick. Kompilasi MetaEditor dan backtest MT5 untuk rilis ini masih perlu diverifikasi. Bukti kinerja di atas belum mendukung pemakaian akun real atau klaim profitabilitas.
