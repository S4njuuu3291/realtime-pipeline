-- ==========================================================
-- CLICKHOUSE ANALYTICS SCRIPT (SILVER & GOLD LAYERS)
-- ==========================================================

-- ----------------------------------------------------------
-- 1. SILVER LAYER (Virtual Current State)
-- Kita membuat View yang hanya mengambil versi terbaru (argMax)
-- ----------------------------------------------------------

CREATE VIEW IF NOT EXISTS vw_current_users AS
SELECT 
    toUInt64(id) AS id, 
    argMax(email, timestamp) AS email, 
    argMax(full_name, timestamp) AS full_name
FROM users_history
GROUP BY id;

CREATE VIEW IF NOT EXISTS vw_current_products AS
SELECT 
    toUInt64(id) AS id, 
    argMax(name, timestamp) AS name, 
    argMax(category, timestamp) AS category, 
    argMax(brand, timestamp) AS brand,
    argMax(price, timestamp) AS price
FROM products_history
GROUP BY id;

CREATE VIEW IF NOT EXISTS vw_current_orders AS
SELECT 
    toUInt64(id) AS id, 
    argMax(user_id, timestamp) AS user_id, 
    argMax(status, timestamp) AS status
FROM orders_history
GROUP BY id;

-- ----------------------------------------------------------
-- 2. DICTIONARIES (Cached Silver Layer untuk Fast Joins)
-- Ini memuat data 'Current State' ke dalam RAM ClickHouse
-- ----------------------------------------------------------

CREATE DICTIONARY IF NOT EXISTS dict_users (
    id UInt64,
    email String,
    full_name String
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(HOST 'localhost' PORT 9000 USER 'default' PASSWORD '' DB 'default' TABLE 'vw_current_users'))
LAYOUT(HASHED())
LIFETIME(MIN 1 MAX 5);

CREATE DICTIONARY IF NOT EXISTS dict_products (
    id UInt64,
    name String,
    category String,
    brand String,
    price String
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(HOST 'localhost' PORT 9000 USER 'default' PASSWORD '' DB 'default' TABLE 'vw_current_products'))
LAYOUT(HASHED())
LIFETIME(MIN 1 MAX 5);

CREATE DICTIONARY IF NOT EXISTS dict_orders (
    id UInt64,
    user_id Int32,
    status String
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(HOST 'localhost' PORT 9000 USER 'default' PASSWORD '' DB 'default' TABLE 'vw_current_orders'))
LAYOUT(HASHED())
LIFETIME(MIN 1 MAX 5);

-- ----------------------------------------------------------
-- 3. GOLD LAYER (One Big Table / OBT)
-- Tabel lebar untuk disajikan ke Superset / Metabase
-- ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS analytics_sales_obt (
    order_item_id Int32,
    order_id Int32,
    user_id Int32,
    user_full_name String,
    product_id Int32,
    product_name String,
    product_category String,
    product_brand String,
    quantity Int32,
    unit_price String,
    order_status String,
    timestamp Int64
) ENGINE = MergeTree()
ORDER BY (timestamp, order_item_id);

-- ----------------------------------------------------------
-- 4. OBT MATERIALIZED VIEW (Real-time Stream Processor)
-- Pipa yang memadukan data dari Kafka dengan Dictionaries RAM
-- ----------------------------------------------------------

CREATE MATERIALIZED VIEW IF NOT EXISTS analytics_sales_mv TO analytics_sales_obt AS
SELECT 
    after.order_item.id AS order_item_id,
    after.order_item.order_id AS order_id,
    
    -- Ambil User ID dari Dictionary Orders
    dictGet('dict_orders', 'user_id', toUInt64(after.order_item.order_id)) AS user_id,
    
    -- Ambil Nama User dari Dictionary Users menggunakan User ID yang didapat di atas
    dictGet('dict_users', 'full_name', toUInt64(dictGet('dict_orders', 'user_id', toUInt64(after.order_item.order_id)))) AS user_full_name,
    
    after.order_item.product_id AS product_id,
    
    -- Ambil Data Produk dari Dictionary Products
    dictGet('dict_products', 'name', toUInt64(after.order_item.product_id)) AS product_name,
    dictGet('dict_products', 'category', toUInt64(after.order_item.product_id)) AS product_category,
    dictGet('dict_products', 'brand', toUInt64(after.order_item.product_id)) AS product_brand,
    
    after.order_item.quantity AS quantity,
    after.order_item.unit_price AS unit_price,
    
    -- Ambil Status Order
    dictGet('dict_orders', 'status', toUInt64(after.order_item.order_id)) AS order_status,
    
    timestamp
FROM cdc_queue
WHERE table_name = 'order_items' AND operation != 'DELETE';
