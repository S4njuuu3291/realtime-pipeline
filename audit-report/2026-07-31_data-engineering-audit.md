# Data Engineering Audit Report

Proyek: realtime-pipeline
Tanggal audit: 2026-07-31
Fokus: evaluasi high-level untuk production-readiness portfolio, dengan penekanan pada arsitektur, data quality, security, dan operability.

## Ringkasan Eksekutif

Repositori ini sudah menunjukkan fondasi yang jelas untuk project data engineering: alurnya benar-benar realtime CDC, ada pemisahan source-ingest-warehouse-BI, dan dokumentasi arsitektur cukup membantu untuk memahami aliran data. Secara konsep, ini sudah lebih matang daripada banyak portfolio biasa karena memakai PostgreSQL WAL, Go CDC ingestor, Redpanda, ClickHouse, dan observability stack.

Gap paling besar ada di area yang paling menentukan kesiapan produksi: secrets management, test coverage, dan validasi data. Selain itu, model data di ClickHouse masih menyimpan beberapa nilai numerik sebagai String, yang membuat analitik bergantung pada casting di layer query dan berisiko menurunkan kualitas hasil serta performa.

## Skor Ringkas

| Dimensi | Skor | Status |
|---|---:|---|
| Pipeline Architecture & Design | 7/10 | Needs Improvement |
| Data Modeling | 6/10 | Needs Improvement |
| Code Quality & Maintainability | 5/10 | Significant Gap |
| Data Quality & Testing | 2/10 | Missing / Critical |
| Security & Compliance | 1/10 | Missing / Critical |
| Performance & Scalability | 6/10 | Needs Improvement |
| Documentation & Observability | 6/10 | Needs Improvement |

## Temuan Utama

### 1) Secrets dan kredensial masih terekspos di konfigurasi runtime
**Confidence: High**

File compose masih menaruh secret dan kredensial langsung di manifest: Superset memakai secret key hardcoded, Grafana memakai `admin/admin`, dan exporter Postgres membentuk DSN dengan password dari environment yang juga mudah terekspos di runtime config. Di sisi CDC ingestor, proses juga mencetak full connection string ke log, yang berarti kredensial database ikut keluar ke stdout.

Referensi: [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L141), [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L171), [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L199), [services/cdc-ingestor/main.go](../services/cdc-ingestor/main.go#L23), [services/cdc-ingestor/main.go](../services/cdc-ingestor/main.go#L38), [services/cdc-ingestor/main.go](../services/cdc-ingestor/main.go#L40)

Impact: ini langsung menurunkan security posture project. Untuk portfolio, reviewer akan melihat ini sebagai gap nyata karena pola ini mudah dipindahkan ke produksi tanpa kontrol yang memadai.

### 2) Testing dan data quality checks hampir tidak ada
**Confidence: High**

CI saat ini hanya melakukan validasi docker compose, cek keberadaan file dashboard, dan `go vet`. Itu berguna sebagai smoke check, tetapi belum menguji transformasi data, integritas relasi, freshness, atau row-count consistency. Di dependency Python juga belum terlihat tooling test seperti `pytest`.

Referensi: [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml#L12), [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml#L23), [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml#L32), [services/order-service/requirements.txt](../services/order-service/requirements.txt#L1)

Impact: ini adalah gap terbesar untuk reliability. Pipeline bisa jalan saat demo, tetapi belum ada bukti bahwa data yang keluar benar dan stabil ketika beban atau skenario edge case berubah.

### 3) Model analitik masih terlalu bergantung pada String untuk nilai numerik
**Confidence: Medium-High**

Bronze/History layer ClickHouse menyimpan `price`, `total_amount`, dan `unit_price` sebagai String, lalu layer analytics juga mempertahankan pola ini. Itu memudahkan ingest CDC, tetapi memindahkan beban validasi dan casting ke query layer. Untuk analitik, ini mengurangi tipe safety, menyulitkan agregasi, dan bisa menjadi sumber bug silent saat visualisasi atau kalkulasi revenue.

Referensi: [scripts/sql/init_clickhouse.sql](../scripts/sql/init_clickhouse.sql#L6), [scripts/sql/init_clickhouse.sql](../scripts/sql/init_clickhouse.sql#L10), [scripts/sql/init_clickhouse.sql](../scripts/sql/init_clickhouse.sql#L14), [scripts/sql/init_analytics.sql](../scripts/sql/init_analytics.sql#L58), [scripts/sql/init_analytics.sql](../scripts/sql/init_analytics.sql#L69), [scripts/sql/init_analytics.sql](../scripts/sql/init_analytics.sql#L70)

Impact: untuk portfolio realtime analytics, ini bukan bug fatal, tetapi merupakan desain yang kurang kuat bila targetnya dashboard yang konsisten dan mudah dipelihara.

### 4) Orkestrasi dan build hygiene masih terlalu banyak asumsi mutable
**Confidence: Medium**

Compose dan Dockerfile masih memakai beberapa image mutable seperti `latest`, dan workflow deploy melakukan alur stop/start yang cukup procedural. Itu masih workable untuk project belajar, tetapi tidak ideal jika ingin menunjukkan discipline produksi: reproducibility build, pinning versi, dan upgrade path yang bisa diprediksi masih bisa diperkuat.

Referensi: [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L117), [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L153), [deployments/docker/docker-compose.yml](../deployments/docker/docker-compose.yml#L166), [services/cdc-ingestor/Dockerfile](../services/cdc-ingestor/Dockerfile#L24)

Impact: risikonya bukan kegagalan langsung, tetapi drift lingkungan dan hasil build yang sulit direproduksi ketika project dipakai ulang atau dipresentasikan di environment berbeda.

## Learning Roadmap untuk Critical Findings

### A. Secrets management dan safe logging
**Konsep**: pisahkan secret dari manifest, hindari log credential, gunakan pola config injection yang aman.

**Resource**: baca materi security/compliance tentang secret management, least privilege, dan secret scanning.

**Praktek**: pindahkan `SUPERSET_SECRET_KEY`, credential Grafana, dan DSN database ke secret manager atau docker secret pattern; ubah CDC ingestor agar hanya log host/service name, bukan full connection string.

**Priority**: sangat tinggi.

### B. Data quality checks dan automated testing
**Konsep**: setiap pipeline perlu bukti bahwa data valid, lengkap, dan konsisten, bukan sekadar berhasil dieksekusi.

**Resource**: cari materi tentang unit test transformasi data, dbt tests, atau Great Expectations, lalu cocokkan dengan kebutuhan project realtime kecil.

**Praktek**: tambahkan minimal 3 lapis pemeriksaan: test untuk SQL/view hasil agregasi, check uniqueness dan referential integrity, serta smoke test untuk row count dan freshness setelah seed atau traffic generator jalan.

**Priority**: sangat tinggi.

### C. Typed warehouse modeling untuk metric fields
**Konsep**: kolom metrik harus bertipe numerik di storage layer agar query lebih aman dan lebih murah.

**Resource**: pelajari perbedaan storage type vs presentation type, serta kapan casting sebaiknya terjadi di ingest layer, bukan di dashboard layer.

**Praktek**: ubah history/analytics layer agar `price`, `total_amount`, dan `unit_price` memakai tipe numerik yang sesuai; lalu update view dan dashboard agar kalkulasi revenue tidak bergantung pada casting ad hoc.

**Priority**: tinggi.

### D. Reproducible build dan environment pinning
**Konsep**: environment yang bisa diulang adalah fondasi untuk demo, review, dan debugging yang stabil.

**Resource**: baca praktik version pinning untuk Docker image, dependency management, dan CI environment isolation.

**Praktek**: ganti image `latest` ke tag spesifik, tambahkan pemeriksaan komponen yang benar-benar ada di CI, dan pertimbangkan lockfile atau versi dependency yang lebih ketat.

**Priority**: medium-high.

## Rekomendasi Prioritas

1. Bereskan secrets management dan logging dulu, karena ini yang paling jelas berisiko.
2. Tambahkan test dan data validation minimal untuk jalur seed -> CDC -> ClickHouse -> analytics view.
3. Rapikan typing warehouse untuk field numerik supaya analitik lebih kuat dan lebih mudah dibaca reviewer.
4. Setelah itu, pin image dan dependencies agar project lebih reproducible.

## Kesimpulan

Secara keseluruhan, project ini sudah layak sebagai portfolio realtime CDC, terutama di sisi arsitektur dan storytelling teknis. Namun, untuk terlihat lebih siap produksi, dua hal yang paling perlu ditingkatkan adalah keamanan konfigurasi dan bukti kualitas data. Jika dua area itu diperkuat, kualitas portfolionya akan naik jauh lebih cepat daripada sekadar menambah komponen baru.