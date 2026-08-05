## ADR-002: Migrasi Ingestion dari Clickhouse Kafka Engine ke Go Consumer

* **Status:** Proposed
* **Date:** 2026-08-05

## Context

Saat ini event CDC yang dihasilkan Debezium dikirim ke Redpanda dalam format JSON dan dikonsumsi langsung oleh ClickHouse menggunakan Kafka Engine. Materialized View kemudian memindahkan data dari Kafka Engine ke tabel Bronze untuk diproses lebih lanjut menjadi Silver dan Gold.

Pendekatan ini sederhana dan memanfaatkan kemampuan native ClickHouse untuk membaca topic Kafka tanpa memerlukan komponen tambahan.

Namun, seiring berkembangnya pipeline, muncul kebutuhan untuk memiliki kontrol yang lebih besar terhadap proses konsumsi event, seperti batching, retry, dead-letter queue (DLQ), observability, maupun pengelolaan offset consumer.

Selain itu, implementasi consumer berbasis aplikasi memberikan fleksibilitas untuk menambahkan validasi maupun transformasi ringan sebelum data disimpan ke ClickHouse tanpa bergantung pada kemampuan Kafka Engine.

### Kondisi saat ini

- Debezium mengirim event CDC ke Redpanda dalam format JSON.
- ClickHouse Kafka Engine membaca topic secara langsung.
- Materialized View memindahkan data ke tabel Bronze.
- Offset consumer dikelola oleh Kafka Engine.
- Error handling dan retry mengikuti mekanisme bawaan ClickHouse.

### Permasalahan

- Kontrol terhadap proses konsumsi event masih terbatas.
- Kebijakan retry dan error handling tidak dapat dikustomisasi secara fleksibel.
- Tidak tersedia mekanisme native untuk dead-letter queue (DLQ).
- Sulit menerapkan validasi maupun penanganan berbeda berdasarkan jenis kegagalan.
- Tidak terdapat fleksibilitas untuk melakukan validasi atau transformasi ringan sebelum proses ingest.
- Observability consumer terbatas dibanding implementasi berbasis aplikasi.
- Sulit melakukan penyesuaian perilaku consumer sesuai kebutuhan pipeline.

### Tujuan

- Memberikan kontrol penuh terhadap proses konsumsi event.
- Menambahkan mekanisme batching untuk meningkatkan efisiensi penulisan ke ClickHouse.
- Menyediakan retry dan dead-letter queue apabila terjadi kegagalan pemrosesan.
- Meningkatkan observability melalui logging dan metrics.
- Mempersiapkan arsitektur agar lebih mudah dikembangkan pada tahap stream processing berikutnya.

---

## Options Considered

### Option 1: Tetap menggunakan ClickHouse Kafka Engine

**Kelebihan**

- Arsitektur sederhana.
- Tidak memerlukan service tambahan.
- Maintenance relatif rendah.
- Latency ingest rendah.
- Memanfaatkan integrasi native ClickHouse dengan Kafka API.

**Kekurangan**

- Kontrol terhadap retry dan error handling terbatas.
- Sulit menambahkan validasi maupun business logic ringan.
- Observability consumer terbatas.
- Sulit menerapkan mekanisme DLQ maupun batching yang lebih fleksibel.

---

### Option 2: Menggunakan Go Stream Consumer

**Kelebihan**

- Kontrol penuh terhadap offset consumer.
- Mendukung batching sebelum penulisan ke ClickHouse.
- Mendukung retry dengan kebijakan yang dapat dikonfigurasi.
- Mendukung dead-letter queue untuk event yang gagal diproses.
- Mudah menambahkan logging, metrics, dan health check.
- Memberikan fleksibilitas untuk validasi maupun transformasi ringan.
- Lebih mudah dikembangkan menuju stream processing yang lebih kompleks.

**Kekurangan**

- Menambah service baru pada deployment.
- Maintenance aplikasi consumer menjadi tanggung jawab tim.
- Perlu menangani lifecycle consumer seperti rebalance, graceful shutdown, dan offset commit.

---

### Option 3: Menggunakan Stream Processing Framework (misalnya Apache Flink)

**Kelebihan**

- Mendukung stateful stream processing.
- Mendukung event-time processing, window, dan checkpoint.
- Cocok untuk transformasi streaming yang kompleks.

**Kekurangan**

- Menambah kompleksitas deployment.
- Membutuhkan resource yang lebih besar.
- Fitur stream processing lanjutan belum dibutuhkan pada tahap pipeline saat ini.

---

## Decision

Dipilih **Option 2: Menggunakan Go Stream Consumer** sebagai komponen ingestion antara Redpanda dan ClickHouse.

Alasan pemilihan:

- Memberikan kontrol yang lebih besar terhadap proses konsumsi event.
- Mendukung batching sehingga proses ingest ke ClickHouse lebih efisien.
- Memungkinkan implementasi retry, dead-letter queue, dan observability yang lebih baik.
- Tetap mempertahankan Debezium sebagai CDC engine sehingga consumer hanya bertanggung jawab terhadap downstream processing.
- Menjadi fondasi untuk pengembangan pipeline streaming pada tahap berikutnya tanpa menambah kompleksitas framework stream processing.

---

## Detail Implementasi

### Langkah implementasi

- Menghapus penggunaan ClickHouse Kafka Engine sebagai consumer utama.
- Mengembangkan service Go sebagai Kafka consumer.
- Consumer membaca event Debezium dari topic Redpanda.
- Consumer melakukan parsing payload Debezium JSON.
- Event dikumpulkan dalam batch sebelum dikirim ke ClickHouse.
- Offset di-commit setelah batch berhasil ditulis.
- Event yang gagal diproses setelah batas retry dikirim ke Dead Letter Queue.
- Menambahkan metrics Prometheus dan structured logging.
- Menambahkan health check endpoint untuk monitoring service.

### Catatan tambahan

- Debezium tetap menjadi CDC engine utama.
- Format payload tetap menggunakan JSON.
- Tidak terdapat perubahan terhadap konfigurasi Debezium maupun topic Redpanda.
- Transformasi bisnis kompleks tetap dilakukan pada layer warehouse atau stream processing pada tahap berikutnya.

---

## Consequences

### Positif

- Kontrol penuh terhadap proses ingest.
- Observability pipeline meningkat.
- Error handling lebih fleksibel.
- Mendukung batching sehingga throughput lebih baik.
- Mempermudah pengembangan fitur consumer di masa depan.

### Negatif

- Menambah kompleksitas deployment.
- Menambah komponen yang harus dipelihara.
- Consumer perlu menangani offset management dan rebalance secara benar.
- Membutuhkan pengujian lebih menyeluruh terhadap skenario kegagalan.