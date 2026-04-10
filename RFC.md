## 📝 RFC: Enterprise E-Commerce CDC & Analytics Platform

**Author:** Sanju  
**Status:** Draft  
**Version:** 2.0  

### 1. Project Overview
The goal of this project is to build a high-performance, near real-time data platform that synchronizes transactional e-commerce data from a microservice to an analytical data warehouse. This platform must handle schema changes, hard deletes, and support dimensional modeling for business intelligence.

---

### 2. System Architecture
The system will follow a decoupled, event-driven architecture:
1.  **Source App (FastAPI):** Simulates user behavior (Orders, Stock Updates).
2.  **Primary DB (Postgres):** Stores transactional state with `wal_level=logical`.
3.  **CDC Ingestor (Go):** Uses `pglogrepl` to stream WAL events.
4.  **Message Broker (Redpanda):** Provides a fault-tolerant buffer for events.
5.  **Data Warehouse (ClickHouse):** Stores the final Star Schema (Facts and Dimensions).



---

### 3. Full Scope of Work

#### Phase 1: The Source Ecosystem
* **FastAPI Microservice:** Build endpoints for `/orders`, `/products`, and `/users`.
* **Synthetic Traffic:** Use **Faker** to generate 10–50 transactions per minute.
* **Transactional Integrity:** Ensure that a "Purchase" updates both the `orders` and `products` table in a single Postgres transaction.

#### Phase 2: The Ingestion Layer (The "Go" Brain)
* **CDC Implementation:** Connect to Postgres logical replication slots.
* **Event Filtering:** Parse the WAL data to identify `INSERT`, `UPDATE`, and `DELETE` events.
* **Protobuf Serialization:** Convert raw database rows into binary Protobuf messages before sending them to Redpanda.

#### Phase 3: The Analytics Warehouse (The Dimensional Model)
* **Staging Layer:** Raw tables in ClickHouse that mirror the Postgres schema.
* **Fact Table (`fct_orders`):** A denormalized table for sales analysis.
* **SCD Type 2 (`dim_products`):** Track price history and product name changes.
* **Materialized Views:** Use ClickHouse features to automatically roll up hourly revenue.

---

### 4. Technical Constraints & Challenges
* **Latency:** The "Commit-to-Warehouse" time must be less than 5 seconds.
* **Idempotency:** The pipeline must handle duplicate events without corrupting the Fact tables.
* **Backfill:** The system must be able to "re-read" old data if the warehouse is wiped.

---