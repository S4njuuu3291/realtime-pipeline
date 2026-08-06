package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	clickhouse "github.com/ClickHouse/clickhouse-go/v2"
	"github.com/joho/godotenv"
	"github.com/twmb/franz-go/pkg/kgo"
)

type OrderDetail struct {
	ID          int    `json:"id"`
	UserID      int    `json:"user_id"`
	TotalAmount string `json:"total_amount"`
	Status      string `json:"status"`
	CreatedAt   int    `json:"created_at"`
	UpdatedAt   int    `json:"updated_at"`
}

type Order struct {
	Before *OrderDetail `json:"before"`
	After  *OrderDetail `json:"after"`
	Op     string       `json:"op"`
}

func main() {
	err := godotenv.Load("../../.env")

	if err != nil {
		log.Fatalf("Error loading .env file: %v", err)
	}

	topic := os.Getenv("TOPIC")
	broker := os.Getenv("KAFKA_BROKERS")

	broker = "localhost:19092"

	group_id := os.Getenv("GROUP_ID")
	client_id := os.Getenv("CLIENT_ID")

	fmt.Println("Go Consumer Started")

	client, err := kgo.NewClient(
		kgo.SeedBrokers(broker),
		kgo.ConsumerGroup(group_id),
		kgo.ConsumeTopics(topic),
		kgo.ClientID(client_id),
		kgo.DisableAutoCommit(),
		kgo.SessionTimeout(6*time.Second),
		kgo.RebalanceTimeout(3*time.Second),
	)

	if err != nil {
		log.Fatalf("Error creating Kafka client: %v", err)
	}
	defer client.Close()

	clickhouseHOST := "localhost:9000"
	clickhouseUSER := os.Getenv("CLICKHOUSE_USER")
	clickhousePASSWORD := os.Getenv("CLICKHOUSE_ADMIN_PASSWORD")
	clickhouseDB := os.Getenv("CLICKHOUSE_DB")

	fmt.Println("Connecting to Clickhouse...")
	// Initialize ClickHouse connection
	conn, err := clickhouse.Open(&clickhouse.Options{
		Addr: []string{
			clickhouseHOST},
		Auth: clickhouse.Auth{
			Database: clickhouseDB,
			Username: clickhouseUSER,
			Password: clickhousePASSWORD},
	})

	if err != nil {
		log.Fatalf("Error connecting to ClickHouse: %v", err)
	}
	defer conn.Close()
	if err := conn.Ping(context.Background()); err != nil {
		log.Fatal(err)
	}

	fmt.Println("Connected!")

	ctx := context.Background()

	for {
		fetches := client.PollFetches(ctx)
		errs := fetches.Errors()
		for _, err := range errs {
			log.Printf("Error fetching records: %v", err)
		}

		if fetches.NumRecords() == 0 {
			continue
		}

		batch, err := conn.PrepareBatch(ctx, "INSERT INTO orders_history (id, user_id, total_amount, status, created_at, updated_at)")

		if err != nil {
			log.Printf("Error preparing batch: %v", err)
			continue
		}

		iter := fetches.RecordIter()

		recordsInBatch := 0

		for !iter.Done() {
			record := iter.Next()

			// handle tombstone messages
			if record.Value == nil {
				log.Printf("Received tombstone message for key: %s", string(record.Key))

				if err := client.CommitRecords(ctx, record); err != nil {
					log.Printf("Error committing record: %v", err)
				}
				continue
			}

			var order Order
			err := json.Unmarshal(record.Value, &order)
			if err != nil {
				log.Printf("Error unmarshaling record value: %v", err)
				continue
			}

			var orderDetail OrderDetail
			// if order.Op == "c" {
			// 	orderDetail = order.After
			// } else if order.Op == "r" {
			// 	orderDetail = order.After
			// } else if order.Op == "u" {
			// 	orderDetail = order.After
			// } else if order.Op == "d" {
			// 	orderDetail = order.Before
			// } else {
			// 	log.Printf("Unknown operation type: %s", order.Op)
			// 	continue
			// }

			switch order.Op {
			case "c", "r", "u":
				orderDetail = *order.After
			case "d":
				orderDetail = *order.Before
			default:
				log.Printf("Unknown operation type: %s", order.Op)
				continue
			}

			// if order.After.ID == 3 {
			// 	log.Println("simulate error")
			// 	os.Exit(1)
			// }

			// fmt.Printf("Consumed record: topic=%s partition=%d offset=%d key=%s value=%+v\n",
			// 	record.Topic, record.Partition, record.Offset, string(record.Key), orderDetail)

			// err = conn.Exec(ctx, "INSERT INTO orders_history (id, user_id, total_amount, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
			// 	orderDetail.ID, orderDetail.UserID, orderDetail.TotalAmount, orderDetail.Status, orderDetail.CreatedAt, orderDetail.UpdatedAt)

			// if err != nil {
			// 	log.Printf("Error inserting record into ClickHouse: %v", err)
			// 	continue
			// } else {
			// 	log.Printf("Inserted record into ClickHouse: %+v", orderDetail.ID)
			// }

			err = batch.Append(
				orderDetail.ID,
				orderDetail.UserID,
				orderDetail.TotalAmount,
				orderDetail.Status,
				orderDetail.CreatedAt,
				orderDetail.UpdatedAt,
			)
			// log.Printf("Appended record to batch: %+v", orderDetail.ID)

			if err != nil {
				log.Printf("Error appending to batch: %v", err)
				continue
			}

			recordsInBatch++

		}

		if recordsInBatch > 0 {
			batch.Send()
			log.Printf("Inserted batch of %v records into ClickHouse", recordsInBatch)

			if err := client.CommitUncommittedOffsets(ctx); err != nil {
				log.Printf("Error committing record: %v", err)
			}

		}

	}

}
