-- Cost tracking per dbt model: warehouse query history joined to billing list prices.
-- dbt-databricks tags each query with its node in the query comment ("node_id": "model.upi_reliability.<name>").
WITH q AS (
  SELECT
    regexp_extract(statement_text, '"node_id": "([^"]+)"', 1)            AS dbt_node,
    date_trunc('month', start_time)                                       AS month,
    total_duration_ms, read_bytes, produced_rows, compute.warehouse_id     AS warehouse_id
  FROM system.query.history
  WHERE compute.warehouse_id = 'b36027f0bc1ea75e'
    AND statement_text LIKE '%"app": "dbt"%'
    AND start_time >= date_sub(current_date(), 90)
),
wh AS (  -- warehouse DBUs and list cost per month
  SELECT date_trunc('month', u.usage_date) AS month,
         sum(u.usage_quantity) AS dbus,
         sum(u.usage_quantity * p.pricing.default) AS list_cost_usd
  FROM system.billing.usage u
  JOIN system.billing.list_prices p
    ON u.sku_name = p.sku_name AND u.usage_start_time >= p.price_start_time
   AND (p.price_end_time IS NULL OR u.usage_start_time < p.price_end_time)
  WHERE u.usage_metadata.warehouse_id = 'b36027f0bc1ea75e'
  GROUP BY 1
)
SELECT q.month, q.dbt_node,
       count(*) AS queries,
       round(sum(q.total_duration_ms) / 1000, 1) AS runtime_s,
       round(sum(q.read_bytes) / 1e6, 1) AS read_mb,
       -- allocate the month's warehouse cost by share of dbt runtime
       round(wh.list_cost_usd * sum(q.total_duration_ms) / sum(sum(q.total_duration_ms)) OVER (PARTITION BY q.month), 4) AS est_cost_usd
FROM q JOIN wh USING (month)
WHERE q.dbt_node <> ''
GROUP BY q.month, q.dbt_node, wh.list_cost_usd
ORDER BY q.month DESC, est_cost_usd DESC;
