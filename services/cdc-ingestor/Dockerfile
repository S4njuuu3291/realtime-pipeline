# --- Tahap Pembangunan (Builder Stage) ---
FROM golang:1.25-alpine AS builder

# Install git jika dependensi Go mengambil dari repo private/public
RUN apk add --no-cache git

# Atur direktori kerja dalam kontainer
WORKDIR /app

# 1. Salin file modul terlebih dahulu (Optimasi Cache Docker)
# Menggunakan wildcard 'go.sum*' agar tidak error jika file belum ada
COPY go.mod go.sum* ./

# 2. Download dependensi
RUN go mod download

# 3. Salin seluruh kode sumber dari context build
COPY . .

# 4. Build aplikasi
RUN CGO_ENABLED=0 GOOS=linux go build -o cdc-ingestor .

# --- Tahap Produksi (Final Stage) ---
FROM alpine:latest

# Install ca-certificates agar bisa akses HTTPS (penting untuk API/DB Cloud)
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Ambil binary dari stage builder
COPY --from=builder /app/cdc-ingestor .

# Jika ada file .env atau config yang dibutuhkan saat runtime:
# COPY .env . 

# Jalankan program
ENTRYPOINT ["./cdc-ingestor"]