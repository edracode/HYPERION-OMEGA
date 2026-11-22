# Mercury Vx 1.40 — Riset MT5

Build ini menambahkan profil breakout setelah kompresi untuk **XAUUSDm M15** dan **BTCUSDm H1**. Kedua profil rugi pada replay utama dengan modal simulasi USD 1.000. Hasil emas membaik pada simulasi USD 10.000 di 2026 dan kembali rugi pada data 2024. Profil baru tersedia di Strategy Tester dan akun demo.

## Hasil di luar periode pemilihan

Replay memeriksa 158.436.857 tick Bid/Ask dari [arsip publik Exness](https://www.exness.com/tick-history/) selama Juli–Oktober 2024 dan Januari–Oktober 2026. Modal awal tiap baris USD 1.000. Risk:reward terealisasi adalah perbandingan besar rugi rata-rata terhadap laba rata-rata setelah biaya simulasi.

| Simbol | Periode | Trade | Win rate | Laba bersih | Profit factor | Drawdown ekuitas | Risk:reward terealisasi |
|---|---|---:|---:|---:|---:|---:|---:|
| XAUUSDm | Jul–Okt 2024 | 102 | 26,47% | −USD 5,96 | 0,99 | 9,85% | 1:2,74 |
| XAUUSDm | Jan–Jun 2026 | 4 | 0,00% | −USD 25,75 | 0,00 | 3,08% | — |
| XAUUSDm | Jul–Okt 2026 | 2 | 50,00% | +USD 11,92 | 2,86 | 1,00% | 1:2,86 |
| XAUUSDm | Jan–Okt 2026 | 6 | 16,67% | −USD 13,83 | 0,57 | 4,07% | 1:2,85 |
| BTCUSDm | Jul–Okt 2024 | 81 | 25,93% | −USD 0,41 | 1,00 | 5,44% | 1:2,85 |
| BTCUSDm | Jan–Jun 2026 | 60 | 20,00% | −USD 74,78 | 0,69 | 9,83% | 1:2,76 |
| BTCUSDm | Jul–Okt 2026 | 74 | 29,73% | +USD 39,89 | 1,15 | 9,87% | 1:2,72 |
| BTCUSDm | Jan–Okt 2026 | 61 | 19,67% | −USD 76,11 | 0,69 | 9,96% | 1:2,80 |

Tes Jan–Okt meneruskan ekuitas, posisi, dan batas drawdown sepanjang periode. Tes subperiode masing-masing mulai dari USD 1.000. Tidak ada hari yang mencapai 50% pada tes-tes ini. Hari terbaik pada tes Jan–Okt 2026 adalah **1,89%** untuk emas dan **1,92%** untuk Bitcoin.

### Pengaruh lot minimum pada emas

Pada Jan–Okt 2026, ada 666 peluang entri emas yang tertahan karena lot 0,01 memerlukan anggaran risiko di atas batas simulasi USD 1.000. Dengan parameter sinyal dan persentase risiko tetap, skenario ukuran akun memberi hasil berikut.

| Modal simulasi | Periode XAUUSDm | Trade | Win rate | Laba bersih | Profit factor | Drawdown ekuitas |
|---|---|---:|---:|---:|---:|---:|
| USD 10.000 | Jan–Okt 2026 | 71 | 33,80% | +USD 1.461,33 (+14,61%) | 1,49 | 9,96% |
| USD 10.000 | Jan–Okt 2026, biaya stres lebih tinggi | 72 | 33,33% | +USD 1.418,80 (+14,19%) | 1,48 | 9,99% |
| USD 10.000 | Jan–Okt 2024 | 40 | 20,00% | −USD 797,60 (−7,98%) | 0,61 | 9,99% |

Pada skenario emas USD 10.000 sepanjang Jan–Okt 2026, risk:reward terealisasi **1:2,93**, kenaikan hari terbaik **6,15%**, dan **0/259** hari mencapai 50%. Simulasi USD 10.000 ditambahkan setelah melihat kendala ukuran lot pada tes dasar. Data Jan–Jun 2024 baru dimuat untuk memeriksa sensitivitas tersebut, dengan parameter sinyal dan modal simulasi sudah ditetapkan. Bitcoin masih rugi **USD 535,96 (−5,36%)** pada Jan–Okt 2026 dengan USD 10.000. Angka selengkapnya ada di [hasil_replay.csv](hasil_replay.csv).

### Metode dan batas model

- Penyaringan mencakup 864 konfigurasi per simbol dari enam keluarga sinyal pada M5, M15, M30, dan H1. Jan–Jun dan Jul–Des 2025 masing-masing harus memiliki ≥25 trade, laba bersih ≥USD 8, profit factor ≥1,08 dan drawdown ≤11%. Minimal separuh parameter tetangga dengan ≥15 trade per bagian juga harus untung di kedua bagian. Satu kandidat per simbol dikunci sebelum replay tick periode lain.
- Bar dibangun dari Bid. Sinyal memakai bar yang sudah selesai. Entri memakai tick pertama pada bar berikutnya dan exit memakai sisi Bid/Ask sesuai arah posisi. Tiga file BTCUSDm dalam periode pengembangan berisi blok waktu yang tidak berurutan. Seluruh baris dengan harga valid diurutkan berdasarkan milidetik dan disertakan sebelum agregasi.
- Replay menggunakan lot minimum dan langkah lot 0,01, leverage simulasi 1:100, risiko 0,75% per posisi sebelum cadangan ukuran lot, batas rugi ekuitas harian 2%, dan batas drawdown ekuitas 10%. Replay menambahkan biaya sebesar 0,5 × spread masuk di atas Bid/Ask historis. Tes stres memakai 1,0 × spread. Biaya inap dimodelkan sebesar 0,035 R per pergantian hari UTC. Biaya broker, margin historis, stop level, swap, dan delay di MT5 dapat berbeda dari asumsi ini. Gap harga dapat melampaui batas rugi.
- Pengujian C++ memeriksa aturan sinyal yang sama dengan EA, konfigurasi, harga TP, dan penilaian target. File .mq5 masih perlu dikompilasi di MetaEditor. Replay lokal dan Strategy Tester memakai mesin eksekusi yang berbeda. [Dokumentasi testing MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing)

## Pasang dan backtest 1–20 tahun

1. Ekstrak `Mercury_Vx_MT5.zip`. Di MT5 klik **File → Open Data Folder**. Salin `Mercury_Vx.mq5` ke `MQL5/Experts/Advisors` jika versi lama ada di sana. Buka file di MetaEditor lalu tekan **F7** agar `Mercury_Vx.ex5` dibuat. [Kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
2. Tekan **Ctrl+R**. Pilih **Mercury_Vx** dan simbol **XAUUSDm** atau **BTCUSDm**. Setel **Optimization → Disabled**, model **Every tick based on real ticks**, dan matikan visualisasi untuk tes panjang. Gunakan timeframe Tester **M15** untuk XAUUSDm atau **H1** untuk BTCUSDm. [Model tick MT5](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
3. Pada tab **Inputs**, gunakan **`ExecutionMode = TESTER_ONLY`**, **`SignalModel = RESEARCH_BY_SYMBOL`**, dan **`ExitPolicy = PROFILE_TIMED`**. Untuk simbol lain, gunakan **`RESEARCH_CUSTOM`** dengan timeframe M5, M15, M30, atau H1. Profil membaca spesifikasi simbol broker. Hasil pada pair lain belum diukur dalam riset ini.
4. Pilih **Date → Custom period**. Contoh tes setahun **1 November 2025–1 November 2026**. Rentang 5, 10, atau 20 tahun bergantung pada riwayat simbol di broker atau impor Anda. Bitcoin diluncurkan pada 2009 dan perdagangan awalnya pada 2010. [Strategy Tester MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing) · [Riwayat awal Bitcoin](https://www.cmegroup.com/articles/2025/celebrating-bitcoins-16th-birthday-a-look-at-achievements-in-the-crypto-space.html)
5. Klik **Start**. Di **Journal**, cari `Mercury Vx 1.40`, lalu `Coverage`, `Targets`, `Daily equity` dan `MinLotAboveRiskBudget`. Bandingkan `FirstTick` dan `LastTick` dengan tanggal yang diminta. `Targets=PASS` memerlukan laba bersih positif, minimal 100 trade dan 20 hari dengan tick pada input bawaan, win rate ≥75%, risk:reward terealisasi ≥1:3, dan kenaikan ekuitas ≥50% pada setiap hari yang memiliki tick. [Laporan MT5](https://www.metatrader5.com/en/terminal/help/algotrading/testing_report)

Profil XAU otomatis mencari breakout long setelah kompresi 18 bar M15 dengan SL 1,50 ATR. Profil BTC mencari breakout long atau short setelah kompresi 32 bar H1 dengan SL 1,00 ATR. TP bawaan direncanakan **1:3**, batas waktu posisi 48 jam, dan batas spread 15% dari jarak SL. Biaya dan penutupan sesuai batas waktu atau batas risiko dapat mengubah rasio terealisasi. **`AUTO_BY_SYMBOL`** memanggil profil M1 v1.30 untuk pembanding. **`BRACKETS_ONLY`** mematikan exit waktu.

`ExportAnnualCsv = true` menulis statistik tiap tahun server yang memiliki tick. `ExportDailyCsv = true` menambahkan statistik harian. Folder output dicetak di Journal. Jika muncul pesan `cannot generate history data, check disk space`, cek ruang bebas drive data MT5 dan pastikan riwayat tick tersedia untuk tanggal tersebut.

## Impor riwayat

Gunakan [arsip Exness](https://www.exness.com/tick-history/) atau sumber Bid/Ask yang sesuai. Cakupan arsip publik bisa berbeda dari server akun Anda. Dokumentasi data Dukascopy mencantumkan tick XAU/USD sejak Mei 2003. Feed serta biaya eksekusi antar sumber dapat berbeda. [Cakupan XAU/USD Dukascopy](https://www.dukascopy-node.app/instrument/xauusd)

1. Buka **Market Watch → Symbols → Create Custom Symbol**. Salin digit, ukuran tick, kontrak, lot, margin, dan sesi dari simbol asal. Beri nama seperti `XAUUSDm_HIST`.
2. Dari folder hasil ekstrak, jalankan konverter dengan Python 3. Contoh untuk emas dengan tiga digit.

   ```powershell
   py .\convert_ticks_mt5.py .\Exness_XAUUSDm_2026_10.zip --digits 3
   ```

   Sesuaikan `--digits` dengan simbol. Untuk CSV dengan kolom `timestamp`, `bidPrice` dan `askPrice`, sertakan `--symbol XAUUSD --digits 3`. Konverter menulis file `_m1.csv` dan `_ticks.csv` dalam folder `mt5_import`.
3. Impor `_m1.csv` ke tab **Bars** sebagai M1 dan `_ticks.csv` ke tab **Ticks**. Gunakan pemisah **Tab** dan lewati satu baris header bila perlu. Gunakan **Shift 0** bila feed dan sesi simbol sama-sama UTC. Ulangi per bulan, lalu pilih custom symbol itu di Strategy Tester. [Custom Symbol MT5](https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments)
