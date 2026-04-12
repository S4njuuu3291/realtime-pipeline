import argparse
import random
import time
import json
import urllib.request
from faker import Faker

# Import komponen database langsung dari file main aplikasi kita
from main import User, Product, SessionLocal

fake = Faker()

def seed_db():
    print("📦 Mempersiapkan Database Seeding...")
    db = SessionLocal()
    
    # Validasi agar tidak numpuk kalau dijalankan 2 kali
    if db.query(User).count() > 100:
        print("⚠️ Database sudah memiliki cukup data pengguna. Proses Seeding dilewati.")
        return

    print("🚀 Membuat 1000 Users acak...")
    users = []
    for _ in range(1000):
        users.append(User(email=fake.unique.email(), full_name=fake.name()))
    
    print("💻 Membuat 300 Products acak...")
    categories = ['Electronics', 'Accessories', 'Furniture', 'Clothing', 'Books', 'Toys', 'Sports', 'Automotive']
    brands = ['Apple', 'Samsung', 'Sony', 'IKEA', 'Nike', 'Adidas', 'Logitech', 'Razer', 'Asus', 'Yamaha']
    
    products = []
    for _ in range(300):
        products.append(Product(
            name=fake.catch_phrase(), # Menggunakan catch_phrase faker untuk nama produk estetis
            category=random.choice(categories),
            brand=random.choice(brands),
            price=round(random.uniform(5.0, 1500.0), 2),
            stock_quantity=random.randint(50, 1000)
        ))
    
    
    db.add_all(users)
    db.add_all(products)
    db.commit()
    db.close()
    print("✅ SELESAI: 1000 Users & 300 Products berhasil disuntikkan ke dalam sistem!")

def generate_traffic():
    print("🔥 Memulai Mesin Simluator Transaksi (Traffic Generator)...", flush=True)
    print("Aplikasi akan memanggil API /simulate/order secara konstan (Tekan Ctrl+C untuk berhenti)\n", flush=True)
    
    req = urllib.request.Request("http://order-service:8000/simulate/order", method="POST")
    while True:
        try:
            with urllib.request.urlopen(req) as response:
                result = json.loads(response.read().decode())
                print(f"🛒 Transaksi Berhasil -> Order ID: {result.get('order_id')} | Item: {result.get('items_count')} | Total: ${result.get('total_amount')}", flush=True)
        except Exception as e:
            print(f"❌ Gagal memanggil API: {e}", flush=True)
        
        # Jeda acak antara 0.5 hingga 2 detik agar trafiknya terlihat riil, bukan ddos
        time.sleep(random.uniform(0.5, 2.0))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Script Manajemen Data Dummy untuk CDC Pipeline")
    parser.add_argument('--seed', action='store_true', help='Memasukkan ribuan data dummy')
    parser.add_argument('--traffic', action='store_true', help='Memutar loop transaksi tanpa henti')
    args = parser.parse_args()

    if args.seed:
        seed_db()
    elif args.traffic:
        generate_traffic()
    else:
        parser.print_help()
