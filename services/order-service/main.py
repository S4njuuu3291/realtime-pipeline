from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy import create_all, Column, Integer, String, Decimal, ForeignKey, create_engine
from sqlalchemy.orm import Session, sessionmaker, declarative_base
from faker import Faker
import random

app = FastAPI()
fake = Faker()

# Database Configuration
DATABASE_URL = "postgresql://admin:password@localhost:5432/ecom_db"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# --- Models (Matching our SQL Schema) ---
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    email = Column(String, unique=True)
    full_name = Column(String)

class Order(Base):
    __tablename__ = "orders"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    total_amount = Column(Decimal)
    status = Column(String)

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/simulate/order")
def create_random_order(db: Session = Depends(get_db)):
    """Simulates a user placing a random order"""
    # 1. Ensure we have users
    user = db.query(User).first()
    if not user:
        user = User(email=fake.email(), full_name=fake.name())
        db.add(user)
        db.commit()
    
    # 2. Create Order
    new_order = Order(
        user_id=user.id,
        total_amount=round(random.uniform(10.5, 500.0), 2),
        status="PENDING"
    )
    db.add(new_order)
    db.commit()
    return {"message": "Order Created", "order_id": new_order.id, "status": new_order.status}

@app.patch("/simulate/ship/{order_id}")
def ship_order(order_id: int, db: Session = Depends(get_db)):
    """Simulates an order being shipped (Testing CDC Updates)"""
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    order.status = "SHIPPED"
    db.commit()
    return {"message": f"Order {order_id} is now SHIPPED"}