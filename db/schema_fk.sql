DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
  id        INTEGER PRIMARY KEY,
  order_ref TEXT NOT NULL UNIQUE
);

CREATE TABLE order_items (
  id       INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  sku      TEXT NOT NULL
);

INSERT INTO orders (id, order_ref) VALUES (1, 'ORD-1001');
