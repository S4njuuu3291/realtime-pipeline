# 1. Load environment variables
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Variables
DOCKER_COMPOSE = docker compose --env-file .env -f deployments/docker/docker-compose.yml
POSTGRES_USER ?= admin
POSTGRES_DB ?= ecom_db

.PHONY: help build test clean docker-up docker-down docker-build order-service-bash db-shell init-db clean-db logs export-dashboard export-dashboard-script

help:
	@echo "Enterprise CDC Pipeline - Available Commands"
	@echo ""
	@echo "  make build              Build Go applications"
	@echo "  make docker-up          Start all services (with build check)"
	@echo "  make docker-down        Stop and remove containers"
	@echo "  make docker-rebuild     Force rebuild and restart order-service"
	@echo "  make init-redpanda      Initialize Redpanda topics with specific partitions"
	@echo "  make init-clickhouse    Initialize ClickHouse schema (Bronze Layer)"
	@echo "  make init-analytics     Initialize ClickHouse Analytics schema (Silver & Gold OBT)"
	@echo "  make init-superset      Initialize Apache Superset (DB & Admin User)"
	@echo "  make clean-clickhouse   Drop all ClickHouse history tables and views"
	@echo "  make reset-clickhouse   Clean and Re-initialize ClickHouse (Reset Everything)"
	@echo "  make init-db            Initialize database schema (create tables)"
	@echo "  make seed-db            Mass insert 1000s of dummy users and products"
	@echo "  make generate-traffic   Trigger infinite random orders (CDC load testing)"
	@echo "  make clean-db           Drop all existing tables in the database"
	@echo "  make db-shell           Enter PostgreSQL CLI"
	@echo "  make order-service-bash Enter FastAPI container"
	@echo "  make clickhouse-shell   Enter ClickHouse CLI"
	@echo "  make logs               View all container logs"

build:
	@echo "Building Go applications...."
	mkdir -p bin
	go build -o bin/producer cmd/producer/main.go
	go build -o bin/processor cmd/processor/main.go

docker-build:
	@echo "Building Docker images..."
	$(DOCKER_COMPOSE) build

docker-up:
	@echo "Starting services..."
	$(DOCKER_COMPOSE) up -d

docker-down:
	@echo "Stopping services..."
	$(DOCKER_COMPOSE) down

# Perintah khusus untuk reset jika order-service error terus (Clear Cache)
docker-rebuild:
	@echo "Rebuilding order-service without cache..."
	$(DOCKER_COMPOSE) build --no-cache order-service
	$(DOCKER_COMPOSE) up -d order-service

order-service-bash:
	@echo "Entering order-service container..."
	docker exec -it order-service /bin/bash

init-redpanda:
	@echo "Initializing Redpanda Topics..."
	@echo "Waiting for Redpanda to be ready..."
	@sleep 5
	$(DOCKER_COMPOSE) exec -T redpanda rpk topic create cdc-events -p 3 || true
	@echo "✓ Topic cdc-events with 3 partitions initialized"

init-db:
	@echo "Initializing database schema..."
	@echo "Waiting for PostgreSQL to be ready..."
	@sleep 3
	$(DOCKER_COMPOSE) exec -T postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -f /dev/stdin < scripts/sql/init_source.sql
	@echo "✓ Database schema initialized successfully"

seed-db:
	@echo "Suntik Data Massal (Seeding) sedang berjalan..."
	$(DOCKER_COMPOSE) exec -T order-service python data_generator.py --seed

generate-traffic:
	@echo "Mengaktifkan Robot Transaksi di background..."
	$(DOCKER_COMPOSE) exec -d order-service python data_generator.py --traffic

clean-db:
	@echo "Dropping existing database tables..."
	$(DOCKER_COMPOSE) exec -T postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "DROP TABLE IF EXISTS order_items, orders, products, users CASCADE;"
	@echo "✓ Database tables dropped successfully"

drop-slot:
	@echo "Dropping PostgreSQL replication slot..."
	-$(DOCKER_COMPOSE) exec -T postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "SELECT pg_drop_replication_slot('cdc_slot');"
	@echo "✓ Replication slot cleaned"

db-shell:
	@echo "Accessing PostgreSQL shell..."
	$(DOCKER_COMPOSE) exec postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

clickhouse-shell:
	@echo "Accessing ClickHouse shell..."
	docker exec -it clickhouse clickhouse-client --password admin123

init-clickhouse:
	@echo "Initializing ClickHouse schema..."
	cat scripts/sql/init_clickhouse.sql | docker exec -i clickhouse clickhouse-client --password admin123 --multiquery
	@echo "✓ ClickHouse schema initialized successfully"

init-analytics:
	@echo "Initializing Analytics (Silver & Gold Layers)..."
	cat scripts/sql/init_analytics.sql | docker exec -i clickhouse clickhouse-client --password admin123 --multiquery
	@echo "✓ Analytics schema initialized successfully"

init-superset:
	@echo "Initializing Apache Superset..."
	docker exec -i superset bash < deployments/docker/init-superset.sh
	@echo "✓ Superset is initialized and ready to use"

clean-clickhouse:
	@echo "Dropping all ClickHouse tables and views..."
	docker exec -i clickhouse clickhouse-client --password admin123 -q "\
		DROP VIEW IF EXISTS analytics_sales_obt; \
		DROP VIEW IF EXISTS analytics_sales_mv; \
		DROP VIEW IF EXISTS orders_join_mv; \
		DROP TABLE IF EXISTS orders_join; \
		DROP DICTIONARY IF EXISTS dict_users; \
		DROP DICTIONARY IF EXISTS dict_products; \
		DROP DICTIONARY IF EXISTS dict_orders; \
		DROP VIEW IF EXISTS vw_current_users; \
		DROP VIEW IF EXISTS vw_current_products; \
		DROP VIEW IF EXISTS vw_current_orders; \
		DROP VIEW IF EXISTS vw_current_order_items; \
		DROP VIEW IF EXISTS users_mv; \
		DROP VIEW IF EXISTS products_mv; \
		DROP VIEW IF EXISTS orders_mv; \
		DROP VIEW IF EXISTS order_items_mv; \
		DROP TABLE IF EXISTS cdc_queue; \
		DROP TABLE IF EXISTS users_history; \
		DROP TABLE IF EXISTS products_history; \
		DROP TABLE IF EXISTS orders_history; \
		DROP TABLE IF EXISTS order_items_history; \
		DROP TABLE IF EXISTS analytics_sales_obt;"
	@echo "✓ ClickHouse environment cleaned"

reset-clickhouse: clean-clickhouse init-clickhouse init-analytics

reset-all: drop-slot clean-db clean-clickhouse init-db init-clickhouse init-analytics init-redpanda
	@echo "🚀 FULL SYSTEM RESET COMPLETE"

full-start:
	@echo "⚠️ WARNING: This will reset all schemas and may overwrite master data!"
	@echo "🎬 STARTING INFRASTRUCTURE..."
	$(DOCKER_COMPOSE) up -d postgres-source clickhouse redpanda superset order-service
	@echo "⏳ Waiting for databases to be ready (20s)..."
	sleep 5
	@echo "⚙️ Initializing Postgres, ClickHouse & Superset..."
	$(MAKE) init-db
	$(MAKE) init-clickhouse
	$(MAKE) init-analytics
	$(MAKE) init-redpanda
	$(MAKE) init-superset
	@echo "🚀 STARTING CDC INGESTOR..."
	$(DOCKER_COMPOSE) up -d cdc-ingestor
	sleep 5
	@echo "🌱 Seeding Master Data (Users & Products)..."
	docker exec -it order-service python data_generator.py --seed
	@echo "⏳ Waiting for master data to sync (10s)..."
	sleep 10
	@echo "🤖 STARTING TRAFFIC GENERATOR..."
	$(DOCKER_COMPOSE) up -d traffic-generator
	@echo "✅ SYSTEM IS UP AND RUNNING!"
	@echo "💡 Cek OBT: docker exec -it clickhouse clickhouse-client --password admin123 -q 'SELECT * FROM analytics_sales_obt LIMIT 5;'"
	$(MAKE) logs

# Perintah untuk melanjutkan pekerjaan tanpa menghapus Dashboard/Data
resume:
	@echo "🎬 RESUMING ALL SERVICES..."
	$(DOCKER_COMPOSE) up -d
	@echo "🚀 RESTARTING INGESTOR..."
	$(DOCKER_COMPOSE) restart cdc-ingestor traffic-generator
	@echo "✅ SERVICES ARE RESUMED"
	$(MAKE) logs

# Matikan tanpa hapus data
stop:
	@echo "🛑 STOPPING SERVICES (Data is safe)..."
	$(DOCKER_COMPOSE) stop

# Alias untuk inisialisasi lengkap
setup-db: init-db seed-db


export-dashboard:
	@echo "📤 Exporting dashboard from Dev to provisioning..."
	python3 -m scripts.export-dashboard
	@echo "✓ Dashboard export complete. Now reloading"
	curl -X POST http://admin:admin@localhost:3000/api/admin/provisioning/dashboards/reload
	@echo "✓ Dashboard reloaded!"

logs:
	$(DOCKER_COMPOSE) logs -f

logs-cdc:
	$(DOCKER_COMPOSE) logs -f cdc-ingestor

turn-on-cdc:
	$(DOCKER_COMPOSE) up -d --build cdc-ingestor

turn-off-cdc:
	$(DOCKER_COMPOSE) rm -s -f cdc-ingestor

on-logs-cdc: turn-on-cdc logs-cdc

clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	go clean

act-deploy:
	act -P ubuntu-latest=catthehacker/ubuntu:act-latest --secret-file .secrets --network bridge
