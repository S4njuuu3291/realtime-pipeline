# System Architecture Diagram

Diagram ini merepresentasikan arsitektur sistem level makro (infrastruktur perangkat lunak). Ini berbeda dengan arsitektur data; diagram ini menunjukkan aplikasi, *database*, dan *tools* apa saja yang digunakan serta bagaimana mereka terhubung dalam suatu *pipeline*.

```mermaid
flowchart LR
    %% Styles
    classDef source fill:#3498DB,stroke:#2980B9,stroke-width:2px,color:#fff;
    classDef logic fill:#E67E22,stroke:#D35400,stroke-width:2px,color:#fff;
    classDef broker fill:#8E44AD,stroke:#6C3483,stroke-width:2px,color:#fff;
    classDef analytics fill:#F1C40F,stroke:#F39C12,stroke-width:2px,color:#333;
    classDef visualize fill:#1ABC9C,stroke:#16A085,stroke-width:2px,color:#fff;
    classDef monitor fill:#E74C3C,stroke:#C0392B,stroke-width:2px,color:#fff;

    %% ========== MAIN FLOW ==========
    subgraph src ["📦 SOURCE"]
        gen(["Faker"])
        pg[("PostgreSQL")]
        gen --> pg
    end

    subgraph ingest ["⚡ INGESTION"]
        go{{"Go CDC Ingestor"}}
    end

    subgraph broker ["📨 MESSAGE BUS"]
        redpanda[("Redpanda/Kafka")]
    end

    subgraph olap ["💾 OLAP"]
        ch[("ClickHouse")]
    end

    subgraph bi ["📊 BI"]
        superset[["Superset"]]
    end

    %% Connections antar subgraph (pendek karena subgraph sudah berisi node sendiri)
    pg -->|WAL| go
    go -->|Protobuf| redpanda
    redpanda -->|Kafka Engine| ch
    ch -->|Query| superset

    %% ========== OBSERVABILITY ==========
    subgraph obs ["🔍 OBSERVABILITY"]
        node_exporter[Node Exporter]
        pg_exporter[Postgres Exporter]
        prom[Prometheus]
        grafana[Grafana]
        
        node_exporter --> prom
        pg_exporter --> prom
        prom --> grafana
    end

    %% Observability connections (dotted, ga ganggu main flow)
    pg -.-> pg_exporter
    pg_exporter -.-> prom

    %% Classes
    class gen,pg source;
    class go logic;
    class redpanda broker;
    class ch analytics;
    class superset visualize;
    class node_exporter,pg_exporter,prom,grafana monitor;
```

### Penjelasan Komponen Sistem:

1. **Source** — **Faker** (traffic generator) menyimulasikan transaksi E-Commerce ke **PostgreSQL**. PostgreSQL diaktifkan WAL *logical replication* untuk CDC.
2. **Ingestion** — **Go CDC Ingestor** membaca WAL PostgreSQL secara *real-time*, menserialisasi event ke **Protobuf**, lalu mengirimkannya ke Redpanda.
3. **Message Bus** — **Redpanda** (Kafka-compatible) menerima event Protobuf dengan 3 partisi untuk *row-level ordering*.
4. **OLAP** — **ClickHouse** menggunakan *Kafka Engine* langsung consume dari Redpanda, lalu memproses data ke layer Medallion (Bronze → Silver → Gold).
5. **BI** — **Apache Superset** membaca tabel Gold (OBT) untuk dashboard analitik E-Commerce.
6. **Observability** — **Node Exporter** & **Postgres Exporter** mengirim metrik ke **Prometheus**, lalu divisualisasikan di **Grafana** — termasuk WAL Lag, CPU, memory, disk.
