# Skenario 1: Baseline tanpa gangguan

**Referensi:** [ADR-004](../../adr/ADR-004-performance-reliability-testing.md) · [Kontrak eksperimen](experiment-contract-template.md)

## Tujuan dan hipotesis

Mengukur perilaku pipeline pada beban dasar tanpa fault atau flash sale sebagai pembanding untuk eksperimen berikutnya. Hipotesisnya, pipeline memproses order dan meneruskan perubahan CDC ke ClickHouse pada beban yang dipilih; hasil pengukuran akan menunjukkan kemampuan dan batasnya.

## Lingkungan dan kondisi awal

- Lingkungan non-production yang dipilih: **belum ditentukan**.
- Versi service dan kapasitas lingkungan: **belum dicatat**.
- Service sehat, schema dan data awal tersedia, connector terdaftar, dan hanya satu traffic generator aktif.
- Backlog awal dan kondisi awal metrik: **belum dicatat**.

## Parameter

| Parameter | Nilai eksperimen |
| --- | --- |
| Laju dasar request yang dicoba | 5 request/detik |
| Batas konkurensi | 50 request |
| Timeout request | 5 detik |
| Durasi eksperimen | 300 detik |
| Flash sale | Nonaktif |
| Jendela pengukuran | Selama 300 detik traffic berjalan |
| Waktu tunggu setelah traffic berhenti | 60 detik awal; catat backlog dan perpanjang bila belum pulih |

Ini adalah **usulan awal, bukan kapasitas yang telah dibuktikan**. Laju 3 request/detik mendekati pola lama ADR (2–5 request per siklus), tetapi pola lama bukan TPS terjamin. Batas konkurensi 50 dan timeout 5 detik mengikuti konfigurasi saat ini; durasi dan waktu tunggu dipilih sebagai titik awal pengamatan. Konfigurasi saat ini memakai 25 request/detik dan flash sale aktif, sehingga perlu disesuaikan khusus untuk eksperimen ini. Generator saat ini membaca konfigurasi saat mulai; terapkan perubahan ke image/container sebelum menjalankan eksperimen.

## Langkah eksperimen

1. Verifikasi lingkungan non-production yang dipilih dan catat kondisi awal, versi, kapasitas, serta konfigurasi.
2. Tentukan parameter dan ambang lulus/gagal di bawah ini sebelum menjalankan eksperimen. Pastikan hanya satu generator aktif.
3. Jalankan traffic dasar tanpa gangguan dan kumpulkan metrik selama jendela pengukuran.
4. Hentikan traffic, tunggu sesuai waktu yang ditentukan, lalu lakukan rekonsiliasi sumber–sink.
5. Catat hasil dan bandingkan dengan ambang yang sudah ditetapkan.

## Metrik dan kriteria

| Metrik | Hasil | Ambang lulus/gagal |
| --- | --- | --- |
| Attempted RPS dan successful TPS | Belum diukur | Belum ditentukan |
| Latency request | Belum diukur | Belum ditentukan |
| Source-to-sink lag | Belum diukur | Belum ditentukan |
| Loss | Belum diukur | Belum ditentukan |
| Duplication | Belum diukur | Belum ditentukan |

Gunakan definisi dan metode dalam kontrak eksperimen. Jika data yang diperlukan belum tersedia, hasil dinyatakan **tidak dapat disimpulkan**. Sampling log generator saja belum cukup untuk menghitung total keberhasilan atau kegagalan secara akurat.

## Hasil dan catatan

- Waktu pelaksanaan:
- Konfigurasi yang digunakan:
- Hasil akhir: **belum dijalankan**.
- Keterbatasan dan tindak lanjut:
