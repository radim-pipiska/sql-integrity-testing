SELECT
  COALESCE(SUM(CASE WHEN oi.order_id = 1 THEN 1 ELSE 0 END), 0) AS order_1_items,
  COALESCE(SUM(CASE WHEN o.id IS NULL THEN 1 ELSE 0 END), 0) AS orphaned_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.id;
