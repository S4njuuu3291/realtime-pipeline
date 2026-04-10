from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy import Column, Integer, String, Numeric, ForeignKey, create_engine
from sqlalchemy.orm import Session, sessionmaker, declarative_base
from faker import Faker
import random
import os
import time

app = FastAPI()
fake = Faker()

# --- Database Configuration ---
DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql://admin:password@postgres-source:5432/ecom_db"
)

# Retry logic agar tidak crash saat nunggu Postgres
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# --- Models ---
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    full_name = Column(String)

class Order(Base):
    __tablename__ = "orders"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    total_amount = Column(Numeric(10, 2)) # Pakai Numeric, bukan Decimal
    status = Column(String)

# --- Create Tables ---
# Jalankan ini agar tabel otomatis terbuat di Postgres
Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/")
def read_root():
    return {"status": "Order Service is running"}

@app.post("/simulate/order")
def create_random_order(db: Session = Depends(get_db)):
    user = db.query(User).first()
    if not user:
        user = User(email=fake.email(), full_name=fake.name())
        db.add(user)
        db.commit()
        db.refresh(user)

    new_order = Order(
        user_id=user.id,
        total_amount=round(random.uniform(10.0, 500.0), 2),
        status=random.choice(["PENDING", "COMPLETED", "SHIPPED"])
    )
    db.add(new_order)
    db.commit()
    db.refresh(new_order)
    return {"message": "Order created", "order_id": new_order.id}
