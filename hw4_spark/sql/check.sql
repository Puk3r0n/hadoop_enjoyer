SHOW PARTITIONS hw4.sales_daily;

SELECT tx_month, count(*) AS daily_rows, sum(tx_count) AS tx, sum(revenue) AS revenue
FROM hw4.sales_daily
GROUP BY tx_month
ORDER BY tx_month;

SELECT tx_date, region, category, tx_count, revenue, avg_check, card_share
FROM hw4.sales_daily
WHERE tx_month = '2025-03' AND tx_date = '2025-03-01' AND category_rank = 1
ORDER BY revenue DESC;
