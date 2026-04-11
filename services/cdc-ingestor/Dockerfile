# Tahap Pembangunan (Builder Stage)
FROM golang:alpine AS builder

# Atur direktori kerja dalam kontainer
WORKDIR /app

# Salin modul dan unduh dependensi
COPY go.mod go.sum ./
RUN go mod download

# Salin seluruh kode Golang ke dalam
COPY . .

# Build aplikasi menjadi file binary tunggal dengan performa tinggi
RUN CGO_ENABLED=0 GOOS=linux go build -o cdc-ingestor main.go

# Tahap Produksi (Final Stage) - Sangat Ringan
FROM alpine:latest

WORKDIR /app

# Ambil hasil binary yang sudah di build dari tahap sebelumnya
COPY --from=builder /app/cdc-ingestor .

# Jalankan programnya
CMD ["./cdc-ingestor"]
