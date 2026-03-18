#!/usr/bin/env python3
"""
FreshCart Australia - Database Setup
Generates synthetic data and loads it into DuckDB.
Run: python3 setup_database.py
"""
import duckdb

import os

DB_PATH = "grocery_analytics.duckdb"
DATA_DIR = "."

# Check CSVs exist
csvs = ["customers.csv", "products.csv", "stores.csv", "orders.csv", "order_items.csv", "promotions.csv"]
for c in csvs:
    path = os.path.join(DATA_DIR, c)
    if not os.path.exists(path):
        print(f"ERROR: {path} not found. Place CSV files in the same directory as this script.")
        exit(1)

con = duckdb.connect(DB_PATH)

for table in [c.replace(".csv", "") for c in csvs]:
    con.execute(f"CREATE OR REPLACE TABLE {table} AS SELECT * FROM read_csv_auto(\'{DATA_DIR}/{table}.csv\')")
    count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"  Loaded {table}: {count:,} rows")

con.close()
print(f"\nDatabase ready: {DB_PATH}")
