# =========================================================
# Stage 1: Build
# =========================================================
FROM golang:1.26-alpine AS builder

# Build essentials (cgo untuk clickhouse-go, walaupun biasanya pure-Go)
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

# Copy go.mod & go.sum dulu untuk layer caching dependency
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY main.go ./

# Build static binary (tanpa cgo agar bisa jalan di scratch/distroless)
RUN CGO_ENABLED=0 GOOS=linux go build -o /consumer .

# =========================================================
# Stage 2: Runtime (image kecil)
# =========================================================
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

WORKDIR /app

# Salin binary dari stage builder
COPY --from=builder /consumer /app/consumer

# Healthcheck sederhana: prosesnya harus hidup (tidak ada HTTP endpoint,
# jadi cek proses via pgrep)
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD pgrep consumer || exit 1

# Env default (dapat di-override dari docker-compose)
ENV KAFKA_BROKERS=redpanda:9092
ENV TOPIC=ecommerce.public.orders
ENV GROUP_ID=go-consumer-group
ENV CLIENT_ID=my-go-consumer
ENV CLICKHOUSE_USER=default
ENV CLICKHOUSE_DB=default

CMD ["/app/consumer"]
