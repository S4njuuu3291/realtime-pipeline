# 1. Load environment variables
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Variables
DOCKER_COMPOSE = docker compose --env-file .env -f deployments/docker/docker-compose.yml
POSTGRES_USER ?= admin
POSTGRES_DB ?= ecom_db

.PHONY: help build test clean docker-up docker-down docker-build order-service-bash db-shell init-db clean-db logs

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

db-shell:
	@echo "Accessing PostgreSQL shell..."
	$(DOCKER_COMPOSE) exec postgres-source psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

clickhouse-shell:
	@echo "Accessing ClickHouse shell..."
	docker exec -it clickhouse clickhouse-client

init-clickhouse:
	@echo "Initializing ClickHouse schema..."
	cat scripts/sql/init_clickhouse.sql | docker exec -i clickhouse clickhouse-client --multiquery
	@echo "✓ ClickHouse schema initialized successfully"

init-analytics:
	@echo "Initializing Analytics (Silver & Gold Layers)..."
	cat scripts/sql/init_analytics.sql | docker exec -i clickhouse clickhouse-client --multiquery
	@echo "✓ Analytics schema initialized successfully"

clean-clickhouse:
	@echo "Dropping all ClickHouse tables and views..."
	docker exec -i clickhouse clickhouse-client -q "DROP TABLE IF EXISTS cdc_queue; DROP VIEW IF EXISTS users_mv; DROP VIEW IF EXISTS products_mv; DROP VIEW IF EXISTS orders_mv; DROP VIEW IF EXISTS order_items_mv; DROP TABLE IF EXISTS users_history; DROP TABLE IF EXISTS products_history; DROP TABLE IF EXISTS orders_history; DROP TABLE IF EXISTS order_items_history;"
	@echo "✓ ClickHouse environment cleaned"

reset-clickhouse: clean-clickhouse init-clickhouse


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

setup-db:
	init-db seed-db