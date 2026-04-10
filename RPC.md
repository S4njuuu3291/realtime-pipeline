# Real-time Crypto Price Pipeline (RPC)

## High-Level Architecture

```
Binance WebSocket
      ↓
Kafka Producer (idempotent)
      ↓
Kafka Topic (crypto_prices)
      ↓
Spark Structured Streaming
      ↓
PostgreSQL (UPSERT, PK-based)
      ↓
Grafana Dashboard
```

## Data Source

### Binance WebSocket API

**Endpoint:**
```
wss://stream.binance.com:9443/ws/{symbol}@trade
```

**Schema:**

| Field | Type | Description |
|-------|------|-------------|
| symbol | string | Asset symbol (e.g. BTCUSDT) |
| price | float | Trade price |
| event_time | long | Event-time from source (Unix seconds) |
| processed_time | long | Ingestion time (Unix seconds) |

