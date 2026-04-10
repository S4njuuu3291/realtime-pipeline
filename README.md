# Real-time Crypto Price Pipeline

Real-time streaming pipeline untuk ingestion and processing data harga cryptocurrency dari Binance WebSocket, menggunakan Kafka untuk streaming, Spark untuk processing, dan PostgreSQL untuk storage.

## Architecture

```
Binance WebSocket
      ↓
Kafka Producer (idempotent)
      ↓
Kafka Topic (crypto_prices)
      ↓
Spark Structured Streaming
      ↓
PostgreSQL (UPSERT)
      ↓
Grafana Dashboard
```

**Full documentation:** [`RPC.md`](RPC.md)

## Tech Stack

- **Producer:** Go (Binance WebSocket)
- **Streaming:** Apache Kafka
- **Processing:** Apache Spark Structured Streaming
- **Storage:** PostgreSQL
- **Visualization:** Grafana
- **Containerization:** Docker & Docker Compose

## Project Structure

```
realtime-pipeline/
├── cmd/                    # Applications
│   ├── producer/          # Kafka producer (Binance WebSocket)
│   └── processor/         # Spark job scheduler
├── internal/              # Internal packages
│   └── utils/            # Helper functions
├── deployments/           # Infrastructure
│   └── docker/           # Docker Compose, images
├── scripts/              # Utility scripts
├── RPC.md                # Design documentation
├── Makefile              # Build targets
├── go.mod                # Go module definition
└── .gitignore            # Git ignore rules
```

## Quick Start

### Prerequisites

- Go 1.23+
- Docker & Docker Compose
- Make

### Setup

```bash
# Clone repo
git clone https://github.com/S4njuuu3291/realtime-pipeline.git
cd realtime-pipeline

# Build
make build

# Run with Docker
docker-compose up -d
```

### Services

| Service | Port | Role |
|---------|------|------|
| Kafka | 9092 | Message queue |
| PostgreSQL | 5432 | Data storage |
| Grafana | 3000 | Visualization |

## Development

```bash
make help          # Show all commands
make build         # Build all apps
make test          # Run tests
make docker-up     # Start services
make docker-down   # Stop services
```

## License

Apache 2.0