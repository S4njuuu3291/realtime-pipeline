package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	pb "github.com/S4njuuu3291/realtime-pipeline.git/proto"
	"github.com/jackc/pglogrepl"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgproto3"
	"github.com/joho/godotenv"
	"google.golang.org/protobuf/proto"
)

var lastProcessedLSN pglogrepl.LSN
var relationsCache = make(map[uint32]*pglogrepl.RelationMessage)

func init() {
	// Arahkan dengan pasti ke lokasi .env di root foldernya
	err := godotenv.Load("../../.env")
	if err != nil {
		log.Println("Peringatan: File .env tidak ditemukan, menggunakan Environment bawaan sistem")
	}
}

func main() {
	POSTGRES_USER := os.Getenv("POSTGRES_USER")
	POSTGRES_PASSWORD := os.Getenv("POSTGRES_PASSWORD")
	POSTGRES_PORT := os.Getenv("POSTGRES_PORT")
	POSTGRES_HOST := os.Getenv("POSTGRES_HOST")
	POSTGRES_DB := os.Getenv("POSTGRES_DB")

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?replication=database", POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB)

	fmt.Println("Proses menyambung ke:", connStr)

	ctx := context.Background()
	conn, err := pgconn.Connect(ctx, connStr)
	if err != nil {
		log.Fatalf("Gagal menyambung ke database: %v\n", err)
	}
	defer conn.Close(ctx)

	log.Println("Berhasil tersambung ke database Postgres!")

	const SLOT_NAME = "cdc_slot"

	// 1. Cek apakah slot sudah ada, jika belum buat
	_, err = pglogrepl.CreateReplicationSlot(ctx, conn, SLOT_NAME, "pgoutput", pglogrepl.CreateReplicationSlotOptions{Temporary: false})

	if err != nil {
		if pgerr, ok := err.(*pgconn.PgError); ok && pgerr.Code == "42710" {
			log.Println("Slot sudah ada, melanjutkan...")
		} else {
			log.Fatalf("Gagal membuat slot: %v\n", err)
		}
	}

	log.Printf("Slot '%s siap. Menunggu perubahan data...", SLOT_NAME)

	err = pglogrepl.StartReplication(ctx, conn, SLOT_NAME, 0, pglogrepl.StartReplicationOptions{PluginArgs: []string{"proto_version '1'", "publication_names 'my_pub'"}})

	if err != nil {
		log.Fatalf("Gagal memulai replikasi: %v\n", err)
	}

	log.Println("Streaming dimulai...")

	for {
		msg, err := conn.ReceiveMessage(ctx)
		if err != nil {
			log.Fatalf("Gagal menerima pesan: %v\n", err)
		}
		rawMsg, ok := msg.(*pgproto3.CopyData)
		if !ok {
			if errResp, isErr := msg.(*pgproto3.ErrorResponse); isErr {
				log.Fatalf("Fatal ErrorResponse dari Postgres: %s (Code: %s, Detail: %s, Hint: %s)", errResp.Message, errResp.Code, errResp.Detail, errResp.Hint)
			}
			log.Printf("Received non-CopyData message: %T\n", msg)
			continue
		}

		switch rawMsg.Data[0] {
		case 'k':
			pkm, err := pglogrepl.ParsePrimaryKeepaliveMessage(rawMsg.Data[1:])
			if err != nil {
				log.Fatalf("Error parsing keepalive message: %v\n", err)
				continue
			}
			ackLSN := pkm.ServerWALEnd
			if lastProcessedLSN > ackLSN {
				ackLSN = lastProcessedLSN
			}
			err = pglogrepl.SendStandbyStatusUpdate(ctx, conn, pglogrepl.StandbyStatusUpdate{
				WALWritePosition: ackLSN,
			})
			if pkm.ReplyRequested {
				log.Printf("Membalas Keepalive dengan LSN: %s", ackLSN)
			}
			if err != nil {
				log.Fatalf("Error sending standby status update: %v\n", err)
			}
		case 'w':
			xld, err := pglogrepl.ParseXLogData(rawMsg.Data[1:])
			if err != nil {
				log.Fatalf("Error parsing XLogData: %v\n", err)
				continue
			}
			lastProcessedLSN = xld.WALStart + pglogrepl.LSN(len(xld.WALData))

			logicalMsg, err := pglogrepl.Parse(xld.WALData)
			if err != nil {
				log.Fatalf("Error parsing logical replication message: %v\n", err)
				continue
			}

			switch m := logicalMsg.(type) {

			case *pglogrepl.RelationMessage:
				// Simpan metadata tabel ke dalam cache
				relationsCache[m.RelationID] = m
				log.Printf("--- TABLE METADATA CACHED ---")
				log.Printf("ID Tabel: %d, Nama Tabel: %s", m.RelationID, m.RelationName)

			case *pglogrepl.InsertMessage:
				rel := relationsCache[m.RelationID]
				if rel == nil {
					log.Printf("Metadata tidak ditemukan untuk relasi ID %d", m.RelationID)
					continue
				}

				event := &pb.CDCEvent{
					TableName: rel.RelationName,
					Operation: "INSERT",
					Timestamp: time.Now().UnixMilli(),
					After:     mapTupleToEntity(rel, m.Tuple),
				}

				protoBytes, err := proto.Marshal(event)
				if err != nil {
					log.Printf("Gagal marshal INSERT event: %v", err)
				} else {
					log.Printf("Berhasil serialisasi INSERT event untuk %s (ukuran: %d bytes)", rel.RelationName, len(protoBytes))
				}

			case *pglogrepl.UpdateMessage:
				rel := relationsCache[m.RelationID]
				if rel == nil {
					log.Printf("Metadata tidak ditemukan untuk relasi ID %d", m.RelationID)
					continue
				}

				event := &pb.CDCEvent{
					TableName: rel.RelationName,
					Operation: "UPDATE",
					Timestamp: time.Now().UnixMilli(),
					After:     mapTupleToEntity(rel, m.NewTuple),
					Before:    mapTupleToEntity(rel, m.OldTuple),
				}

				protoBytes, err := proto.Marshal(event)
				if err != nil {
					log.Printf("Gagal marshal UPDATE event: %v", err)
				} else {
					log.Printf("Berhasil serialisasi UPDATE event untuk %s (ukuran: %d bytes)", rel.RelationName, len(protoBytes))
				}

			case *pglogrepl.DeleteMessage:
				rel := relationsCache[m.RelationID]
				if rel == nil {
					log.Printf("Metadata tidak ditemukan untuk relasi ID %d", m.RelationID)
					continue
				}

				event := &pb.CDCEvent{
					TableName: rel.RelationName,
					Operation: "DELETE",
					Timestamp: time.Now().UnixMilli(),
					Before:    mapTupleToEntity(rel, m.OldTuple),
				}

				protoBytes, err := proto.Marshal(event)
				if err != nil {
					log.Printf("Gagal marshal DELETE event: %v", err)
				} else {
					log.Printf("Berhasil serialisasi DELETE event untuk %s (ukuran: %d bytes)", rel.RelationName, len(protoBytes))
				}

			default:
				log.Printf("Logical message lain diterima: %T", m)
			}
		}

	}
}

// Helper function untuk memetakan TupleData dari Postgres ke struct Protobuf (pb.Entity)
func mapTupleToEntity(rel *pglogrepl.RelationMessage, tuple *pglogrepl.TupleData) *pb.Entity {
	if rel == nil || tuple == nil {
		return nil
	}

	switch rel.RelationName {
	case "users":
		user := &pb.User{}
		for i, col := range tuple.Columns {
			val := string(col.Data)
			switch rel.Columns[i].Name {
			case "id":
				id, _ := strconv.Atoi(val)
				user.Id = int32(id)
			case "email":
				user.Email = val
			case "full_name":
				user.FullName = val
			case "created_at":
				user.CreatedAt = val
			case "updated_at":
				user.UpdatedAt = val
			}
		}
		return &pb.Entity{EntityType: &pb.Entity_User{User: user}}

	case "products":
		product := &pb.Product{}
		for i, col := range tuple.Columns {
			val := string(col.Data)
			switch rel.Columns[i].Name {
			case "id":
				id, _ := strconv.Atoi(val)
				product.Id = int32(id)
			case "name":
				product.Name = val
			case "category":
				product.Category = val
			case "brand":
				product.Brand = val
			case "price":
				product.Price = val
			case "stock_quantity":
				sq, _ := strconv.Atoi(val)
				product.StockQuantity = int32(sq)
			case "created_at":
				product.CreatedAt = val
			case "updated_at":
				product.UpdatedAt = val
			}
		}
		return &pb.Entity{EntityType: &pb.Entity_Product{Product: product}}

	case "orders":
		order := &pb.Order{}
		for i, col := range tuple.Columns {
			val := string(col.Data)
			switch rel.Columns[i].Name {
			case "id":
				id, _ := strconv.Atoi(val)
				order.Id = int32(id)
			case "user_id":
				uid, _ := strconv.Atoi(val)
				order.UserId = int32(uid)
			case "total_amount":
				order.TotalAmount = val
			case "status":
				order.Status = val
			case "created_at":
				order.CreatedAt = val
			case "updated_at":
				order.UpdatedAt = val
			}
		}
		return &pb.Entity{EntityType: &pb.Entity_Order{Order: order}}

	case "order_items":
		item := &pb.OrderItem{}
		for i, col := range tuple.Columns {
			val := string(col.Data)
			switch rel.Columns[i].Name {
			case "id":
				id, _ := strconv.Atoi(val)
				item.Id = int32(id)
			case "order_id":
				oid, _ := strconv.Atoi(val)
				item.OrderId = int32(oid)
			case "product_id":
				pid, _ := strconv.Atoi(val)
				item.ProductId = int32(pid)
			case "quantity":
				q, _ := strconv.Atoi(val)
				item.Quantity = int32(q)
			case "unit_price":
				item.UnitPrice = val
			case "created_at":
				item.CreatedAt = val
			}
		}
		return &pb.Entity{EntityType: &pb.Entity_OrderItem{OrderItem: item}}
	}

	return nil
}
