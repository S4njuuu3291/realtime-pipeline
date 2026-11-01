import argparse
import logging
import random
import time
import requests
import concurrent.futures
from datetime import datetime
from pathlib import Path
from faker import Faker
from sqlalchemy.orm import Session
import yaml

# Import komponen database dari main.py
from main import User, Product, SessionLocal

fake = Faker()
logger = logging.getLogger(__name__)

# ==========================================
# 1. KATALOG PRODUK REALISTIS (ENTERPRISE)
# ==========================================
PRODUCT_CATALOG = {
    'Electronics': {
        'brands': ['Apple', 'Samsung', 'Sony', 'Asus', 'Dell'],
        'price_range': (200.0, 3000.0),
        'templates': ['{} Smart TV {} Inch', '{} Laptop Pro Gen {}', '{} Smartphone S{}', '{} Noise Cancelling Headphone V{}']
    },
    'Clothing': {
        'brands': ['Nike', 'Adidas', 'Uniqlo', 'H&M', 'Zara'],
        'price_range': (10.0, 200.0),
        'templates': ['{} Running Shoes Seri {}', '{} Casual T-Shirt Model {}', '{} Sport Jacket V{}', '{} Denim Fit-{}']
    },
    'Furniture': {
        'brands': ['IKEA', 'Informa', 'Ashley', 'Cellini'],
        'price_range': (50.0, 1500.0),
        'templates': ['{} Minimalist Sofa V{}', '{} Wooden Table Seri {}', '{} Ergonomic Chair {}', '{} Wardrobe Model {}']
    },
    'Beauty': {
        'brands': ['Loreal', 'Maybelline', 'Wardah', 'SK-II'],
        'price_range': (5.0, 150.0),
        'templates': ['{} Matte Lipstick V{}', '{} Anti-Aging Serum {}ml', '{} Foundation Shade {}', '{} Face Wash {}ml']
    }
}

def seed_db():
    """Fase 1: Membangun Data Warehouse Landing Zone dengan data yang masuk akal"""
    print("📦 [SEEDING] Mempersiapkan Database...")
    db: Session = SessionLocal()
    
    # Cek Idempotency (Jangan jalankan dua kali)
    if db.query(User).count() > 100:
        print("⚠️ [SEEDING] Data sudah ada. Melewati proses seeding untuk mencegah duplikasi.")
        db.close()
        return

    # 1. Generate Users
    print("👥 [SEEDING] Menyuntikkan 1000 Users acak...")
    users = [User(email=fake.unique.email(), full_name=fake.name()) for _ in range(1000)]
    db.add_all(users)

    # 2. Generate Products
    print("💻 [SEEDING] Menyuntikkan 500 Products realistis...")
    products = []
    for _ in range(500):
        category = random.choice(list(PRODUCT_CATALOG.keys()))
        meta = PRODUCT_CATALOG[category]
        brand = random.choice(meta['brands'])
        
        # Harga menggunakan Triangular Distribution (Cenderung ke arah harga murah/menengah)
        min_p, max_p = meta['price_range']
        mode_p = min_p + (max_p - min_p) * 0.2 # Puncak probabilitas ada di 20% harga bawah
        price = round(random.triangular(min_p, max_p, mode_p), 2)
        
        # Penamaan Produk Berbasis Template
        template = random.choice(meta['templates'])
        product_name = template.format(brand, random.randint(1, 99))
        
        products.append(Product(
            name=product_name,
            category=category,
            brand=brand,
            price=price,
            stock_quantity=random.randint(20, 500)
        ))
    
    db.add_all(products)
    db.commit()
    db.close()
    print("✅ [SEEDING] SELESAI: 1000 Users & 500 Products siap untuk simulasi transaksi!")


# ==========================================
# 2. SIMULATOR TRAFIK E-COMMERCE (MULTITHREADING)
# ==========================================
API_URL = "http://localhost:8000/simulate/order" # Gunakan localhost jika dari dalam container fastapi ke dirinya sendiri, atau "order-service" jika via docker network

def load_traffic_config():
    config_path = Path(__file__).resolve().with_name("traffic-config.yaml")
    with config_path.open(encoding="utf-8") as config_file:
        return yaml.safe_load(config_file)

def send_transaction(worker_id: int):
    """Fungsi worker tunggal untuk menembak 1 API Call"""
    try:
        # Timeout penting agar thread tidak nyangkut selamanya jika server melambat
        response = requests.post(API_URL, timeout=5)
        if response.status_code == 200:
            res = response.json()
            # Hanya print sebagian kecil saja agar terminal tidak lag
            if random.random() < 0.1: 
                # Perbaikan: Menggunakan 'order_id' sesuai output di main.py
                order_id = res.get('order_id', 'N/A')
                logger.info("[Worker-%s] Transaksi sukses -> Order ID: %s", worker_id, order_id)
        else:
            if random.random() < 0.05:
                logger.warning("[Worker-%s] Server busy: %s", worker_id, response.status_code)
    except Exception as e:
        if random.random() < 0.01:
            logger.error("[Worker-%s] Gagal: %s", worker_id, e)

def generate_traffic():
    """Fase 2: Menembakkan transaksi menggunakan Thread Pool dengan pola Gelombang"""
    logger.info("[TRAFFIC] Memulai simulator transaksi")
    logger.info("Pola: base load 2-5 request per siklus; flash sale 30-50 request setiap 30 siklus")
    logger.info("Tekan Ctrl+C untuk menghentikan")
    
    # Gunakan thread pool untuk menembakkan request secara konkuren
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        cycle = 0
        try:
            while True:
                cycle += 1
                
                # Logika Pola Trafik
                is_flash_sale = (cycle % 30 == 0) # Tiap siklus ke-30 terjadi Flash Sale
                
                if is_flash_sale:
                    target_tps = random.randint(30, 50)
                    logger.info("[FLASH SALE] Menembakkan %s request", target_tps)
                else:
                    target_tps = random.randint(2, 5) # Base load normal e-commerce
                
                # Tembak API secara paralel
                futures = [executor.submit(send_transaction, i) for i in range(target_tps)]
                
                # Tunggu semua request di detik ini selesai
                concurrent.futures.wait(futures)
                
                # Jeda 1 detik untuk menyimulasikan hitungan TPS sesungguhnya
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("[TRAFFIC] Simulator dihentikan oleh user")

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Script Manajemen Data & Simulator Trafik (Enterprise Grade)")
    parser.add_argument('--seed', action='store_true', help='Suntik Data Katalog & User')
    parser.add_argument('--traffic', action='store_true', help='Jalankan Robot Simulator Trafik')
    args = parser.parse_args()

    # Perbaiki URL jika dijalankan dari dalam Docker (sebagai service traffic-generator)
    import os
    if os.getenv("DOCKER_ENV") or os.path.exists("/.dockerenv"):
        API_URL = "http://order-service:8000/simulate/order"

    if args.seed:
        seed_db()
    elif args.traffic:
        traffic_config = load_traffic_config()
        generate_traffic()
    else:
        parser.print_help()
