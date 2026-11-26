WITH item_integrity_flags AS (
  SELECT
    oi.id AS item_id,
    oi.order_id,
    CASE 
      WHEN oi.order_id = 1 THEN 1 
      ELSE 0 
    END AS is_target_order,
    CASE 
      WHEN o.id IS NULL THEN 1 
      ELSE 0 
    END AS is_orphaned
  FROM order_items oi
  LEFT JOIN orders o 
    ON oi.order_id = o.id
),
aggregated_metrics AS (
  SELECT
    SUM(is_target_order) AS raw_order_1_count,
    SUM(is_orphaned) AS raw_orphaned_count
  FROM item_integrity_flags
)
SELECT
  COALESCE(raw_order_1_count, 0) AS order_1_items,
  COALESCE(raw_orphaned_count, 0) AS orphaned_items
FROM aggregated_metrics;