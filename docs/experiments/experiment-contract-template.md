# Experiment Contract, Metrics & Acceptance Criteria

**ADR:** [ADR-004](../../adr/ADR-004-performance-reliability-testing.md)  
**Task:** 1/9  
**Parent epic:** DAS-1  
**Status:** rancangan; parameter dan ambang harus disepakati sebelum eksperimen.

## Informasi eksperimen

- **Nama:** baseline beban order pipeline.
- **Tujuan:** mengukur perilaku pipeline PostgreSQL → Debezium → Redpanda → Go Consumer → ClickHouse tanpa gangguan.
- **Hipotesis:** pada beban dasar yang dipilih, pipeline memproses order dan meneruskan perubahan CDC ke ClickHouse. Kemampuan dan batasnya ditentukan dari pengukuran.
- **Lingkungan:** pilih dan catat lingkungan non-production secara eksplisit sebelum eksperimen.
- **Kondisi awal:** service sehat, schema dan data awal tersedia, connector terdaftar, serta hanya satu traffic generator aktif. Catat versi, kapasitas, konfigurasi, dan backlog awal.

## Skema konfigurasi workload

Skema mengikuti `services/order-service/traffic-config.yaml`. Nilai eksperimen ditetapkan sebelum eksekusi; nilai di file bukan otomatis kriteria kelulusan.

| Parameter | Tipe | Satuan | Arti |
| --- | --- | --- | --- |
| `request.base_rate_per_second` | angka | request/detik | Target laju dasar request yang dicoba. |
| `request.max_concurrency` | integer | request | Batas request yang berjalan bersamaan. |
| `request.timeout_seconds` | angka | detik | Timeout request. |
| `flash_sale.enabled` | boolean | — | Mengaktifkan flash sale. |
| `flash_sale.interval_seconds` | angka | detik | Interval antarawal flash sale. |
| `flash_sale.duration_seconds` | angka | detik | Durasi flash sale. |
| `flash_sale.rate_per_second` | angka | request/detik | Target laju selama flash sale, menggantikan laju dasar. |
| `experiment.duration_seconds` | angka atau null | detik | Durasi eksperimen; `null` berarti hingga dihentikan manual. |

## Workload dan penjadwalan

Target mengacu pada **request yang dicoba**, bukan transaksi sukses. Penjadwalan menggunakan waktu untuk laju dasar dan flash sale; target adalah beban yang diupayakan, bukan jaminan throughput. Catat target serta laju aktual dan hindari generator tambahan yang berjalan bersamaan.

Satu request order dapat menghasilkan beberapa perubahan CDC. Jumlah request, transaksi sukses, dan event CDC tidak dapat dibandingkan satu banding satu tanpa menetapkan jenis event dan unit pengukuran.

## Definisi dan metode pengukuran metrik

Berikut adalah kontrak pengukuran yang diusulkan untuk memenuhi ADR; ketersediaan instrumentasi dan timestamp harus diverifikasi sebelum eksperimen. Gunakan jendela pengukuran dan identitas event yang konsisten, serta catat sumber dan keterbatasannya.

| Metrik | Definisi dan metode | Satuan / sumber |
| --- | --- | --- |
| Attempted RPS | Jumlah request yang benar-benar dicoba dibagi durasi jendela. Bedakan target yang terlewat karena batas konkurensi dari request yang dicoba. | request/detik; counter generator. |
| Successful TPS | Jumlah request yang menghasilkan transaksi order sukses dibagi durasi jendela. Catat respons gagal dan timeout; timeout tidak membuktikan transaksi tidak terjadi. | transaksi/detik; counter generator dan data order sumber untuk rekonsiliasi. |
| Latency request | Selisih waktu mulai request hingga respons diterima; laporkan distribusi dan timeout secara terpisah. | milidetik; pengukuran generator. |
| Source-to-sink lag | Selisih waktu event tercatat pada sumber dan waktu event yang sama tersedia di sink. Definisikan titik timestamp, identitas event, dan sink; pastikan jam dapat dibandingkan. | detik; metadata CDC dan pengamatan ClickHouse. |
| Loss | Setelah masa tunggu pemulihan yang ditentukan, bandingkan event sumber yang diharapkan dengan event sink berdasarkan identitas event yang stabil. Catat yang belum ditemukan dan batas pengamatan. | jumlah dan proporsi; rekonsiliasi sumber–sink. |
| Duplication | Hitung kemunculan berlebih untuk identitas event yang sama di sink, sesuai semantik pemrosesan. Jangan anggap beberapa perubahan sah pada satu record sebagai duplikasi. | jumlah dan proporsi; identitas event di sink. |
| Consumer lag dan pemulihan | Amati backlog atau consumer lag dan waktu sampai kembali ke tingkat yang ditentukan setelah gangguan. | pesan/offset dan detik; metrik broker/consumer. |

Generator saat ini belum menyediakan seluruh counter, timestamp, korelasi, dan metrik tersebut. Sampling log keberhasilan/kegagalan tidak cukup untuk menghitung total yang akurat; jangan menyatakan loss atau duplikasi nol tanpa data rekonsiliasi yang memadai.

## Eksperimen baseline

1. Pilih lingkungan non-production, catat kondisi awal dan konfigurasi, lalu pastikan hanya satu generator aktif.
2. Tentukan laju dasar, konkurensi, timeout, durasi, jendela pengukuran, dan masa tunggu pemulihan. Nonaktifkan flash sale untuk baseline; uji spike sebagai skenario terpisah.
3. Tentukan ambang lulus/gagal sebelum menjalankan traffic. Jalankan tanpa gangguan yang disengaja.
4. Kumpulkan throughput, latency, source-to-sink lag, loss, dan duplikasi; catat konfigurasi serta hasil agar dapat diulang.
5. Hentikan traffic, tunggu pemrosesan sesuai masa yang ditentukan, dan lakukan rekonsiliasi sumber–sink.

**Nilai baseline dan hasil:** belum ditentukan; isi setelah parameter disepakati dan pengukuran dilakukan.

## Kriteria lulus atau gagal

ADR tidak menetapkan ambang numerik. Isi tabel sebelum eksperimen; hasil tanpa data yang memadai dinyatakan **tidak dapat disimpulkan**, bukan lulus.

| Metrik | Ambang dan jendela terukur | Lulus | Gagal |
| --- | --- | --- | --- |
| Attempted RPS / successful TPS | Belum ditentukan | Memenuhi ambang yang disepakati | Tidak memenuhi ambang yang disepakati |
| Latency | Belum ditentukan | Memenuhi ambang persentil yang disepakati | Melebihi ambang yang disepakati |
| Source-to-sink lag | Belum ditentukan | Memenuhi ambang yang disepakati | Melebihi ambang yang disepakati |
| Loss | Belum ditentukan | Memenuhi batas hasil rekonsiliasi | Melebihi batas hasil rekonsiliasi |
| Duplication | Belum ditentukan | Memenuhi batas hasil rekonsiliasi | Melebihi batas hasil rekonsiliasi |
| Pemulihan setelah fault | Belum ditentukan; untuk skenario fault | Kembali ke kondisi yang ditentukan dalam batas waktu | Tidak kembali dalam batas waktu |

## Keselamatan dan pemulihan

- Jalankan fault hanya pada lingkungan **non-production yang dipilih dan diverifikasi secara eksplisit**; catat nama proyek, service, dan target sebelum tindakan.
- Untuk skenario gangguan, catat kondisi awal, hipotesis, komponen dan durasi fault, metrik, serta kriteria lulus sebelum menjalankannya.
- Rencanakan langkah untuk melanjutkan atau memulihkan setiap service yang terdampak, termasuk jika eksperimen berhenti atau gagal.
- Setelah fault, pulihkan service dan verifikasi status, backlog, serta pemulihan aliran data. Contoh ADR: jeda Go Consumer, amati backlog bertambah, lanjutkan consumer, dan amati backlog berkurang.
