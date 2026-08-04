-- =========================================================
-- CDC QUEUE (Debezium JSON) -> ClickHouse
-- Tiap tabel Kafka membaca topic Debezium: ecommerce.public.<table>
-- Field Debezium: before, after, source, transaction, op, ts_ms, ts_us, ts_ns
-- =========================================================

-- ---------------------------------------------------------
-- 1) USERS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS cdc_queue_users
(
    before Tuple(
        id Nullable(Int32),
        email Nullable(String),
        full_name Nullable(String),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    after Tuple(
        id Nullable(Int32),
        email Nullable(String),
        full_name Nullable(String),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    source Tuple(
        version String,
        connector String,
        name String,
        ts_ms UInt64,
        snapshot String,
        db String,
        sequence String,
        ts_us String,
        ts_ns String,
        schema String,
        table String,
        txId Nullable(Int64),
        lsn UInt64,
        xmin Nullable(Int64),
        origin Nullable(String),
        origin_lsn Nullable(UInt64)
    ),
    transaction Nullable(String),
    op String,
    ts_ms UInt64,
    ts_us String,
    ts_ns String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list='redpanda:9092',
    kafka_topic_list='ecommerce.public.users',
    kafka_group_name='clickhouse_users',
    kafka_format='JSONEachRow';

CREATE TABLE IF NOT EXISTS users_history (
    id Int32,
    email String,
    full_name String,
    created_at String,
    updated_at String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE MATERIALIZED VIEW IF NOT EXISTS users_mv TO users_history AS
SELECT
    after.id AS id,
    after.email AS email,
    after.full_name AS full_name,
    after.created_at AS created_at,
    after.updated_at AS updated_at,
    op AS operation,
    ts_ms AS timestamp
FROM cdc_queue_users
WHERE op IN ('c', 'r', 'u', 'd') AND after.id IS NOT NULL;

-- ---------------------------------------------------------
-- 2) PRODUCTS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS cdc_queue_products
(
    before Tuple(
        id Nullable(Int32),
        name Nullable(String),
        category Nullable(String),
        brand Nullable(String),
        price Nullable(String),
        stock_quantity Nullable(Int32),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    after Tuple(
        id Nullable(Int32),
        name Nullable(String),
        category Nullable(String),
        brand Nullable(String),
        price Nullable(String),
        stock_quantity Nullable(Int32),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    source Tuple(
        version String,
        connector String,
        name String,
        ts_ms UInt64,
        snapshot String,
        db String,
        sequence String,
        ts_us String,
        ts_ns String,
        schema String,
        table String,
        txId Nullable(Int64),
        lsn UInt64,
        xmin Nullable(Int64),
        origin Nullable(String),
        origin_lsn Nullable(UInt64)
    ),
    transaction Nullable(String),
    op String,
    ts_ms UInt64,
    ts_us String,
    ts_ns String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list='redpanda:9092',
    kafka_topic_list='ecommerce.public.products',
    kafka_group_name='clickhouse_products',
    kafka_format='JSONEachRow';

CREATE TABLE IF NOT EXISTS products_history (
    id Int32,
    name String,
    category String,
    brand String,
    price String,
    stock_quantity Int32,
    created_at String,
    updated_at String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE MATERIALIZED VIEW IF NOT EXISTS products_mv TO products_history AS
SELECT
    after.id AS id,
    after.name AS name,
    after.category AS category,
    after.brand AS brand,
    after.price AS price,
    after.stock_quantity AS stock_quantity,
    after.created_at AS created_at,
    after.updated_at AS updated_at,
    op AS operation,
    ts_ms AS timestamp
FROM cdc_queue_products
WHERE op IN ('c', 'r', 'u', 'd') AND after.id IS NOT NULL;

-- ---------------------------------------------------------
-- 3) ORDERS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS cdc_queue_orders
(
    before Tuple(
        id Nullable(Int32),
        user_id Nullable(Int32),
        total_amount Nullable(String),
        status Nullable(String),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    after Tuple(
        id Nullable(Int32),
        user_id Nullable(Int32),
        total_amount Nullable(String),
        status Nullable(String),
        created_at Nullable(String),
        updated_at Nullable(String)
    ),
    source Tuple(
        version String,
        connector String,
        name String,
        ts_ms UInt64,
        snapshot String,
        db String,
        sequence String,
        ts_us String,
        ts_ns String,
        schema String,
        table String,
        txId Nullable(Int64),
        lsn UInt64,
        xmin Nullable(Int64),
        origin Nullable(String),
        origin_lsn Nullable(UInt64)
    ),
    transaction Nullable(String),
    op String,
    ts_ms UInt64,
    ts_us String,
    ts_ns String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list='redpanda:9092',
    kafka_topic_list='ecommerce.public.orders',
    kafka_group_name='clickhouse_orders',
    kafka_format='JSONEachRow';

CREATE TABLE IF NOT EXISTS orders_history (
    id Int32,
    user_id Int32,
    total_amount String,
    status String,
    created_at String,
    updated_at String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE MATERIALIZED VIEW IF NOT EXISTS orders_mv TO orders_history AS
SELECT
    after.id AS id,
    after.user_id AS user_id,
    after.total_amount AS total_amount,
    after.status AS status,
    after.created_at AS created_at,
    after.updated_at AS updated_at,
    op AS operation,
    ts_ms AS timestamp
FROM cdc_queue_orders
WHERE op IN ('c', 'r', 'u', 'd') AND after.id IS NOT NULL;

-- ---------------------------------------------------------
-- 4) ORDER_ITEMS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS cdc_queue_order_items
(
    before Tuple(
        id Nullable(Int32),
        order_id Nullable(Int32),
        product_id Nullable(Int32),
        quantity Nullable(Int32),
        unit_price Nullable(String),
        created_at Nullable(String)
    ),
    after Tuple(
        id Nullable(Int32),
        order_id Nullable(Int32),
        product_id Nullable(Int32),
        quantity Nullable(Int32),
        unit_price Nullable(String),
        created_at Nullable(String)
    ),
    source Tuple(
        version String,
        connector String,
        name String,
        ts_ms UInt64,
        snapshot String,
        db String,
        sequence String,
        ts_us String,
        ts_ns String,
        schema String,
        table String,
        txId Nullable(Int64),
        lsn UInt64,
        xmin Nullable(Int64),
        origin Nullable(String),
        origin_lsn Nullable(UInt64)
    ),
    transaction Nullable(String),
    op String,
    ts_ms UInt64,
    ts_us String,
    ts_ns String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list='redpanda:9092',
    kafka_topic_list='ecommerce.public.order_items',
    kafka_group_name='clickhouse_order_items',
    kafka_format='JSONEachRow';

CREATE TABLE IF NOT EXISTS order_items_history (
    id Int32,
    order_id Int32,
    product_id Int32,
    quantity Int32,
    unit_price String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

CREATE MATERIALIZED VIEW IF NOT EXISTS order_items_mv TO order_items_history AS
SELECT
    after.id AS id,
    after.order_id AS order_id,
    after.product_id AS product_id,
    after.quantity AS quantity,
    after.unit_price AS unit_price,
    op AS operation,
    ts_ms AS timestamp
FROM cdc_queue_order_items
WHERE op IN ('c', 'r', 'u', 'd') AND after.id IS NOT NULL;
