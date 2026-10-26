package main

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
)

func TestDecodeRow(t *testing.T) {
	tests := []struct {
		name, value string
		table       string
		want        []any
		invalid     bool
	}{
		{name: "order create", value: `{"op":"c","ts_ms":123,"after":{"id":1,"user_id":2,"total_amount":"12.50","status":"pending","created_at":1792980000000000,"updated_at":1792980000000000}}`, want: []any{int32(1), int32(2), "12.50", "pending", int64(1792980000000000), int64(1792980000000000), "c", int64(123)}},
		{name: "item snapshot", table: "order_items", value: `{"op":"r","ts_ms":123,"after":{"id":3,"order_id":1,"product_id":4,"quantity":2,"unit_price":"6.25"}}`, want: []any{int32(3), int32(1), int32(4), int32(2), "6.25", "r", int64(123)}},
		{name: "item update", table: "order_items", value: `{"op":"u","ts_ms":124,"before":{"quantity":1},"after":{"id":3,"order_id":1,"product_id":4,"quantity":2,"unit_price":"6.25"}}`, want: []any{int32(3), int32(1), int32(4), int32(2), "6.25", "u", int64(124)}},
		{name: "item delete", table: "order_items", value: `{"op":"d","ts_ms":125,"before":{"id":3,"order_id":1,"product_id":4,"quantity":2,"unit_price":"6.25"},"after":null}`, want: []any{int32(3), int32(1), int32(4), int32(2), "6.25", "d", int64(125)}},
		{name: "missing after", value: `{"op":"c","after":null}`, invalid: true},
		{name: "missing before", table: "order_items", value: `{"op":"d"}`, invalid: true},
		{name: "unknown operation", value: `{"op":"x"}`, invalid: true},
		{name: "malformed", value: `{`, invalid: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			table := tt.table
			if table == "" {
				table = "orders"
			}
			got, err := decodeRow([]byte(tt.value), table)
			if (err != nil) != tt.invalid {
				t.Fatalf("error=%v", err)
			}
			if !tt.invalid && !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %#v want %#v", got, tt.want)
			}
		})
	}
	if row, err := decodeRow(nil, "order_items"); err != nil || row != nil {
		t.Fatalf("tombstone: %v %v", row, err)
	}
}

type testBatch struct {
	driver.Batch
	appendErr, sendErr error
	sent, aborted      bool
}

func (b *testBatch) Append(...any) error { return b.appendErr }
func (b *testBatch) Send() error         { b.sent = true; return b.sendErr }
func (b *testBatch) Abort() error        { b.aborted = true; return nil }

type testConn struct {
	driver.Conn
	batch *testBatch
}

func (c *testConn) PrepareBatch(context.Context, string, ...driver.PrepareBatchOption) (driver.Batch, error) {
	return c.batch, nil
}
func TestWriteRowsFailure(t *testing.T) {
	failure := errors.New("sink failed")
	for _, appendFailure := range []bool{true, false} {
		b := &testBatch{}
		if appendFailure {
			b.appendErr = failure
		} else {
			b.sendErr = failure
		}
		err := writeRows(context.Background(), &testConn{batch: b}, orderItemsInsert, [][]any{{int32(1)}})
		if !errors.Is(err, failure) || !b.aborted {
			t.Fatalf("failure lost or batch not released: %v", err)
		}
		if appendFailure && b.sent {
			t.Fatal("sent incomplete batch")
		}
	}
}

func TestUserAndProductEvents(t *testing.T) {
	tests := []struct {
		table, image string
		fields       []any
	}{
		{"users", `{"id":7,"email":"user@example.org","full_name":"Test User","created_at":1792980000000000,"updated_at":1792980000000001}`, []any{int32(7), "user@example.org", "Test User", int64(1792980000000000), int64(1792980000000001)}},
		{"products", `{"id":9,"name":"Laptop","category":"Electronics","brand":"Test","price":"1234.50","stock_quantity":12,"created_at":1792980000000000,"updated_at":1792980000000001}`, []any{int32(9), "Laptop", "Electronics", "Test", "1234.50", int32(12), int64(1792980000000000), int64(1792980000000001)}},
	}
	for _, tt := range tests {
		for _, op := range []string{"c", "r", "u", "d"} {
			t.Run(tt.table+"/"+op, func(t *testing.T) {
				imageKey := "after"
				if op == "d" {
					imageKey = "before"
				}
				value := fmt.Sprintf(`{"op":%q,"ts_ms":456,%q:%s}`, op, imageKey, tt.image)
				got, err := decodeRow([]byte(value), tt.table)
				want := append(append([]any{}, tt.fields...), op, int64(456))
				if err != nil || !reflect.DeepEqual(got, want) {
					t.Fatalf("got=%#v err=%v want=%#v", got, err, want)
				}
			})
		}
	}
}

func TestConsumerTopics(t *testing.T) {
	topics, routes, err := consumerTopics("custom.public.orders", map[string]string{"users": "custom-users"})
	want := []string{"custom.public.orders", "custom.public.order_items", "custom-users", "custom.public.products"}
	if err != nil || !reflect.DeepEqual(topics, want) {
		t.Fatalf("topics=%v err=%v", topics, err)
	}
	for i, table := range tables {
		if routes[topics[i]] != table {
			t.Fatalf("wrong route for %s", table)
		}
	}
	if _, _, err := consumerTopics("custom.public.orders", map[string]string{"users": "custom.public.orders"}); err == nil {
		t.Fatal("duplicate topic accepted")
	}
	if _, _, err := consumerTopics("orders", nil); err == nil {
		t.Fatal("missing overrides accepted")
	}
}
