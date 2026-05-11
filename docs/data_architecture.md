# Data Architecture Diagram (Medallion Architecture)

Diagram berikut menunjukkan bagaimana aliran data bergerak dalam arsitektur Medallion Anda, mulai dari ingest data melalui Kafka hingga ke lapisan Gold berupa *One Big Table* (OBT) di ClickHouse.

```mermaid
flowchart TD
    %% Subgraph Styles
    classDef layerStyle fill:#fdfdfd,stroke:#333,stroke-width:1px;
    classDef streamStyle fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;

    subgraph INGEST ["1. Ingestion Layer"]
        cdc[("fa:fa-stream Event Queue<br/>(Message Broker)")]
    end

    subgraph BRONZE ["2. Bronze Layer (Historical Logs)"]
        direction LR
        uh[("User Logs")]
        ph[("Product Logs")]
        oh[("Order Logs")]
        oih[("Order Item Logs")]
    end

    subgraph SILVER ["3. Silver Layer (Current State & Cache)"]
        direction TB
        subgraph VIEWS ["Deduplicated State (Latest)"]
            direction LR
            vu["Current Users"]
            vp["Current Products"]
            vo["Current Orders"]
        end
        
        subgraph CACHE ["In-Memory Lookup Cache"]
            direction LR
            du[("User Cache")]
            dp[("Product Cache")]
            do[("Order Cache")]
        end
    end

    subgraph GOLD ["4. Gold Layer (Analytics Ready)"]
        enrich_proc{{"fa:fa-bolt Enrichment Logic<br/>(Stream Processor)"}}
        obt[("Sales Analytics Table<br/>(One Big Table)")]
    end

    %% --- DATA FLOW ---

    %% Kafka to Bronze
    cdc ==>|Persistent Storage| uh
    cdc ==>|Persistent Storage| ph
    cdc ==>|Persistent Storage| oh
    cdc ==>|Persistent Storage| oih

    %% Bronze to Silver
    uh -.->|Deduplicate| vu
    ph -.->|Deduplicate| vp
    oh -.->|Deduplicate| vo

    %% Silver Views to Cache
    vu -.->|Sync to RAM| du
    vp -.->|Sync to RAM| dp
    vo -.->|Sync to RAM| do

    %% Real-time Enrichment Path
    cdc -- "Raw Events" --> enrich_proc
    
    %% Lookups
    du -. "Fetch User Info" .-> enrich_proc
    dp -. "Fetch Product Info" .-> enrich_proc
    do -. "Fetch Order Info" .-> enrich_proc

    %% Final Output
    enrich_proc ==>|Enriched Records| obt

    class INGEST,BRONZE,SILVER,GOLD layerStyle;
    class cdc,enrich_proc streamStyle;
```



### Penjelasan Lapisan (Layers):

1. **Bronze Layer (Raw Historical Data)**: Menyimpan seluruh log kejadian (insert/update/delete) apa adanya. Berfungsi sebagai arsip atau sumber data historis menggunakan tabel tipe `MergeTree` biasa.
2. **Silver Layer (Current State & Cached)**:
   - Terdiri dari **View** (`vw_current_*`) yang menggunakan fungsi `argMax` untuk secara dinamis mencari data baris terakhir berdasarkan waktu (*timestamp*), sehingga menyingkirkan duplikasi log dari Bronze.
   - Terdiri dari **Dictionaries** (`dict_*`) yang menarik hasil View tersebut lalu menyimpannya di RAM (*Memory*). Ini krusial agar pencarian data (*lookup* / *join*) saat dipanggil jutaan kali dari kafka bisa berjalan dalam sepersekian milidetik.
3. **Gold Layer (One Big Table / OBT)**: Menggunakan fitur Materialized View (`analytics_sales_mv`) untuk membaca arus data *order_items* secara *real-time* langsung dari antrean Kafka (`cdc_queue`). Saat data lewat, ia mengambil fungsi *dictGet* untuk meminta info pelengkap dari Silver Dictionaries (RAM) kemudian menggabungkannya ke tabel lebar `analytics_sales_obt` yang siap dihubungkan langsung ke *dashboard* Superset.
