DROP TABLE IF EXISTS payments_u;
CREATE TABLE payments_u (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  order_ref    TEXT    NOT NULL UNIQUE,
  amount_cents INTEGER NOT NULL,
  status       TEXT    NOT NULL
);

INSERT INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');
INSERT INTO payments_u (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');
