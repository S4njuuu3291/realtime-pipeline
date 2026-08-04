# 1. Load environment variables
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Variables
DOCKER_COMPOSE = docker compose --env-file .env -f deployments/docker/docker-compose.yml
POSTGRES_USER ?= admin
POSTGRES_DB ?= ecom_db
CONNECTOR_NAME ?= ecommerce-postgres-source
TOPIC_PREFIX ?= ecommerce
SLOT_NAME ?= ecommerce_debezium_slot
PUBLICATION_NAME ?= ecommerce_debezium_publication
TABLE_INCLUDE_LIST ?= public.users,public.products,public.orders,public.order_items

.PHONY: help build test clean docker-up docker-down docker-build order-service-bash db-shell init-db clean-db logs export-dashboard export-dashboard-script logs-cdc logs-tg init-redpanda init-debezium init-clickhouse init-analytics init-superset clean-clickhouse reset-clickhouse drop-slot seed-db generate-traffic resume stop reset-all act-deploy k8s-db-shell

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

docker-down-v:
	@echo "Stopping services and removing volumes..."
	$(DOCKER_COMPOSE) down -v

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

init-dbz:
	@echo "Generating connector config from template..."
	@envsubst < connectors/postgres-template.json > connectors/postgres-source.json
	@echo "Registering Debezium connector..."
	@curl -s -X POST http://localhost:8083/connectors \
		-H "Content-Type: application/json" \
		--data @connectors/postgres-source.json \
		-o /dev/null -w "HTTP %{http_code}\n"
	@echo "✓ Debezium connector registered"

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

db-shell:
	@echo "Accessing PostgreSQL shell..."
	$(DOCKER_COMPOSE) exec postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

clickhouse-shell:
	@echo "Accessing ClickHouse shell..."
	docker exec -it docker-clickhouse-1 clickhouse-client --password $(CLICKHOUSE_ADMIN_PASSWORD)

init-clickhouse:
	@echo "Initializing ClickHouse schema..."
	cat scripts/sql/init_clickhouse.sql | docker exec -i docker-clickhouse-1 clickhouse-client --password $(CLICKHOUSE_ADMIN_PASSWORD) --multiquery
	cat scripts/sql/init_analytics.sql | docker exec -i docker-clickhouse-1 clickhouse-client --password $(CLICKHOUSE_ADMIN_PASSWORD) --multiquery
	@echo "✓ ClickHouse schema initialized successfully"

init-superset:
	@echo "Initializing Apache Superset..."
	docker exec -i docker-superset-1 bash < deployments/docker/init-superset.sh
	@echo "✓ Superset is initialized and ready to use"

reset-all: drop-slot clean-db clean-clickhouse init-db init-clickhouse init-analytics init-redpanda
	@echo "🚀 FULL SYSTEM RESET COMPLETE"

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
	curl -sf -X POST -u "$(GRAFANA_ADMIN_USER):$(GRAFANA_ADMIN_PASSWORD)" http://localhost:3000/api/admin/provisioning/dashboards/reload

logs-cdc:
	$(DOCKER_COMPOSE) logs -f cdc-ingestor

logs-tg:
	# tail 20 lines of logs and follow
	$(DOCKER_COMPOSE) logs --tail=20 --follow traffic-generator

restart-tg:
	@echo "Restarting traffic-generator..."
	$(DOCKER_COMPOSE) restart traffic-generator

pause-tg:
	@echo "Pausing traffic-generator..."
	$(DOCKER_COMPOSE) stop traffic-generator

docker-logs-os:
	$(DOCKER_COMPOSE) logs order-service

clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	go clean

act-deploy:
	act -P ubuntu-latest=catthehacker/ubuntu:act-latest --secret-file .secrets --network bridge


# ========================= K8S =========================
k8s-db-shell:
	minikube kubectl -- exec -it postgres-source-0 -- psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)
