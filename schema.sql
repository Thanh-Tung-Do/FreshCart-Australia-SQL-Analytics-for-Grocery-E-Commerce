-- =============================================================================
-- FRESHCART AUSTRALIA: DATABASE SCHEMA
-- =============================================================================
-- This script creates all tables with explicit data types, primary keys,
-- foreign keys, and constraints. Run this before loading data from CSVs.
-- =============================================================================

-- Drop tables in reverse dependency order (if rebuilding)
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS promotions;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;


-- -----------------------------------------------------------------------------
-- DIMENSION: customers
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     VARCHAR(6)   NOT NULL PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    state           VARCHAR(3)   NOT NULL,
    city            VARCHAR(50)  NOT NULL,
    signup_date     DATE         NOT NULL,
    customer_segment VARCHAR(10) NOT NULL
        CHECK (customer_segment IN ('Regular', 'Premium', 'Budget'))
);


-- -----------------------------------------------------------------------------
-- DIMENSION: products
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id      VARCHAR(5)     NOT NULL PRIMARY KEY,
    product_name    VARCHAR(100)   NOT NULL,
    category        VARCHAR(20)    NOT NULL,
    subcategory     VARCHAR(30)    NOT NULL,
    brand           VARCHAR(30)    NOT NULL,
    unit_price      DECIMAL(10,2)  NOT NULL CHECK (unit_price > 0),
    unit_cost       DECIMAL(10,2)  NOT NULL CHECK (unit_cost > 0),
    is_active       BOOLEAN        NOT NULL DEFAULT TRUE
);


-- -----------------------------------------------------------------------------
-- DIMENSION: stores
-- -----------------------------------------------------------------------------
CREATE TABLE stores (
    store_id        VARCHAR(4)   NOT NULL PRIMARY KEY,
    store_name      VARCHAR(50)  NOT NULL,
    state           VARCHAR(3)   NOT NULL,
    city            VARCHAR(50)  NOT NULL,
    opened_date     DATE         NOT NULL,
    store_size_sqm  INTEGER      NOT NULL CHECK (store_size_sqm > 0)
);


-- -----------------------------------------------------------------------------
-- DIMENSION: promotions
-- -----------------------------------------------------------------------------
CREATE TABLE promotions (
    promo_id        VARCHAR(5)     NOT NULL PRIMARY KEY,
    promo_name      VARCHAR(50)    NOT NULL,
    start_date      DATE           NOT NULL,
    end_date        DATE           NOT NULL,
    discount_pct    DECIMAL(4,2)   NOT NULL CHECK (discount_pct BETWEEN 0 AND 1),
    CHECK (end_date >= start_date)
);


-- -----------------------------------------------------------------------------
-- FACT: orders
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id        VARCHAR(7)   NOT NULL PRIMARY KEY,
    customer_id     VARCHAR(6)   NOT NULL REFERENCES customers(customer_id),
    order_date      DATE         NOT NULL,
    channel         VARCHAR(20)  NOT NULL
        CHECK (channel IN ('Online', 'In-Store', 'Click & Collect')),
    store_id        VARCHAR(4)   REFERENCES stores(store_id),
    promo_id        VARCHAR(5)   REFERENCES promotions(promo_id),
    status          VARCHAR(15)  NOT NULL
        CHECK (status IN ('Processing', 'Shipped', 'Delivered', 'Returned', 'Cancelled'))
);


-- -----------------------------------------------------------------------------
-- FACT: order_items
-- -----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_id          VARCHAR(7)     NOT NULL REFERENCES orders(order_id),
    line_item         INTEGER        NOT NULL,
    product_id        VARCHAR(5)     NOT NULL REFERENCES products(product_id),
    quantity          INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price        DECIMAL(10,2)  NOT NULL CHECK (unit_price > 0),
    discount_pct      DECIMAL(4,2)   NOT NULL DEFAULT 0 CHECK (discount_pct >= 0),
    final_unit_price  DECIMAL(10,2)  NOT NULL CHECK (final_unit_price > 0),
    PRIMARY KEY (order_id, line_item)
);
