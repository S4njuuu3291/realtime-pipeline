# System Architecture Diagram

Diagram ini merepresentasikan arsitektur sistem level makro (infrastruktur perangkat lunak). Ini berbeda dengan arsitektur data; diagram ini menunjukkan aplikasi, *database*, dan *tools* apa saja yang digunakan serta bagaimana mereka terhubung dalam suatu *pipeline*.

```mermaid
graph LR
    %% Global Styles
    classDef storage fill:#2C3E50,stroke:#34495E,stroke-width:2px,color:#ECF0F1;
    classDef logic fill:#E67E22,stroke:#D35400,stroke-width:2px,color:#fff;
    classDef broker fill:#1B1B1B,stroke:#333,stroke-width:2px,color:#fff;
    classDef analytics fill:#F1C40F,stroke:#F39C12,stroke-width:2px,color:#333;
    classDef visualize fill:#16A085,stroke:#117A65,stroke-width:2px,color:#fff;

    subgraph SOURCE ["1. Source & Transactional"]
        gen([fa:fa-robot Order Generator])
        pg[(fa:fa-database PostgreSQL)]
    end

    subgraph CDC ["2. Real-time Ingestion"]
        go{{"fa:fa-code Go CDC Service"}}
    end

    subgraph STREAM ["3. Message Bus"]
        redpanda[("fa:fa-layer-group Redpanda / Kafka")]
    end

    subgraph WAREHOUSE ["4. Storage & OLAP"]
        ch[(fa:fa-chart-pie ClickHouse)]
    end

    subgraph BI ["5. Presentation"]
        superset[["fa:fa-dashboard Apache Superset"]]
    end

    %% Flow with cleaner labels
    gen -->|Simulated Activity| pg
    pg -.->|WAL Log Reading| go
    go ==>|Protobuf Events| redpanda
    redpanda ==>|Kafka Engine Stream| ch
    ch ---|Real-time Query| superset

    %% Class assignment
    class pg storage;
    class go logic;
    class redpanda broker;
    class ch analytics;
    class superset visualize;
```

### Penjelasan Komponen Sistem:

1. **Source System (PostgreSQL & Generator)**: Sebuah robot/skrip berjalan menyimulasikan transaksi E-Commerce (menambah user, membuat order, dsb) secara langsung ke *database* operasional PostgreSQL.
2. **Go CDC Ingestor**: Layanan *backend* khusus buatan sendiri (*custom*) menggunakan Golang yang bertugas menangkap setiap perubahan (CDC) di PostgreSQL. Data tersebut kemudian dibungkus dan dienkode secara efisien menggunakan Protobuf (`event.proto`).
3. **Redpanda / Kafka**: Berfungsi sebagai jalur antrean (*message broker*) berkecepatan tinggi yang menerima aliran *event* berformat Protobuf dari layanan Golang.
4. **ClickHouse (Data Warehouse)**: Bertindak sebagai konsumen (*consumer*) langsung dari Kafka menggunakan fitur *Kafka Engine*, lalu memproses data kotor melalui lapisan *Medallion* (Bronze -> Silver -> Gold).
5. **Apache Superset (BI & Visualization)**: Platform antarmuka untuk membaca tabel Gold di ClickHouse guna menampilkan *dashboard* analitik berkecepatan *sub-second* kepada *end-user*.
