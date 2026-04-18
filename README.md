# 🚀 Real-time CDC Pipeline (Postgres to ClickHouse)

Proyek ini adalah implementasi *Enterprise Data Pipeline* untuk menangkap perubahan data (*Change Data Capture*) secara *real-time* dari PostgreSQL, mengirimkannya melalui Redpanda (Kafka), dan menyimpannya di ClickHouse menggunakan model data **SCD Type 2**.

## 🏗️ Arsitektur Sistem
- **Source**: PostgreSQL (Logical Replication / WAL).
- **Ingestion**: CDC Ingestor (Go + `pglogrepl`) -> Serialisasi **Protobuf**.
- **Message Broker**: Redpanda (Kafka-compatible) dengan 3 Partisi (Row-level ordering).
- **Warehouse**: ClickHouse (OLAP) menggunakan **Kafka Engine** & **Materialized Views**.
- **Data Model**: SCD Type 2 (History tracking per baris data).

## 🛠️ Persiapan & Jalankan
Pastikan Anda memiliki Docker & Docker Compose terinstal.

1. **Nyalakan Infrastruktur:**
   ```bash
   make docker-up
   ```

2. **Inisialisasi Komponen (Urutan Penting):**
   ```bash
   make init-redpanda      # Buat Topic dengan 3 partisi
   make init-db            # Buat Tabel di Postgres Source
   make init-clickhouse    # Buat Skema SCD2 di ClickHouse
   ```

3. **Suntik Data & Testing:**
   ```bash
   make seed-db            # Masukkan data awal ke Postgres
   make generate-traffic   # Jalankan bot transaksi otomatis (CDC Testing)
   ```

## 📊 Monitoring & Analitik
- **Redpanda Console**: Akses [http://localhost:8888](http://localhost:8888) untuk melihat *stream* pesan Protobuf.
- **ClickHouse CLI**: Jalankan `make clickhouse-shell` lalu:
  ```sql
  -- Cek sejarah perubahan produk (SCD Type 2)
  SELECT * FROM products_history;
  ```

## 📂 Struktur Proyek
- `services/cdc-ingestor`: Ingestor utama berbasis Go.
- `services/order-service`: API transaksi (FastAPI) & Data Generator.
- `scripts/sql`: Script DDL untuk Postgres & ClickHouse.
- `deployments/docker`: Konfigurasi *orchestration* container.

---
*Dibuat untuk keperluan belajar Data Engineering - Real-time Pipeline Journey.*
