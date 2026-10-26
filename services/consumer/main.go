package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	clickhouse "github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"github.com/joho/godotenv"
	"github.com/twmb/franz-go/pkg/kgo"
)

type OrderDetail struct {
	ID          int32  `json:"id"`
	UserID      int32  `json:"user_id"`
	TotalAmount string `json:"total_amount"`
	Status      string `json:"status"`
	CreatedAt   int64  `json:"created_at"`
	UpdatedAt   int64  `json:"updated_at"`
}

type OrderItemDetail struct {
	ID        int32  `json:"id"`
	OrderID   int32  `json:"order_id"`
	ProductID int32  `json:"product_id"`
	Quantity  int32  `json:"quantity"`
	UnitPrice string `json:"unit_price"`
}

type UserDetail struct {
	ID        int32  `json:"id"`
	Email     string `json:"email"`
	FullName  string `json:"full_name"`
	CreatedAt int64  `json:"created_at"`
	UpdatedAt int64  `json:"updated_at"`
}

type ProductDetail struct {
	ID            int32  `json:"id"`
	Name          string `json:"name"`
	Category      string `json:"category"`
	Brand         string `json:"brand"`
	Price         string `json:"price"`
	StockQuantity int32  `json:"stock_quantity"`
	CreatedAt     int64  `json:"created_at"`
	UpdatedAt     int64  `json:"updated_at"`
}

type CDCEvent struct {
	Before    json.RawMessage `json:"before"`
	After     json.RawMessage `json:"after"`
	Op        string          `json:"op"`
	Timestamp int64           `json:"ts_ms"`
}

const ordersInsert = "INSERT INTO orders_history (id, user_id, total_amount, status, created_at, updated_at, operation, timestamp)"
const orderItemsInsert = "INSERT INTO order_items_history (id, order_id, product_id, quantity, unit_price, operation, timestamp)"

var tableInserts = map[string]string{
	"orders":      ordersInsert,
	"order_items": orderItemsInsert,
	"users":       "INSERT INTO users_history (id, email, full_name, created_at, updated_at, operation, timestamp)",
	"products":    "INSERT INTO products_history (id, name, category, brand, price, stock_quantity, created_at, updated_at, operation, timestamp)",
}

var tables = []string{"orders", "order_items", "users", "products"}

// Tombstones have no row. Deletes use the before image; other data events use after.
func decodeRow(value []byte, table string) ([]any, error) {
	if value == nil {
		return nil, nil
	}
	var event CDCEvent
	if err := json.Unmarshal(value, &event); err != nil {
		return nil, err
	}
	var image json.RawMessage
	switch event.Op {
	case "c", "r", "u":
		image = event.After
	case "d":
		image = event.Before
	default:
		return nil, fmt.Errorf("unsupported CDC operation %q", event.Op)
	}
	if len(image) == 0 || string(image) == "null" {
		return nil, fmt.Errorf("missing row image for operation %q", event.Op)
	}
	switch table {
	case "users":
		var user UserDetail
		if err := json.Unmarshal(image, &user); err != nil {
			return nil, err
		}
		return []any{user.ID, user.Email, user.FullName, user.CreatedAt, user.UpdatedAt, event.Op, event.Timestamp}, nil
	case "products":
		var product ProductDetail
		if err := json.Unmarshal(image, &product); err != nil {
			return nil, err
		}
		return []any{product.ID, product.Name, product.Category, product.Brand, product.Price, product.StockQuantity, product.CreatedAt, product.UpdatedAt, event.Op, event.Timestamp}, nil
	case "order_items":
		var item OrderItemDetail
		if err := json.Unmarshal(image, &item); err != nil {
			return nil, err
		}
		return []any{item.ID, item.OrderID, item.ProductID, item.Quantity, item.UnitPrice, event.Op, event.Timestamp}, nil
	case "orders":
	default:
		return nil, fmt.Errorf("unsupported table %q", table)
	}
	var order OrderDetail
	if err := json.Unmarshal(image, &order); err != nil {
		return nil, err
	}
	return []any{order.ID, order.UserID, order.TotalAmount, order.Status, order.CreatedAt, order.UpdatedAt, event.Op, event.Timestamp}, nil
}

func consumerTopics(ordersTopic string, overrides map[string]string) ([]string, map[string]string, error) {
	topics := make([]string, 0, len(tables))
	routes := make(map[string]string, len(tables))
	for _, table := range tables {
		topic := ordersTopic
		if table != "orders" {
			topic = overrides[table]
			if topic == "" {
				if !strings.HasSuffix(ordersTopic, ".orders") {
					return nil, nil, fmt.Errorf("set topic override for %s when TOPIC does not end in .orders", table)
				}
				topic = strings.TrimSuffix(ordersTopic, ".orders") + "." + table
			}
		}
		if _, exists := routes[topic]; exists {
			return nil, nil, fmt.Errorf("duplicate topic %q", topic)
		}
		topics = append(topics, topic)
		routes[topic] = table
	}
	return topics, routes, nil
}

func writeRows(ctx context.Context, conn driver.Conn, query string, rows [][]any) error {
	if len(rows) == 0 {
		return nil
	}
	batch, err := conn.PrepareBatch(ctx, query)
	if err != nil {
		return err
	}
	defer batch.Abort()
	for _, row := range rows {
		if err := batch.Append(row...); err != nil {
			return err
		}
	}
	return batch.Send()
}

func run() error {
	_ = godotenv.Load("../../.env")
	_ = godotenv.Load(".env")
	ordersTopic := os.Getenv("TOPIC")
	if ordersTopic == "" {
		ordersTopic = "ecommerce.public.orders"
	}
	topics, routes, err := consumerTopics(ordersTopic, map[string]string{
		"order_items": os.Getenv("ORDER_ITEMS_TOPIC"),
		"users":       os.Getenv("USERS_TOPIC"),
		"products":    os.Getenv("PRODUCTS_TOPIC"),
	})
	if err != nil {
		return err
	}
	client, err := kgo.NewClient(
		kgo.SeedBrokers(os.Getenv("KAFKA_BROKERS")),
		kgo.ConsumerGroup(os.Getenv("GROUP_ID")),
		kgo.ConsumeTopics(topics...),
		kgo.ClientID(os.Getenv("CLIENT_ID")),
		kgo.DisableAutoCommit(),
		kgo.BlockRebalanceOnPoll(),
		kgo.SessionTimeout(6*time.Second),
		kgo.RebalanceTimeout(3*time.Second),
	)
	if err != nil {
		return err
	}
	defer client.CloseAllowingRebalance()
	host := os.Getenv("CLICKHOUSE_HOST")
	if host == "" {
		host = "localhost:9000"
	}
	conn, err := clickhouse.Open(&clickhouse.Options{
		Addr: []string{host},
		Auth: clickhouse.Auth{
			Database: os.Getenv("CLICKHOUSE_DB"),
			Username: os.Getenv("CLICKHOUSE_USER"),
			Password: os.Getenv("CLICKHOUSE_ADMIN_PASSWORD"),
		},
	})
	if err != nil {
		return err
	}
	defer conn.Close()
	ctx := context.Background()
	if err := conn.Ping(ctx); err != nil {
		return err
	}
	log.Printf("Consuming %v", topics)
	for {
		fetches := client.PollFetches(ctx)
		if errs := fetches.Errors(); len(errs) > 0 {
			return fmt.Errorf("fetch records: %v", errs)
		}
		rows := make(map[string][][]any, len(tables))
		iter := fetches.RecordIter()
		for !iter.Done() {
			record := iter.Next()
			table, ok := routes[record.Topic]
			if !ok {
				return fmt.Errorf("unexpected topic %q", record.Topic)
			}
			row, err := decodeRow(record.Value, table)
			if err != nil {
				return fmt.Errorf("decode %s partition=%d offset=%d: %w", record.Topic, record.Partition, record.Offset, err)
			}
			if row == nil {
				continue
			}
			rows[table] = append(rows[table], row)
		}
		for _, table := range tables {
			if err := writeRows(ctx, conn, tableInserts[table], rows[table]); err != nil {
				return fmt.Errorf("write %s: %w", table, err)
			}
		}
		// Commit only after all tables succeed, including tombstone-only fetches.
		if fetches.NumRecords() > 0 {
			if err := client.CommitUncommittedOffsets(ctx); err != nil {
				return fmt.Errorf("commit offsets: %w", err)
			}
			log.Printf("Inserted orders=%d order_items=%d users=%d products=%d", len(rows["orders"]), len(rows["order_items"]), len(rows["users"]), len(rows["products"]))
		}
		client.AllowRebalance()
	}
}

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
