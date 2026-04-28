from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy import Column, Integer, String, Numeric, ForeignKey, create_engine
from sqlalchemy.orm import Session, sessionmaker, declarative_base
from sqlalchemy.sql.expression import func
from faker import Faker
import random
import os

app = FastAPI()
fake = Faker()

# --- Database Configuration ---
def get_db_url():
    # Coba ambil URL lengkap dulu
    url = os.getenv("DATABASE_URL")
    
    # Jika URL ada tapi password-nya kosong (common issue di docker exec), 
    if not url or ":@postgres-source" in url:
        user = os.getenv("POSTGRES_USER", "admin")
        password = os.getenv("POSTGRES_PASSWORD", "password")
        host = os.getenv("POSTGRES_HOST", "postgres-source")
        port = os.getenv("POSTGRES_PORT", "5432")
        db = os.getenv("POSTGRES_DB", "ecom_db")
        return f"postgresql://{user}:{password}@{host}:{port}/{db}"
    
    return url

DATABASE_URL = get_db_url()

# Retry logic agar tidak crash saat nunggu Postgres
# Kita tambahkan pool_size dan max_overflow agar tahan banting saat trafik tinggi
engine = create_engine(
    DATABASE_URL, 
    pool_size=60, 
    max_overflow=30,
    pool_timeout=30,
    pool_recycle=1800
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# --- Models ---
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    full_name = Column(String)

class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    category = Column(String)
    brand = Column(String)
    price = Column(Numeric(10, 2), nullable=False)
    stock_quantity = Column(Integer, default=0)

class Order(Base):
    __tablename__ = "orders"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    total_amount = Column(Numeric(10, 2))
    status = Column(String)

class OrderItem(Base):
    __tablename__ = "order_items"
    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"))
    product_id = Column(Integer, ForeignKey("products.id"))
    quantity = Column(Integer, nullable=False)
    unit_price = Column(Numeric(10, 2), nullable=False)

# Kita menghapus Base.metadata.create_all(bind=engine)
# Karena tabel sekarang dikelola murni oleh Makefile (init_source.sql)
# Sehingga konfigurasi "Replica Identity" untuk CDC tidak tertimpa/hilang.

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/")
def read_root():
    return {"status": "Order Service is running with Enterprise Schema"}

@app.post("/simulate/order")
def create_random_order(db: Session = Depends(get_db)):
    # 1. Pilih User ACAK, jika tidak ada, buat baru.
    user = db.query(User).order_by(func.random()).first()
    if not user:
        user = User(email=fake.email(), full_name=fake.name())
        db.add(user)
        db.commit()
        db.refresh(user)

    # 2. Ambil 1 hingga 3 Produk ACAK dari database
    num_items = random.randint(1, 3)
    products = db.query(Product).order_by(func.random()).limit(num_items).all()
    
    if not products:
        raise HTTPException(status_code=400, detail="No products available in database")

    # 3. Hitung keranjang belanja
    total_order_amount = 0
    items_to_create = []

    for product in products:
        buy_qty = random.randint(1, 2)
        
        # Simulasikan pengurangan stok (Memicu UPDATE event untuk CDC)
        product.stock_quantity = product.stock_quantity - buy_qty
        
        line_total = buy_qty * product.price
        total_order_amount += line_total

        # Siapkan Order Item
        item = OrderItem(
            product_id=product.id,
            quantity=buy_qty,
            unit_price=product.price
        )
        items_to_create.append(item)

    # 4. Buat Record Order
    new_order = Order(
        user_id=user.id,
        total_amount=total_order_amount,
        status=random.choice(["PENDING", "PROCESSING", "SHIPPED"])
    )
    db.add(new_order)
    db.flush() # Flush agar kita mendapatkan new_order.id sebelum dicommit

    # 5. Pasangkan Order Items dengan Order ID, dan simpan
    for item in items_to_create:
        item.order_id = new_order.id
        db.add(item)

    # 6. Commit seluruh transaksi (Order, OrderItems, Update Stock Product)
    db.commit()
    
    return {
        "message": "Order created successfully", 
        "order_id": new_order.id,
        "total_amount": float(total_order_amount),
        "items_count": len(items_to_create)
    }
