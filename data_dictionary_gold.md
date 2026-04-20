# Data Dictionary: Gold Layer (One Big Table)

Tabel **`analytics_sales_obt`** adalah tabel denormalisasi (One Big Table) di lapisan Gold yang berada di dalam ClickHouse. Tabel ini didesain secara khusus untuk analitik berkecepatan tinggi dan siap dihubungkan langsung ke platform *Business Intelligence* (seperti Apache Superset).

Karena data sudah berwujud **Satu Tabel Lebar (OBT)**, semua metrik fakta (jumlah, harga) dan atribut dimensi (nama user, kategori produk) sudah tergabung menjadi satu, membebaskan Superset dari kewajiban melakukan proses operasi *JOIN* yang berat.

## Struktur Skema

| Nama Kolom | Tipe Data ClickHouse | Deskripsi / Definisi | Sumber Data Asal |
| :--- | :--- | :--- | :--- |
| `order_item_id` | `Int32` | ID unik dari item pesanan. Bersama dengan timestamp membentuk susunan pengurutan data (*Sorting Key*). | Event Stream (`order_items.id`) |
| `order_id` | `Int32` | ID pesanan (transaksi utama). Satu `order_id` bisa memiliki beberapa baris jika pembeli membeli lebih dari 1 jenis produk. | Event Stream (`order_items.order_id`) |
| `user_id` | `Int32` | ID unik pengguna pembeli. | *Lookup* di `dict_orders` |
| `user_full_name` | `String` | Nama lengkap pengguna. | *Lookup* di `dict_users` |
| `product_id` | `Int32` | ID unik produk yang dibeli. | Event Stream (`order_items.product_id`) |
| `product_name` | `String` | Nama produk. | *Lookup* di `dict_products` |
| `product_category` | `String` | Kategori produk (misal: Electronics, Accessories). | *Lookup* di `dict_products` |
| `product_brand` | `String` | Merk dari produk (misal: Apple, Logitech). | *Lookup* di `dict_products` |
| `quantity` | `Int32` | Jumlah barang yang dibeli pada baris transaksi tersebut. | Event Stream (`order_items.quantity`) |
| `unit_price` | `String` | Harga satuan barang saat transaksi terjadi. (Catatan: dalam format string dari CDC Kafka, perlu dikonversi ke *Float* saat kalkulasi). | Event Stream (`order_items.unit_price`) |
| `order_status` | `String` | Status keseluruhan pesanan (misal: PENDING, SHIPPED, DELIVERED). | *Lookup* di `dict_orders` |
| `timestamp` | `Int64` | Waktu terjadinya event transaksi dari CDC (format *epoch milliseconds*). Berfungsi sebagai penentu kapan data direkam. | Event Stream (`timestamp`) |

<br/>

> [!TIP]
> **Metrik Dasar yang Bisa Langsung Divisualisasikan di Superset:**
> - **Total Revenue/Pendapatan**: `SUM(quantity * toFloat64(unit_price))`
> - **Jumlah Total Transaksi Unik**: `COUNT(DISTINCT order_id)`
> - **Jumlah Total Barang Terjual**: `SUM(quantity)`
> - **Performa per Kategori/Merek**: Lakukan visualisasi *Pie Chart/Bar Chart* menggunakan kolom `product_category` atau `product_brand`.
