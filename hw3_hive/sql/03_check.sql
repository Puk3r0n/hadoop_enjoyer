SHOW PARTITIONS hw3.sales;

SELECT tx_month, count(*) AS rows_cnt, round(sum(amount), 2) AS revenue
FROM hw3.sales
GROUP BY tx_month
ORDER BY tx_month;

SELECT region, count(*) AS rows_cnt
FROM hw3.sales
WHERE tx_month = '2025-03'
GROUP BY region
ORDER BY rows_cnt DESC;
