-- ---------------------------------------------------------
-- 1) USERS
-- ---------------------------------------------------------

CREATE TABLE IF NOT EXISTS users_history (
    id Int32,
    email String,
    full_name String,
    created_at Int64,
    updated_at Int64,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

-- ---------------------------------------------------------
-- 2) PRODUCTS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS products_history (
    id Int32,
    name String,
    category String,
    brand String,
    price String,
    stock_quantity Int32,
    created_at Int64,
    updated_at Int64,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

-- ---------------------------------------------------------
-- 3) ORDERS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders_history (
    id Int32,
    user_id Int32,
    total_amount String,
    status String,
    created_at Int64,
    updated_at Int64,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);

-- ---------------------------------------------------------
-- 4) ORDER_ITEMS
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_items_history (
    id Int32,
    order_id Int32,
    product_id Int32,
    quantity Int32,
    unit_price String,
    operation String,
    timestamp Int64
) ENGINE = MergeTree() ORDER BY (id, timestamp);