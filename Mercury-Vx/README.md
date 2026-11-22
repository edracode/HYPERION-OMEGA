# Mercury Vx

Mercury Vx adalah Expert Advisor untuk MetaTrader 5 desktop. EA membaca simbol yang dipilih di Strategy Tester atau pada chart. Untuk akun Exness Standard dengan simbol emas bersufiks, pilih **XAUUSDm**. [Daftar sufiks simbol Exness](https://get.exness.help/hc/en-us/articles/360014560220-Account-type-suffixes)

## Cara pasang dan menjalankan backtest pertama

1. Ekstrak paket ZIP. Di MT5 desktop, pilih **File → Open Data Folder**. Salin `Mercury_Vx.mq5` ke folder **MQL5 → Experts**.
2. Tekan **F4** dari MT5 untuk membuka MetaEditor. Buka file tersebut, tekan **F7**, lalu periksa panel **Errors**. Kompilasi yang berhasil membuat `Mercury_Vx.ex5` di folder yang sama. [Dokumentasi kompilasi MQL5](https://www.mql5.com/en/docs/runtime)
3. Kembali ke MT5 dan buka **Strategy Tester** dengan **Ctrl+R**. Pilih **Single** dan **Mercury_Vx**. Jika EA belum muncul, klik kanan **Expert Advisors** di Navigator lalu pilih **Refresh**.
4. Pilih simbol **XAUUSDm**, timeframe **M1**, mode **Every tick based on real ticks**, dan rentang awal 1–3 bulan yang tersedia di server Exness Anda. Gunakan mata uang, saldo, leverage, dan biaya yang sesuai dengan akun yang ingin disimulasikan. Jalankan dengan pengaturan bawaan `ExecutionMode = TESTER_ONLY`. [Dokumentasi tick MT5](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
5. Klik **Start**. Setelah selesai, baca **Backtest** dan **Journal**. Cari baris `Mercury Vx | Trades=` dan `Mercury Vx | Days`. Journal juga mencetak lokasi CSV harian di folder bersama **MetaQuotes → Terminal → Common → Files**.

Paket ini berisi kode sumber MQL5 dan panduan. Logika telah diperiksa dengan simulasi sintetis. Kompilasi MetaEditor, kompatibilitas eksekusi Exness, dan kinerja dengan tick pasar masih perlu diverifikasi di MT5.

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
| `RiskPerTradePct` | 0,50% | Batas risiko posisi berdasarkan ekuitas. EA menyisakan cadangan saat mengukur lot awal. |
| `DailyLossLimitPct` | 3,00% | Saat kondisi tercapai, EA mencoba menutup posisinya dan menghentikan entri sampai hari server berikutnya. Harga eksekusi dapat membuat hasil berbeda dari batas yang dihitung. |
| `CommissionPerLotRoundTrip` | 0 | Masukkan estimasi total biaya buka dan tutup per lot dalam mata uang akun jika tipe akun mengenakan komisi. Nilai ini dipakai untuk perhitungan lot. Biaya backtest mengikuti konfigurasi dan data tester. |
| `MaxHoldSeconds` | 180 | Penutupan dicoba ketika quote pertama setelah batas waktu tersedia. Isi 0 untuk mematikan batas waktu. |
| `CooldownSeconds` | 20 | Jeda sebelum entri kembali setelah posisi selesai. |
| `SessionStartHour` dan `SessionEndHour` | 0 dan 0 | Jam server broker. Nilai yang sama berarti sepanjang jam perdagangan yang tersedia. |

Pada mode chart, batas harian memakai ekuitas akun dan dapat ikut terpengaruh oleh aktivitas lain di akun tersebut. Batas tersimpan selama hari server yang sama. Jalankan satu instance Mercury Vx untuk tiap simbol dan gunakan akun terpisah untuk menilai hasil EA secara mandiri.

## Membaca hasil

- **Win rate** memakai persentase trade profit dari total trade di laporan MT5. Ambang lulusnya **lebih dari 75%**. [Definisi statistik tester MQL5](https://www.mql5.com/en/docs/constants/environment_state/statistics)
- **Return harian** dihitung dari perubahan ekuitas dalam zona waktu server. Hari pertama memakai ekuitas pada tick pertama. Hari berikutnya memakai ekuitas terakhir hari yang sebelumnya teramati sebagai titik awal. CSV juga mencakup hari dengan tick dan tanpa trade, serta hari pertama dan terakhir yang bisa berupa hari parsial.
- **Targets=PASS** mensyaratkan setiap hari teramati mencapai **minimal +50%**, win rate **lebih dari 75%**, dan sampel bawaan setidaknya **100 trade dan 20 hari teramati**. Ambang tersebut adalah kriteria laporan. Kinerja aktual harus diukur dengan data pasar.
- Jika jumlah trade nol, periksa baris **Entry checks** pada Journal. `History` berarti data bar tertutup belum siap, `TickWindow` berarti sampel detik belum lengkap, `Signal` berarti skor di bawah ambang, `Spread` berarti biaya spread melewati filter, dan `SizeOrMargin` berarti lot atau margin belum memenuhi syarat. `Rejected` menghitung permintaan order yang ditolak dan kode penolakannya dicetak di Journal.
- Jika menguji periode panjang, periksa cakupan tick broker. MT5 dapat memakai tick sintetis ketika tick asli tidak tersedia untuk bar tertentu. Uji hasil pada periode lain yang belum digunakan untuk menyetel parameter. [Cara MT5 menangani kekosongan riwayat tick](https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation)
