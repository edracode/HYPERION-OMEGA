# VeloxAurkaeon Trading untuk MT5 Strategy Tester

Port backtest dari **v0.4.0.dev36** pada commit `3dd88a03c44de0b003ec7f175405ad9da7738d90`. V43 adalah audit acceptance untuk checkpoint tersebut. EA berjalan di Strategy Tester desktop MT5 dan menyimulasikan transaksi dalam ledger Velox. Hasil transaksi, ekuitas, dan statistik ada di berkas CSV. Tab Results standar MT5 tidak menampilkan transaksi dari ledger internal.

## Mulai backtest 20 tahun

1. Di MT5 desktop, buka **File → Open Data Folder**. Salin folder `MQL5/Experts/VeloxAurkaeon` ke `MQL5/Experts`. Jika paket berisi `VeloxAurkaeonBacktest.ex5`, MT5 bisa memuat berkas itu langsung. Untuk sumber `.mq5`, buka **MetaEditor** dengan **F4**, buka EA, lalu tekan **F7**.
2. Buka **Strategy Tester** dengan **Ctrl+R**. Pilih **VeloxAurkaeonBacktest**, simbol **XAUUSD** dan timeframe **H1** untuk EMA. Pilih satu kali uji dan masukkan tanggal, misalnya **22 November 2006 hingga 22 November 2026**. Setelan awal berada di `MQL5/Profiles/Tester`. Gunakan **Load** di tab Inputs untuk memuat preset.
3. Untuk uji penelusuran EMA, pilih `XAUUSD` atau nama simbol broker yang sesuai, misalnya `XAUUSDm` di Exness. Sejak v1.01, konfigurasi bawaan sudah memakai `DISCOVERY_ASSUME_CLEAR` sehingga preset bersifat opsional. Asumsi bahwa semua sesi lolos filter berita muncul di Journal dan ringkasan CSV. Pilih `ATTESTED_CLEAR` jika Anda sudah memeriksa clearance untuk data tersebut. `REQUIRE_NEWS_CLEARANCE` menghentikan inisialisasi saat data perlu diperiksa. Setel `InpServerUtcOffsetMinutes` sesuai sumber data. Untuk server dengan perubahan offset DST sepanjang sejarah, gunakan impor CSV dengan timestamp UTC yang telah diverifikasi. EURUSD dan USDJPY London memerlukan data tick yang waktunya bisa dipetakan ke UTC.
4. Untuk London, pilih **EURUSD** atau **USDJPY**, **M1**, dan **Every tick based on real ticks**. Muat `Velox-Dev36-London-Discovery.set`. Periksa cakupan di kolom `coverage`. Untuk XAUUSD, mode bar memakai OHLC bid dan satu spread per bar, termasuk bila model tester menggunakan real ticks.
5. Buka direktori **Terminal/Common/Files** untuk membaca `*_summary.csv`, `*_trades.csv`, `*_equity.csv`, `*_rejections.csv` atau `*_london.csv`. Gunakan prefix unik per percobaan. Periksa tanggal bar pertama dan terakhir, jumlah bar, serta status run. Rentang yang tersedia mengikuti data terminal. MT5 dapat membangkitkan tick ketika riwayat real tick suatu menit tidak tersedia.

## Sumber data dan biaya

| Mode | Masukan dan simulasi |
| --- | --- |
| `MT5_BAR_PROXY` | XAUUSD. OHLC bid MT5, spread per bar, kontrak tetap dan swap nol. Ini mode penelusuran. EA memproses bar ketika bar berikutnya sudah terlihat. `InpUseTerminalQuoteGrid` bawaan menyesuaikan grid harga bila terminal memakai pecahan tick kontrak. Nilai kas per satuan perubahan harga dan jarak slippage tetap sama. |
| `VELOX_OHLC_CSV` | XAUUSD. Replay semua bar di file yang dipilih. Tanggal Strategy Tester hanya memicu EA. Potong data dan tambahkan bar warmup sebelum periode pengujian di file input. `InpWarmupBars` menentukan awal eligibility transaksi. |
| `MT5_LONDON_TICKS` | EURUSD atau USDJPY, satu simbol per run. Rentang bid pukul 11.30–13.00 London, trigger BUY dengan ask atau SELL dengan bid, cutoff 15.30, stop di ujung rentang lawan atau keluar pukul 16.30. Output per sesi untuk BUY, SELL dan BOTH, termasuk pips setelah biaya eksplisit. Run penelusuran memakai batas holdout yang dipilih pada input. |

Untuk XAUUSD, nilai awal kontrak sama dengan kontrak contoh Dev36, termasuk modal 10.000 USD, risk per trade 0,25%, daily loss 1%, weekly loss 2,5%, drawdown 5%, komisi 7 USD per lot dan slippage dua tick. Gunakan kontrak yang sesuai dengan dataset untuk menafsirkan hasil historis. Akun MT5 dalam tester dan parameter deposit tester berdiri terpisah dari ledger internal. Gunakan `InpInitialEquity` untuk menentukan modal ledger.

Untuk replay bid/ask, simpan CSV ke `Terminal/Common/Files`. Siapkan file berisi `close_time,open,high,low,close,spread,swap_cash_per_lot`, dengan kolom opsional `ask_open,ask_high,ask_low,ask_close,sell_swap_cash_per_lot`. Nilai spread berbentuk selisih harga. Swap berbentuk biaya kas per lot. Waktu `close_time` wajib menyertakan zona waktu.

```bash
python tools/prepare_replay.py bars.csv xauusd_replay.csv --interval 3600
```

Pilih `InpSource=VELOX_OHLC_CSV`, isi `InpCsv`, dan aktifkan `InpConfirmHistoricalCosts` setelah memeriksa data. Pakai interval 3600 untuk H1, 14400 untuk H4 atau 86400 untuk D1 sesuai strategi. Untuk smoke test, salin `reference/rsi21_SYNTHETIC_replay.csv` ke Common/Files dan gunakan preset RSI. Berkas itu berisi data sintetis dari checkpoint.

## Cakupan konversi

| Sumber Dev36 | Implementasi |
| --- | --- |
| `example-ema` | XAUUSD H1, BUY-only, EMA10/30, ATR14 × 2, TP 2R, weekday UTC, crossover bar tertutup. Strategi PAPER ini memakai jadwal sampling next-open dari adapter OHLC EA. PAPER API aslinya menerima quote dan panjang histori dari pemanggil kapan saja. |
| `experiment-donchian` | XAUUSD D1, BUY close lebih tinggi dari 25 high sebelumnya, SL tiga low sebelumnya, TP 2R, filter regime. Default registry tetap disabled. EA menyediakan pengujian eksperimen ini saat dipilih eksplisit. |
| `lab-rsi21`, `lab-adx18_burst`, `lab-supertrend15_3` | Varian analisis XAUUSD, diuji secara terpisah dengan timeframe dan parameter asli. |
| Lima kebijakan `quant-*` | Analisis H4. Dua window yang sudah ditetapkan untuk tiap keluarga. Trading digerakkan oleh sinyal bar tertutup dan proteksi 2 ATR. |
| London range di `research_oos_dev30.py` | Mesin sesi dan pemicu London disalin untuk replay tick. Pemilihan bergulir 15/20 sesi, bootstrap, holdout frozen dan validasi lintas instrumen tetap tersedia di arsip Python Dev36. |
| 21 kandidat `tbd-*` | ID, status, file asal, dan catatan aturan tercatat di `reference/Strategy_Registry_dev36.csv`. Dev36 menandai semuanya **Awaiting Clarification**, tanpa plugin trading siap pakai. |
| API, Android, SQLite, MOCK lifecycle, Saxo/OANDA, staging | Komponen tersebut tersedia di proyek referensi Dev36. EA ini menggunakan ledger backtest single-symbol dan port algoritme historis. Ia tidak mengirim order, menjalankan API, atau mengakses broker. |

Untuk mencocokkan hasil dengan Python, gunakan bar, parameter, kontrak dan skenario yang sama. Eksekusi OHLC memakai next-open, stop lebih dahulu ketika SL dan TP sama-sama tersentuh, mark di open dan close, posisi masih terbuka dicatat di akhir, serta pembatasan risiko harian, mingguan dan drawdown. Python menggunakan `Decimal` dan MQL5 menggunakan `double`. Perbandingan pada fixture telah diuji. Nilai di batas perbandingan dan pembulatan bisa berbeda. Mode PAPER menggunakan sampling OHLC, model broker dan infrastruktur lengkap Dev36 tetap menjadi referensi terpisah.

## Verifikasi

`reference/` mencatat registry, checksum sumber, daftar arsip yang ditemukan, dan contoh kontrak. `tools/verify_parity.py` mengompilasi subset MQL yang dipakai oleh EA melalui C++ dan membandingkan hasilnya dengan Python Dev36. Jalankan dengan sumber upstream yang sudah diekstrak dan dependensi `.[test]` tersedia.

```bash
python tools/verify_parity.py /path/to/veloxaurkaeon
```

419 tes Python Dev36 lulus. Uji pembanding pada fixture menghasilkan 1.533 sinyal serta 824 perdagangan tertutup yang cocok. Perbandingan hasil tersebut mencakup ledger kebijakan lab dan quant, serta sinyal EMA dan Donchian. Kompilasi MetaEditor dan pengujian terminal dicatat terpisah.

Build MetaEditor untuk kode EA pada commit `29ea0cce44aa162a37da900e58b5d42c1dd61606` selesai dengan **0 error dan 0 warning**, X64 Regular. SHA-256 `VeloxAurkaeonBacktest.ex5` adalah `247de2f9cb108fbca94c4367131ed25aeb46ebed37972f42c1c6b1101f230bfa`. Lihat [hasil build](https://github.com/edracode/HYPERION-OMEGA/actions/runs/45003641855). Data historis 20 tahun perlu dimuat pada terminal yang dipakai untuk pengujian.
