#!/usr/bin/env python3
"""
FreshCart Australia: Database Setup
Creates tables with proper schema (PKs, FKs, constraints) and loads CSV data.
Run: python3 setup_database.py
"""
import duckdb
import os

DB_PATH = "grocery_analytics.duckdb"
SCHEMA_FILE = "schema.sql"
DATA_DIR = "data"

# Check required files exist
required = [SCHEMA_FILE] + [f"{t}.csv" for t in
    ["customers", "products", "stores", "orders", "order_items", "promotions"]]

for f in required:
    if not os.path.exists(os.path.join(DATA_DIR, f)):
        print(f"ERROR: {f} not found. Place all files in the same directory.")
        exit(1)

# Remove existing database if rebuilding
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

con = duckdb.connect(DB_PATH)

# Create tables from schema
print("Creating tables from schema.sql...")
with open(SCHEMA_FILE) as f:
    schema_sql = f.read()

for stmt in schema_sql.split(';'):
    stmt = stmt.strip()
    if stmt and not all(
        line.strip().startswith('--') or line.strip() == ''
        for line in stmt.split('\n')
    ):
        con.execute(stmt)

# Load data in dependency order
print("Loading data...")
load_order = ['customers', 'products', 'stores', 'promotions', 'orders', 'order_items']
for table in load_order:
    con.execute(
        f"INSERT INTO {table} SELECT * FROM read_csv_auto('{DATA_DIR}/{table}.csv')"
    )
    count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"  {table:15s} | {count:>6,} rows")

con.close()
print(f"\nDatabase ready: {DB_PATH}")
