#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/6] Menyiapkan schema PostgreSQL..."
make init-db

echo "[2/6] Menyiapkan topic Redpanda..."
make init-redpanda

echo "[3/6] Menyiapkan schema dan views ClickHouse..."
make init-clickhouse

echo "[4/6] Mengisi data awal..."
make seed-db

echo "[5/6] Mendaftarkan connector Debezium..."
make init-dbz

echo "[6/6] Menyiapkan Superset dan dashboard..."
make init-superset

echo "Inisialisasi pipeline selesai."
