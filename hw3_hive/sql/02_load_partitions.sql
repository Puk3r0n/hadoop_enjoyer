SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

INSERT OVERWRITE TABLE hw3.sales PARTITION (tx_month)
SELECT
  tx_id,
  CAST(tx_time AS TIMESTAMP),
  region,
  category,
  amount,
  quantity,
  payment_type,
  substr(tx_time, 1, 7) AS tx_month
FROM hw3.sales_raw
WHERE tx_id IS NOT NULL;

ANALYZE TABLE hw3.sales PARTITION (tx_month) COMPUTE STATISTICS;
