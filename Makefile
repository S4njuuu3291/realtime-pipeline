.PHONY: help build test clean docker-up docker-down docker-build

help:
	@echo "Real-time Crypto Pipeline - Available Commands"
	@echo ""
	@echo "  make build          Build Go applications"
	@echo "  make test           Run tests"
	@echo "  make clean          Remove build artifacts"
	@echo "  make docker-build   Build Docker images"
	@echo "  make docker-up      Start services (docker-compose)"
	@echo "  make docker-down    Stop services"
	@echo "  make run-producer   Run Kafka producer"
	@echo "  make run-processor  Run Spark processor"

build:
	@echo "Building applications..."
	cd cmd/producer && go build -o ../../bin/producer
	cd cmd/processor && go build -o ../../bin/processor

test:
	@echo "Running tests..."
	go test -v ./...

clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	go clean

docker-build:
	@echo "Building Docker images..."
	docker-compose -f deployments/docker/docker-compose.yml build

docker-up:
	@echo "Starting services..."
	docker-compose -f deployments/docker/docker-compose.yml up -d

docker-down:
	@echo "Stopping services..."
	docker-compose -f deployments/docker/docker-compose.yml down

run-producer: build
	@echo "Running producer..."
	./bin/producer

run-processor: build
	@echo "Running processor..."
	./bin/processor
