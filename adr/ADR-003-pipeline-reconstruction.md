# ADR-003: Rekonstruksi dan stabilisasi pipeline realtime

- Status: Accepted
- Date: 2026-10-26

## Context

Project direkonstruksi untuk menyegarkan pemahaman alur PostgreSQL → Debezium →
Redpanda → Go consumer → ClickHouse → Superset. Selama verifikasi ditemukan
ketidakcocokan driver PostgreSQL, koneksi database yang habis, password koneksi
Superset yang tidak diteruskan, dan query monitoring yang memakai nama slot lama.

## Decision

- Gunakan dialect `postgresql+psycopg2` sesuai dependency aplikasi.
- Batasi pool setiap worker order-service menjadi 5 koneksi tetap dan 5 overflow.
  Dengan 4 worker, maksimal 40 koneksi untuk aplikasi ini dari batas PostgreSQL 100;
  proses lain tetap memerlukan anggaran koneksi tersendiri.
- Teruskan password ClickHouse ke Superset melalui environment. Saat impor,
  berikan password secara terpisah dan perbarui URI database yang sudah ada
  menggunakan akun `superset_user` dan dialect `clickhousedb`.
- Gunakan slot `ecommerce_debezium_slot` pada dashboard monitoring.
- Lengkapi consumer untuk empat tabel sesuai ADR-002 dan verifikasi dengan unit test.
- Jalankan validasi consumer dan Compose pada PR sebelum merge ke main.

## Consequences

Konfigurasi dan pemetaan CDC dapat direproduksi dari repository. Password tidak
perlu ditulis ke arsip dashboard. File `.env` tetap lokal, cache Python tidak
lagi dilacak, dan pengiriman consumer tetap at least once.

Impor dashboard memakai API internal Superset 6.0.0 sehingga perlu diperiksa lagi
ketika versi Superset dinaikkan. Penggabungan data analytics tetap menggunakan
view terbaru per ID; keterbatasan delete dan tie timestamp dijelaskan di ADR-002.
