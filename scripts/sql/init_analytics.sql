-- ==========================================================
-- CLICKHOUSE ANALYTICS SCRIPT (SILVER & GOLD LAYERS)
-- Arsitektur: Query-Time Join (Anti Race Condition)
-- ==========================================================

-- ----------------------------------------------------------
-- 1. SILVER LAYER (Virtual Current State)
-- View yang hanya mengambil versi terbaru (argMax)
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
    argMax(total_amount, timestamp) AS total_amount,
    argMax(status, timestamp) AS status
FROM orders_history
GROUP BY id;

CREATE VIEW IF NOT EXISTS vw_current_order_items AS
SELECT 
    toUInt64(id) AS id,
    argMax(order_id, timestamp) AS order_id,
    argMax(product_id, timestamp) AS product_id,
    argMax(quantity, timestamp) AS quantity,
    argMax(unit_price, timestamp) AS unit_price,
    argMax(timestamp, timestamp) AS event_timestamp
FROM order_items_history
GROUP BY id;

-- ----------------------------------------------------------
-- 2. GOLD LAYER (One Big Table - Query-Time Join)
-- 
-- Ini adalah VIEW, bukan TABLE.
-- Data SELALU konsisten karena join dilakukan saat query,
-- bukan saat data masuk (yang rentan race condition).
-- Untuk dashboard Superset, VIEW bekerja persis sama.
-- ----------------------------------------------------------

CREATE VIEW IF NOT EXISTS analytics_sales_obt AS
SELECT 
    toInt32(oi.id) AS order_item_id,
    toInt32(oi.order_id) AS order_id,
    toInt32(o.user_id) AS user_id,
    u.full_name AS user_full_name,
    toInt32(oi.product_id) AS product_id,
    p.name AS product_name,
    p.category AS product_category,
    p.brand AS product_brand,
    toInt32(oi.quantity) AS quantity,
    oi.unit_price,
    o.total_amount AS order_total_amount,
    o.status AS order_status,
    oi.event_timestamp AS timestamp
FROM vw_current_order_items oi
LEFT JOIN vw_current_orders o ON toUInt64(oi.order_id) = o.id
LEFT JOIN vw_current_users u ON toUInt64(o.user_id) = u.id
LEFT JOIN vw_current_products p ON toUInt64(oi.product_id) = p.id;
