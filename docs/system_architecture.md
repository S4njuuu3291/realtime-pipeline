# System Architecture Diagram

Diagram ini merepresentasikan arsitektur sistem level makro (infrastruktur perangkat lunak). Ini berbeda dengan arsitektur data; diagram ini menunjukkan aplikasi, *database*, dan *tools* apa saja yang digunakan serta bagaimana mereka terhubung dalam suatu *pipeline*.

```mermaid
graph TB
    %% Global Styles
    classDef source fill:#3498DB,stroke:#2980B9,stroke-width:2px,color:#fff;
    classDef logic fill:#E67E22,stroke:#D35400,stroke-width:2px,color:#fff;
    classDef broker fill:#8E44AD,stroke:#6C3483,stroke-width:2px,color:#fff;
    classDef analytics fill:#F1C40F,stroke:#F39C12,stroke-width:2px,color:#333;
    classDef visualize fill:#1ABC9C,stroke:#16A085,stroke-width:2px,color:#fff;
    classDef monitor fill:#E74C3C,stroke:#C0392B,stroke-width:2px,color:#fff;
    classDef groupTitle fill:#F8F9FA,stroke:#CCC,stroke-width:1px,color:#333;

    subgraph SOURCE["1. Source & Transactional"]
        direction TB
        gen(["🖥️  Order Generator (Faker)"]) --> pg[("🐘  PostgreSQL WAL")]       
    end
    class SOURCE groupTitle;

    subgraph INGESTION["2. Real-time Ingestion"]
        go{{"⚙️  Go CDC Ingestor"}}
    end
    class INGESTION groupTitle;

    subgraph BROKER["3. Message Bus"]
        redpanda[("📦  Redpanda / Kafka")]
    end
    class BROKER groupTitle;

    subgraph WAREHOUSE["4. Storage & OLAP"]
        ch[("📊  ClickHouse")]
    end
    class WAREHOUSE groupTitle;

    subgraph BI["5. Presentation"]
        superset[["📈  Apache Superset"]]
    end
    class BI groupTitle;

    subgraph OBSERVABILITY["6. Observability"]
        direction TB
        node_exporter[🔧 Node Exporter] -.->|Hardware Metrics| prom[("📉  Prometheus")]
        pg_exporter[🐘 Postgres Exporter] -.->|Postgres Metrics| prom
        prom ---|Data Source| grafana{{"👁️  Grafana"}}
    end
    class OBSERVABILITY groupTitle;

    %% Main Pipeline Flow
    pg -.->|WAL Logical Replication| go
    go ==>|Protobuf Events| redpanda
    redpanda ==>|Kafka Engine Stream| ch
    ch ---|Real-time Query| superset

    %% Class assignment
    class gen source;
    class pg source;
    class go logic;
    class redpanda broker;
    class ch analytics;
    class superset visualize;
    class node_exporter,pg_exporter,prom,grafana monitor;
```

### Penjelasan Komponen Sistem:

1. **Source System (PostgreSQL & Generator)**: Sebuah robot/skrip berjalan menyimulasikan transaksi E-Commerce (menambah user, membuat order, dsb) secara langsung ke *database* operasional PostgreSQL.
2. **Go CDC Ingestor**: Layanan *backend* khusus buatan sendiri (*custom*) menggunakan Golang yang bertugas menangkap setiap perubahan (CDC) di PostgreSQL. Data tersebut kemudian dibungkus dan dienkode secara efisien menggunakan Protobuf (`event.proto`).
3. **Redpanda / Kafka**: Berfungsi sebagai jalur antrean (*message broker*) berkecepatan tinggi yang menerima aliran *event* berformat Protobuf dari layanan Golang.
4. **ClickHouse (Data Warehouse)**: Bertindak sebagai konsumen (*consumer*) langsung dari Kafka menggunakan fitur *Kafka Engine*, lalu memproses data kotor melalui lapisan *Medallion* (Bronze -> Silver -> Gold).
5. **Apache Superset (BI & Visualization)**: Platform antarmuka untuk membaca tabel Gold di ClickHouse guna menampilkan *dashboard* analitik berkecepatan *sub-second* kepada *end-user*.
6. **Observability (Prometheus + Grafana + Exporters)**: Memonitoring kesehatan pipeline secara *real-time* — WAL Lag dari PostgreSQL, resource usage dari Node Exporter, dan metrik Postgres dari Postgres Exporter — semuanya divisualisasikan di Grafana.
