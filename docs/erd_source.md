erDiagram
    USERS ||--o{ ORDERS : "places"
    PRODUCTS ||--o{ ORDER_ITEMS : "included in"
    ORDERS ||--o{ ORDER_ITEMS : "contains"

    USERS {
        int id PK
        varchar email UK
        varchar full_name
        timestamp created_at
        timestamp updated_at
    }

    PRODUCTS {
        int id PK
        varchar name
        varchar category
        varchar brand
        decimal price
        int stock_quantity
        timestamp created_at
        timestamp updated_at
    }

    ORDERS {
        int id PK
        int user_id FK
        decimal total_amount
        varchar status
        timestamp created_at
        timestamp updated_at
    }

    ORDER_ITEMS {
        int id PK
        int order_id FK
        int product_id FK
        int quantity
        decimal unit_price
        timestamp created_at
    }
