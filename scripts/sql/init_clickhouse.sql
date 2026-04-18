-- ==========================================================
-- CLICKHOUSE INITIALIZATION SCRIPT (FIXED - SCD TYPE 2)
-- ==========================================================

-- 1. TABEL PENYIMPANAN AKHIR
CREATE TABLE IF NOT EXISTS users_history (
    id Int32,
    email String,
    full_name String,
    created_at String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE TABLE IF NOT EXISTS products_history (
    id Int32,
    name String,
    category String,
    brand String,
    price String,
    stock_quantity Int32,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE TABLE IF NOT EXISTS orders_history (
    id Int32,
    user_id Int32,
    total_amount String,
    status String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

-- 2. TABEL ANTREAN KAFKA (URUTAN KOLOM HARUS SESUAI PROTO)
CREATE TABLE IF NOT EXISTS cdc_queue (
    table_name String,    -- Index 1
    operation String,     -- Index 2
    timestamp Int64,      -- Index 3
    -- Index 4: Before (Kita definisikan agar index sinkron)
    before Tuple(
        user Tuple(id Int32, email String, full_name String, created_at String),
        product Tuple(id Int32, name String, category String, brand String, price String, stock_quantity Int32),
        order Tuple(id Int32, user_id Int32, total_amount String, status String)
    ),
    -- Index 5: After
    after Tuple(
        user Tuple(id Int32, email String, full_name String, created_at String),
        product Tuple(id Int32, name String, category String, brand String, price String, stock_quantity Int32),
        order Tuple(id Int32, user_id Int32, total_amount String, status String)
    )
) ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'cdc-events',
    kafka_group_name = 'clickhouse_cdc_group_v3',
    kafka_format = 'ProtobufSingle',
    kafka_schema = 'event.proto:CDCEvent',
    kafka_skip_broken_messages = 1;

-- 3. MATERIALIZED VIEWS

CREATE MATERIALIZED VIEW IF NOT EXISTS users_mv TO users_history AS
SELECT 
    after.user.id AS id, after.user.email AS email, after.user.full_name AS full_name, after.user.created_at AS created_at,
    operation, timestamp
FROM cdc_queue WHERE table_name = 'users';

CREATE MATERIALIZED VIEW IF NOT EXISTS products_mv TO products_history AS
SELECT 
    after.product.id AS id, after.product.name AS name, after.product.category AS category, after.product.brand AS brand, after.product.price AS price, after.product.stock_quantity AS stock_quantity,
    operation, timestamp
FROM cdc_queue WHERE table_name = 'products';

CREATE MATERIALIZED VIEW IF NOT EXISTS orders_mv TO orders_history AS
SELECT 
    after.order.id AS id, after.order.user_id AS user_id, after.order.total_amount AS total_amount, after.order.status AS status,
    operation, timestamp
FROM cdc_queue WHERE table_name = 'orders';
