-- ==========================================================
-- CLICKHOUSE INITIALIZATION SCRIPT (FIXED - ALL TABLES)
-- ==========================================================

-- 1. TABEL PENYIMPANAN AKHIR
CREATE TABLE IF NOT EXISTS users_history (
    id Int32, email String, full_name String, created_at String, operation String, timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE TABLE IF NOT EXISTS products_history (
    id Int32, name String, category String, brand String, price String, stock_quantity Int32, operation String, timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE TABLE IF NOT EXISTS orders_history (
    id Int32, user_id Int32, total_amount String, status String, operation String, timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE TABLE IF NOT EXISTS order_items_history (
    id Int32, order_id Int32, product_id Int32, quantity Int32, unit_price String, operation String, timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

-- 2. TABEL ANTREAN KAFKA (DIBUAT LEBIH FLEKSIBEL DENGAN NULLABLE)
CREATE TABLE IF NOT EXISTS cdc_queue (
    table_name String,
    operation String,
    timestamp Int64,
    before Tuple(
        user Tuple(id Nullable(Int32), email Nullable(String), full_name Nullable(String), created_at Nullable(String), updated_at Nullable(String)),
        product Tuple(id Nullable(Int32), name Nullable(String), category Nullable(String), brand Nullable(String), price Nullable(String), stock_quantity Nullable(Int32), created_at Nullable(String), updated_at Nullable(String)),
        order Tuple(id Nullable(Int32), user_id Nullable(Int32), total_amount Nullable(String), status Nullable(String), created_at Nullable(String), updated_at Nullable(String)),
        order_item Tuple(id Nullable(Int32), order_id Nullable(Int32), product_id Nullable(Int32), quantity Nullable(Int32), unit_price Nullable(String), created_at Nullable(String))
    ),
    after Tuple(
        user Tuple(id Nullable(Int32), email Nullable(String), full_name Nullable(String), created_at Nullable(String), updated_at Nullable(String)),
        product Tuple(id Nullable(Int32), name Nullable(String), category Nullable(String), brand Nullable(String), price Nullable(String), stock_quantity Nullable(Int32), created_at Nullable(String), updated_at Nullable(String)),
        order Tuple(id Nullable(Int32), user_id Nullable(Int32), total_amount Nullable(String), status Nullable(String), created_at Nullable(String), updated_at Nullable(String)),
        order_item Tuple(id Nullable(Int32), order_id Nullable(Int32), product_id Nullable(Int32), quantity Nullable(Int32), unit_price Nullable(String), created_at Nullable(String))
    )
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'cdc-events',
    kafka_group_name = 'clickhouse_cdc_group_v16',
    kafka_format = 'ProtobufSingle',
    kafka_schema = 'event.proto:cdc.CDCEvent',
    kafka_skip_broken_messages = 0;

-- 3. MATERIALIZED VIEWS (DENGAN ASUMSI NOT NULL UNTUK KEAMANAN DATA)

CREATE MATERIALIZED VIEW IF NOT EXISTS users_mv TO users_history AS
SELECT
    assumeNotNull(after.user.id) AS id,
    assumeNotNull(after.user.email) AS email,
    assumeNotNull(after.user.full_name) AS full_name,
    assumeNotNull(after.user.created_at) AS created_at,
    operation,
    timestamp
FROM cdc_queue WHERE table_name = 'users';

CREATE MATERIALIZED VIEW IF NOT EXISTS products_mv TO products_history AS
SELECT
    assumeNotNull(after.product.id) AS id,
    assumeNotNull(after.product.name) AS name,
    assumeNotNull(after.product.category) AS category,
    assumeNotNull(after.product.brand) AS brand,
    assumeNotNull(after.product.price) AS price,
    assumeNotNull(after.product.stock_quantity) AS stock_quantity,
    operation,
    timestamp
FROM cdc_queue WHERE table_name = 'products';

CREATE MATERIALIZED VIEW IF NOT EXISTS orders_mv TO orders_history AS
SELECT
    assumeNotNull(after.order.id) AS id,
    assumeNotNull(after.order.user_id) AS user_id,
    assumeNotNull(after.order.total_amount) AS total_amount,
    assumeNotNull(after.order.status) AS status,
    operation,
    timestamp
FROM cdc_queue WHERE table_name = 'orders';

CREATE MATERIALIZED VIEW IF NOT EXISTS order_items_mv TO order_items_history AS
SELECT
    assumeNotNull(after.order_item.id) AS id,
    assumeNotNull(after.order_item.order_id) AS order_id,
    assumeNotNull(after.order_item.product_id) AS product_id,
    assumeNotNull(after.order_item.quantity) AS quantity,
    assumeNotNull(after.order_item.unit_price) AS unit_price,
    operation,
    timestamp
FROM cdc_queue WHERE table_name = 'order_items';
