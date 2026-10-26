# ADR-001: Migrasi CDC dari Manual `pglogrepl` ke Debezium

* **Status:** Proposed
* **Date:** 2026-08-02

## Context

Saat ini pipeline CDC menggunakan implementasi berbasis `pglogrepl` yang ditulis secara manual dalam bahasa Go untuk membaca PostgreSQL Write-Ahead Log (WAL) dan mengirimkan perubahan data ke ClickHouse. Pendekatan ini memberikan fleksibilitas penuh, namun seluruh mekanisme CDC—mulai dari replication slot, logical replication, decoding WAL, transformasi event, hingga pengiriman data—harus diimplementasikan dan dipelihara sendiri.

Selain itu, beberapa image container yang digunakan pada stack saat ini (misalnya Redpanda Console versi lama) sudah memasuki status deprecated sehingga perlu dilakukan pembaruan agar tetap memperoleh dukungan dan kompatibilitas dengan ekosistem terbaru.

Untuk meningkatkan maintainability, scalability, dan observability pipeline, diperlukan migrasi menuju solusi CDC yang lebih standar, yaitu Debezium.

### Kondisi saat ini

- CDC menggunakan implementasi manual berbasis `pglogrepl` (Go).
- Seluruh proses logical replication dikelola oleh kode aplikasi sendiri.
- Event CDC langsung diproses sesuai format internal sebelum dikirim ke ClickHouse.
- Beberapa image Docker yang digunakan sudah menggunakan versi lama atau deprecated.

### Permasalahan

- Perubahan schema PostgreSQL sering membutuhkan perubahan kode CDC.
- Seluruh proses replication, decoding WAL, dan mapping event harus dipelihara sendiri.
- Penambahan tabel baru memerlukan perubahan konfigurasi dan kode aplikasi.
- Monitoring kondisi connector, replication lag, maupun status sink masih terbatas.
- Sulit melakukan standarisasi pipeline untuk beberapa environment (development, staging, production).
- Beban maintenance meningkat karena CDC merupakan komponen yang dikembangkan sendiri.

### Tujuan

- Mengurangi kompleksitas implementasi CDC.
- Meningkatkan maintainability pipeline.
- Mempermudah penambahan tabel dan perubahan schema.
- Menyediakan monitoring dan observability yang lebih baik.
- Menggunakan komponen open-source yang telah teruji dan banyak digunakan di industri.
- Memperbarui image container ke versi yang masih aktif didukung.

---

## Options Considered

### Option 1: Tetap menggunakan `pglogrepl` manual

**Kelebihan**

- Fleksibilitas penuh terhadap format event.
- Tidak memiliki dependency tambahan.
- Seluruh proses dapat dioptimasi sesuai kebutuhan aplikasi.

**Kekurangan**

- Maintenance tinggi.
- Seluruh fitur CDC harus dikembangkan sendiri.
- Sulit melakukan scaling ketika jumlah tabel bertambah.
- Monitoring dan observability terbatas.
- Semakin kompleks seiring berkembangnya pipeline.

---

### Option 2: Migrasi ke Debezium

**Kelebihan**

- Solusi CDC yang sudah mature dan digunakan secara luas.
- Mengelola replication slot dan logical decoding secara otomatis.
- Mendukung penambahan maupun perubahan tabel melalui konfigurasi connector.
- Mendukung schema evolution.
- Memiliki monitoring melalui Kafka Connect REST API dan metric JMX.
- Mudah diintegrasikan dengan Redpanda/Kafka.
- Mendukung Single Message Transform (SMT) untuk transformasi event tanpa menulis kode tambahan.
- Lebih mudah dikembangkan untuk multi-environment.

**Kekurangan**

- Menambah komponen baru (Kafka Connect + Debezium Connector).
- Format event lebih kompleks dibanding implementasi manual.
- Membutuhkan penyesuaian pada consumer ClickHouse.

---

### Option 3: Menggunakan CDC berbasis Trigger PostgreSQL

**Kelebihan**

- Implementasi relatif sederhana.
- Tidak membutuhkan logical replication.

**Kekurangan**

- Menambah beban pada database.
- Sulit dipelihara jika jumlah tabel banyak.
- Berpotensi memengaruhi performa transaksi.
- Tidak direkomendasikan untuk workload CDC berskala besar.

---

## Decision

Dipilih **Option 2: Debezium** sebagai solusi CDC utama.

Alasan pemilihan:

- Mengurangi kompleksitas implementasi CDC karena sebagian besar mekanisme telah disediakan oleh Debezium.
- Menurunkan biaya maintenance dibanding mempertahankan implementasi `pglogrepl` manual.
- Memiliki monitoring, observability, dan tooling yang lebih baik.
- Lebih mudah dikembangkan ketika jumlah tabel maupun environment bertambah.
- Mengikuti praktik umum (industry standard) untuk pipeline CDC berbasis PostgreSQL.

---

## Detail Implementasi

### Langkah implementasi

- Menambahkan service **Debezium Kafka Connect** pada `docker-compose`.
- Menambahkan direktori `connectors/` yang berisi konfigurasi connector PostgreSQL dalam format JSON.
- Menghapus implementasi CDC berbasis `pglogrepl` beserta service Go yang terkait.
- Mengonfigurasi Debezium agar mengirim event CDC ke topic Redpanda.
- Menyesuaikan consumer ClickHouse agar membaca format event Debezium.
- Mengubah struktur tabel ClickHouse apabila diperlukan agar sesuai dengan payload Debezium.
- Pada tahap awal, payload menggunakan format **JSON** untuk mempermudah debugging dan validasi.
- Pada tahap berikutnya dapat dipertimbangkan migrasi ke format **Avro** atau **Protobuf** menggunakan Schema Registry apabila diperlukan efisiensi storage dan bandwidth.
- Memperbarui seluruh image container ke versi terbaru yang masih aktif didukung, termasuk mengganti image yang sudah deprecated.

### Catatan tambahan

- Format event berubah dari format internal menjadi format standar Debezium.
- Struktur topic mengikuti penamaan connector Debezium.
- Dokumentasi deployment dan konfigurasi connector perlu diperbarui.

---

## Consequences

### Positif

- Pipeline CDC menjadi lebih mudah dipelihara.
- Penambahan tabel baru cukup melalui konfigurasi connector tanpa mengubah kode aplikasi.
- Monitoring status connector dan replication lebih mudah dilakukan.
- Pipeline lebih mudah dikembangkan untuk environment development, staging, dan production.
- Mengurangi risiko bug pada implementasi CDC karena menggunakan solusi yang telah matang.
- Stack menggunakan image container yang lebih baru dan masih memperoleh dukungan.

### Negatif

- Menambah kompleksitas deployment karena terdapat service Debezium/Kafka Connect.
- Consumer ClickHouse perlu disesuaikan dengan format event Debezium.
- Payload Debezium lebih besar dibanding implementasi manual sehingga penggunaan bandwidth dan storage sedikit meningkat.
- Tim perlu memahami konfigurasi dan operasional Debezium.