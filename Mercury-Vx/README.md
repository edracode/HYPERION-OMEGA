# Mercury Vx 1.10

Mercury Vx adalah Expert Advisor untuk MetaTrader 5 desktop. EA membaca simbol yang dipilih di Strategy Tester atau pada chart. Pada akun Exness Standard, pilih **BTCUSDm** untuk mengulang pengujian revisi ini atau **XAUUSDm** untuk menguji emas. [Daftar sufiks simbol Exness](https://get.exness.help/hc/en-us/articles/360014560220-Account-type-suffixes)

## Perubahan versi 1.10

- Entri perlu sinyal searah pada M1 dan gabungan M3/M5. Filter spread bawaan membatasi spread hingga 20% dari jarak SL.
- Risiko bawaan turun ke 0,25% ekuitas per posisi dan batas rugi harian menjadi 2%. Batas drawdown kumulatif 10% memakai puncak ekuitas sejak awal tes. EA mengecilkan lot ketika mendekati batas. Jika batas tersentuh, EA mencoba menutup posisinya dan menghentikan entri sepanjang sisa tes. Harga eksekusi, gap, dan slippage dapat membuat batas terlewati.
- Journal mencatat laba dan rugi rata-rata, rasio aktual, profit factor, dan jumlah deal yang ditutup oleh SL, TP, atau alasan lainnya. Penutupan karena batas waktu dicatat sebagai permintaan yang diterima server. Jumlah deal dapat berbeda dari jumlah posisi karena eksekusi parsial.
- Kriteria optimasi **Custom max** menilai hasil bersih dan drawdown serta memberi penalti pada konfigurasi yang merugi atau memiliki sampel di bawah minimum.

### Replay pada tick publik Exness

Perbandingan menggunakan 12.351.223 tick Bid/Ask `BTCUSDm` dari November 2025 hingga Februari 2026, modal awal USD 1.000, lot minimum dan langkah lot 0,01, spread historis, serta simulasi margin 1:100. Simulasi lokal menutup posisi pada quote untuk SL dan penutupan waktu, serta pada harga target untuk TP. Komisi tambahan, penundaan, dan swap diset nol. Hasil dapat berbeda di Strategy Tester atau server akun Anda. [Riwayat tick Exness](https://www.exness.com/tick-history/) · [Spesifikasi BTCUSD](https://get.exness.help/hc/en-us/articles/17854191888540-Cryptocurrencies)

| Metrik | 1.00 bawaan | 1.10 bawaan |
|---|---:|---:|
| Trade ditutup | 2.696 | 376 |
| Win rate | 30,01% | 36,17% |
| Profit factor | 0,73 | 0,87 |
| Hasil bersih | −USD 866,96 | −USD 49,95 |
| Drawdown maksimum ekuitas | 86,70% | 9,94% |

Pada risiko 0,25% dengan batas drawdown kumulatif dimatikan untuk kedua versi, hasil rata-rata meningkat dari −0,217 R ke −0,141 R per trade pada replay ini. Satu R adalah risiko uang yang dihitung dari SL awal. Kedua versi masih merugi. Dengan bawaan 1.10, lot minimum tidak lagi masuk sisa anggaran risiko setelah 376 trade. Perubahan ini memperkecil kerugian dan target profit harian serta win rate awal belum tercapai.

## Cara pasang dan menjalankan backtest pertama

1. Ekstrak paket ZIP. Di MT5 desktop, pilih **File → Open Data Folder**. Salin `Mercury_Vx.mq5` ke folder **MQL5 → Experts**.
2. Tekan **F4** dari MT5 untuk membuka MetaEditor. Buka file tersebut, tekan **F7**, lalu periksa panel **Errors**. Kompilasi yang berhasil membuat `Mercury_Vx.ex5` di folder yang sama. Jika mengganti versi lama, timpa file `.mq5` saat menyalin agar MetaEditor membuat ulang `.ex5` di lokasi yang sama. [Dokumentasi kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
3. Kembali ke MT5 dan buka **Strategy Tester** dengan **Ctrl+R**. Pilih **Single** dan **Mercury_Vx**. Jika EA belum muncul, klik kanan **Expert Advisors** di Navigator lalu pilih **Refresh**.
4. Pilih simbol **BTCUSDm**, timeframe **M1**, dan mode **Every tick based on real ticks**. Untuk pembanding, gunakan rentang 1 November 2025 sampai 1 Maret 2026 dan modal USD 1.000 jika data tersedia untuk rentang tersebut. Gunakan pengaturan bawaan dari versi 1.10 dengan `ExecutionMode = TESTER_ONLY`. [Dokumentasi tick MT5](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
5. Klik **Start** dan pastikan ada baris `Mercury Vx 1.10` di **Journal**. Setelah selesai, lihat `Mercury Vx | Trades=`, `RealizedRewardRisk`, `Exit deals`, dan `Mercury Vx | Days`. Journal juga mencetak lokasi CSV harian di folder bersama **MetaQuotes → Terminal → Common → Files**.

Paket ini berisi kode sumber MQL5 dan panduan. Pengujian sintetis memeriksa filter arah, anggaran risiko, penghentian berdasarkan drawdown, dan penghitungan deal keluar. Replay pasar dijalankan pada simulator lokal. Kompilasi MetaEditor dan hasil Strategy Tester untuk versi ini masih perlu diverifikasi di MT5.

## Cara EA mengambil keputusan

- **4.096 variasi indikator** berasal dari 8 keluarga indikator × 128 periode (4–131 bar) × 4 timeframe (M1, M2, M3, M5). Keluarganya mencakup deviasi SMA, kemiringan regresi linear, RSI berbobot linear, momentum yang dinormalisasi dengan ATR, Stochastic %K, kanal Donchian, posisi harga terhadap Bollinger Bands, dan rasio efisiensi berarah.
- **1.536 kombinasi strategi** berasal dari 3 aturan (tren, breakout, pullback) × 128 periode × 4 timeframe. EA menggabungkan skor strategi, dengan bobot lebih besar pada periode yang lebih pendek. Seluruh indikator timeframe memakai bar yang sudah ditutup.
- Konfirmasi arah berasal dari perubahan harga tengah Bid/Ask selama kira-kira **5, 15, dan 30 detik**. Secara bawaan, EA mengevaluasi sinyal paling cepat sekali tiap **2 detik**, saat quote baru tiba.
- Ukuran lot mempertimbangkan risiko pada SL, lot minimum dan langkah lot broker, serta margin bebas. EA memeriksa spread sebelum membuka posisi dan memakai satu posisi per simbol. Setelah order terisi, EA memeriksa kembali batas risiko dan menyelaraskan TP berdasarkan harga isi order jika perlu.
- Jarak TP dirancang **3× jarak SL** dari harga masuk dan disesuaikan dengan ukuran tick. Komisi, slippage, dan penutupan karena batas waktu atau batas rugi memengaruhi rasio hasil yang terealisasi.

## Pengaturan bawaan

| Input | Nilai | Fungsi |
|---|---:|---|
| `ExecutionMode` | `TESTER_ONLY` | Pengaturan awal berjalan di Strategy Tester. `ENABLE_DEMO` atau `ENABLE_REAL` mengaktifkan mode chart sesuai jenis akun yang dipilih. |
| `RiskPerTradePct` | 0,25% | Batas risiko posisi berdasarkan ekuitas. EA menyisakan cadangan saat mengukur lot awal. |
| `DailyLossLimitPct` | 2,00% | Saat kondisi tercapai, EA mencoba menutup posisinya dan menghentikan entri sampai hari server berikutnya. Harga eksekusi dapat membuat hasil berbeda dari batas yang dihitung. |
| `MaxEquityDrawdownPct` | 10,00% | Batas penurunan dari puncak ekuitas. Nilai 0 mematikan batas ini untuk pembanding di Strategy Tester. |
| `MaxSpreadToRisk` | 0,20 | Rasio maksimum antara spread dan jarak SL dari harga masuk. |
| `MinimumTrendAlignment` | 0,15 | Syarat kesesuaian arah skor tren M1 dan gabungan M3/M5. |
| `CommissionPerLotRoundTrip` | 0 | Masukkan estimasi total biaya buka dan tutup per lot dalam mata uang akun jika tipe akun mengenakan komisi. Nilai ini dipakai untuk perhitungan lot. Biaya backtest mengikuti konfigurasi dan data tester. |
| `MaxHoldSeconds` | 180 | Penutupan dicoba ketika quote pertama setelah batas waktu tersedia. Isi 0 untuk mematikan batas waktu. |
| `CooldownSeconds` | 20 | Jeda sebelum entri kembali setelah posisi selesai. |
| `SessionStartHour` dan `SessionEndHour` | 0 dan 0 | Jam server broker. Nilai yang sama berarti sepanjang jam perdagangan yang tersedia. |

Pada mode chart, batas harian dan drawdown memakai ekuitas akun sehingga aktivitas lain di akun dapat ikut memengaruhinya. Puncak ekuitas dan status penghentian drawdown dari akun, simbol, dan Magic Number yang sama dimuat kembali ketika terminal dimulai ulang. Jalankan satu instance Mercury Vx untuk tiap simbol dan gunakan akun terpisah untuk menilai hasil EA secara mandiri.

## Membaca hasil

- **Win rate** memakai persentase trade profit dari total trade di laporan MT5. Ambang lulusnya **lebih dari 75%**. [Definisi statistik tester MQL5](https://www.mql5.com/en/docs/constants/environment_state/statistics)
- **Return harian** dihitung dari perubahan ekuitas dalam zona waktu server. Hari pertama memakai ekuitas pada tick pertama. Hari berikutnya memakai ekuitas terakhir hari yang sebelumnya teramati sebagai titik awal. CSV juga mencakup hari dengan tick dan tanpa trade, serta hari pertama dan terakhir yang bisa berupa hari parsial.
- **Targets=PASS** mensyaratkan setiap hari teramati mencapai **minimal +50%**, win rate **lebih dari 75%**, laba bersih positif, dan sampel bawaan setidaknya **100 trade dan 20 hari teramati**. Ambang tersebut adalah kriteria laporan. Kinerja aktual harus diukur dengan data pasar.
- Jika jumlah trade nol, periksa baris **Entry checks** pada Journal. `History` berarti data bar tertutup belum siap, `TickWindow` berarti sampel detik belum lengkap, `Signal` berarti skor di bawah ambang, `Spread` berarti biaya spread melewati filter, dan `SizeOrMargin` berarti lot atau margin belum memenuhi syarat. `Rejected` menghitung permintaan order yang ditolak dan kode penolakannya dicetak di Journal.
- Jika menguji periode panjang, periksa cakupan tick broker. MT5 dapat memakai tick sintetis ketika tick asli tidak tersedia untuk bar tertentu. Uji hasil pada periode lain yang belum digunakan untuk menyetel parameter. [Cara MT5 menangani kekosongan riwayat tick](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
