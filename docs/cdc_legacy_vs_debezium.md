# CDC Legacy: Implementasi Manual `pglogrepl` (Go) vs Debezium

* **Epic:** CDC-4
* **Date:** 2026-08-02
* **Status:** Reference dokumentasi
* **Konteks:** Dokumentasi implementasi CDC lama berbasis `pglogrepl` (Go) dan perbandingannya dengan pendekatan Debezium yang diadopsi pada ADR-001.

---

## 1. Ringkasan

Pipeline CDC yang lama dibangun secara **manual** dengan library Go `pglogrepl`. Seluruh mekanisme logical replication — mulai dari membuat replication slot, memulai replikasi WAL, mendecode pesan logis, memetakan kolom ke entity, sampai mengirim event ke Redpanda — diimplementasikan langsung dalam satu file `main.go` pada service `cdc-ingestor`.

Pendekatan ini memberi kendali penuh, namun membutuhkan pemeliharaan tangan untuk setiap bagian protokol PostgreSQL.

---

## 2. Arsitektur Implementasi Legacy (`pglogrepl`)

```
PostgreSQL (WAL)
     │
     │  logical replication (pgoutput)
     ▼
cdc-ingestor (Go) ── pglogrepl / pgx ──► decode WAL ──► Protobuf CDCEvent ──► Redpanda
                                                        (topic: cdc-events)
```

### Komponen utama (`services/cdc-ingestor/main.go`)

| Langkah | Library / API | Fungsi |
|---------|---------------|--------|
| 1. Koneksi replikasi | `pgconn.Connect(...replication=database)` | Koneksi khusus replikasi ke Postgres |
| 2. Buat slot | `pglogrepl.CreateReplicationSlot(SLOT_NAME, "pgoutput")` | Buat replication slot (`cdc_slot`) bila belum ada |
| 3. Mulai replikasi | `pglogrepl.StartReplication(...PluginArgs)` | Mulai streaming WAL dengan publication `my_pub` |
| 4. Terima pesan | `conn.ReceiveMessage()` → `pgproto3.CopyData` | Loop baca pesan dari socket replikasi |
| 5. Handle keepalive (`k`) | `pglogrepl.ParsePrimaryKeepaliveMessage` + `SendStandbyStatusUpdate` | Ack LSN agar server tidak membuang WAL |
| 6. Parse data (`w`) | `pglogrepl.ParseXLogData` → `pglogrepl.Parse` | Decode XLogData & pesan logis |
| 7. Cache relasi | `RelationMessage` → `relationsCache` | Simpan metadata tabel (nama kolom, tipe) |
| 8. Buat event | `InsertMessage`/`UpdateMessage`/`DeleteMessage` | Petakan tuple → `pb.CDCEvent` |
| 9. Serialisasi | `proto.Marshal` | Encode Protobuf |
| 10. Kirim | `kafka-go` `Writer` (topic `cdc-events`) | Publikasikan ke Redpanda dengan key routing |

### Detail yang diimplementasi manual

- **Replication slot** `cdc_slot` — dibuat & dikelola aplikasi (menangani error `42710` = sudah ada).
- **Publication** `my_pub` — harus ada di Postgres; dipilih saat `StartReplication`.
- **Decoding** `pgoutput` — parsing pesan raw WAL (`RelationMessage`, `InsertMessage`, `UpdateMessage`, `DeleteMessage`).
- **Relation cache** — memetakan `RelationID` ke metadata tabel agar tuple bisa dipetakan ke kolom.
- **WAL ack (standby status update)** — menjaga agar LSN ter-proses tidak tertinggal / tidak ter-buang.
- **Transformasi event** — tuple → struct Protobuf `CDCEvent` dengan `table_name`, `operation`, `timestamp`, `after`, `before`.
- **Routing key** — memilih key partisi (mis. `getEntityID(after)`) untuk menjamin ordering per entity.

---

## 3. Perbandingan: `pglogrepl` Manual vs Debezium

| Aspek | `pglogrepl` Manual (legacy) | Debezium (Kafka Connect) |
|-------|------------------------------|--------------------------|
| **Replication slot** | Dikelola manual di kode | Dikelola otomatis oleh connector |
| **Decoding WAL** | Manual (`pgoutput`, parse pesan) | Otomatis (plugin + converter) |
| **Mapping kolom/relasi** | Manual (relation cache) | Otomatis (schema) |
| **Format event** | Format internal Protobuf (`CDCEvent`) | Format standar Debezium (JSON/Avro/Protobuf, berisi `before`/`after`/`source`/`op`/`ts_ms`) |
| **Penambahan tabel** | Perlu ubah kode + publication | Cukup ubah konfigurasi connector (`table.include.list`) |
| **Schema evolution** | Manual / rawan | Didukung (Schema Registry opsional) |
| **Monitoring** | Log aplikasi saja | REST API `GET /connectors/{name}/status` + metrik JMX, lag, offset |
| **Biaya maintenance** | Tinggi (kode sendiri) | Rendah (komponen mature) |
| **Multi-environment** | Sulit distandarkan | Mudah (config-as-code) |
| **Dependency** | Library `pglogrepl`, `pgx`, `kafka-go` | Kafka Connect + connector image |
| **Payload size** | Ringkas (Protobuf) | Lebih besar (JSON berisi metadata Debezium) |

### Perbedaan format event

**Legacy (`pb.CDCEvent`, Protobuf):**
```json
{
  "table_name": "orders",
  "operation": "INSERT",
  "timestamp": 1722500000000,
  "after": { "id": 1, "total": 250000.0 }
}
```

**Debezium (JSON, nilai inti):**
```json
{
  "schema": { "...": "..." },
  "payload": {
    "before": null,
    "after": { "id": 1, "total": 250000.0 },
    "source": {
      "db": "ecom_db",
      "table": "orders",
      "lsn": 123456,
      "ts_ms": 1722500000000
    },
    "op": "c",
    "ts_ms": 1722500000000
  }
}
```

> **Catatan konsekuensi** (sesuai ADR-001): payload Debezium lebih besar, sehingga **consumer ClickHouse perlu disesuaikan** — baik pola SQL parsing JSON, maupun validasi bahwa event sudah dalam format Debezium sebelum masuk tabel.

---

## 4. Kelebihan & Kekurangan

### `pglogrepl` Manual

**Kelebihan:**
- Kendali penuh atas format event (Protobuf ringkas).
- Tanpa komponen tambahan (hanya Go binary + library).
- Optimasi rendah-level (mis. async kafka batching, relation cache).

**Kekurangan:**
- Maintenance tinggi — semua mekanisme replikasi ditulis tangan.
- Perubahan schema butuh ubah kode.
- Monitoring terbatas (hanya log).
- Sulit scaling & standarisasi multi-environment.

### Debezium

**Kelebihan:**
- Mature, dipakai luas di industri.
- Otomatis mengelola slot, decoding, schema.
- Monitoring via REST API & metrik.
- Penambahan tabel via konfigurasi saja.
- Integrasi rapi dengan Redpanda/Kafka & Schema Registry.

**Kekurangan:**
- Komponen tambahan (Kafka Connect + connector).
- Payload lebih besar.
- Butuh penyesuaian consumer ClickHouse & pemahaman operasional baru.

---

## 5. Transisi: dari Legacy ke Debezium

1. Tambah service **Debezium Kafka Connect** (`quay.io/debezium/connect`) di `docker-compose.yml`.
2. Tambah konfigurasi connector PostgreSQL di `connectors/` (lihat `postgres-template.json` + target `make init-debezium`).
3. Hapus/decommission service `cdc-ingestor` (Go `pglogrepl`).
4. Sesuaikan consumer ClickHouse agar membaca format event Debezium (JSON) — topik Debezium bernama sesuai `topic.prefix` (mis. `ecommerce.public.orders`).
5. Pada tahap awal gunakan **JSON** untuk kemudahan debug; tahap lanjut bisa **Avro/Protobuf + Schema Registry**.

---

## 6. Referensi

- [ADR-001: Migrasi CDC dari Manual pglogrepl ke Debezium](adr/ADR-001-migration-to-dbz.md)
- Implementasi legacy: `services/cdc-ingestor/main.go`
- Konfigurasi connector: `connectors/postgres-template.json`
- Target setup: `make init-debezium` (Makefile)
