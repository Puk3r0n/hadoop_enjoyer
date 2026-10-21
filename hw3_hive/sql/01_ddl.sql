CREATE DATABASE IF NOT EXISTS hw3;

CREATE EXTERNAL TABLE IF NOT EXISTS hw3.sales_raw (
  tx_id        BIGINT,
  tx_time      STRING,
  region       STRING,
  category     STRING,
  amount       DECIMAL(12,2),
  quantity     INT,
  payment_type STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${hivevar:raw_dir}'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE TABLE IF NOT EXISTS hw3.sales (
  tx_id        BIGINT,
  tx_time      TIMESTAMP,
  region       STRING,
  category     STRING,
  amount       DECIMAL(12,2),
  quantity     INT,
  payment_type STRING
)
PARTITIONED BY (tx_month STRING)
STORED AS PARQUET;
