SELECT
  (SELECT COUNT(*) FROM order_items WHERE order_id = 1) AS order_1_items,
  (SELECT COUNT(*)
     FROM order_items i
    WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.id = i.order_id)) AS orphaned_items;