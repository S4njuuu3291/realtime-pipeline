package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pglogrepl"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgproto3"
	"github.com/joho/godotenv"
)

var lastProcessedLSN pglogrepl.LSN

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
				log.Printf("--- TABLE METADATA ---")
				log.Printf("ID Tabel: %d, Nama Tabel: %s", m.RelationID, m.RelationName)

				for _, col := range m.Columns {
					log.Printf("Kolom: %s, Tipe: %d", col.Name, col.DataType)
				}

			case *pglogrepl.InsertMessage:
				log.Printf("--- DATA INSERTED ---")

				for i, col := range m.Tuple.Columns {
					// col.Data adalah []byte, kita ubah ke string agar terbaca
					log.Printf("Kolom ke-%d: %s", i, string(col.Data))
				}

			case *pglogrepl.UpdateMessage:
				log.Printf("--- DATA UPDATED ---")
				log.Printf("Data Baru:")
				for _, col := range m.NewTuple.Columns {
					log.Printf("- %s", string(col.Data))
				}

				// Data lama (jika ada)
				if m.OldTuple != nil {
					log.Printf("Data Lama:")
					for _, col := range m.OldTuple.Columns {
						log.Printf("- %s", string(col.Data))
					}
				}

			case *pglogrepl.DeleteMessage:
				log.Printf("--- DATA DELETED ---")
				log.Printf("Data yang dihapus:")
				for _, col := range m.OldTuple.Columns {
					log.Printf("- %s", string(col.Data))
				}

				log.Printf("XLogData received: WAL %s, Payload: %x", xld.WALStart, xld.WALData)
			}
		}

	}
}
