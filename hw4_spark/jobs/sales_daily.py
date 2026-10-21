import argparse

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType

RAW_COLUMNS = ["tx_id", "tx_time", "region", "category", "amount", "quantity", "payment_type"]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="каталог с CSV в HDFS")
    parser.add_argument("--table", required=True, help="таблица результата, db.table")
    return parser.parse_args()


def read_raw(spark, path):
    schema = StructType([StructField(c, StringType()) for c in RAW_COLUMNS])
    return spark.read.option("header", "true").schema(schema).csv(path)


def clean(raw):
    typed = raw.select(
        F.col("tx_id").cast("bigint").alias("tx_id"),
        F.to_timestamp("tx_time", "yyyy-MM-dd HH:mm:ss").alias("tx_time"),
        F.trim("region").alias("region"),
        F.lower(F.trim("category")).alias("category"),
        F.col("amount").cast("decimal(12,2)").alias("amount"),
        F.col("quantity").cast("int").alias("quantity"),
        F.lower(F.trim("payment_type")).alias("payment_type"),
    )
    valid = (
        F.col("tx_id").isNotNull() & F.col("tx_time").isNotNull()
        & F.col("region").isNotNull() & F.col("category").isNotNull()
        & (F.col("amount") > 0) & (F.col("quantity") > 0)
    )
    return typed.filter(valid).dropDuplicates(["tx_id"])


def daily_metrics(sales):
    daily = (
        sales
        .withColumn("tx_date", F.to_date("tx_time"))
        .groupBy("tx_date", "region", "category")
        .agg(
            F.count("*").alias("tx_count"),
            F.sum("quantity").cast("bigint").alias("items_sold"),
            F.sum("amount").cast("decimal(16,2)").alias("revenue"),
            F.avg("amount").cast("decimal(12,2)").alias("avg_check"),
            F.max("amount").alias("max_check"),
            F.round(F.avg((F.col("payment_type") == "card").cast("int")), 4).alias("card_share"),
        )
    )
    by_revenue = Window.partitionBy("tx_date", "region").orderBy(F.desc("revenue"), "category")
    return (
        daily
        .withColumn("category_rank", F.row_number().over(by_revenue))
        .withColumn("tx_month", F.date_format("tx_date", "yyyy-MM"))
    )


def main():
    args = parse_args()
    spark = SparkSession.builder.appName("hw4_sales_daily").enableHiveSupport().getOrCreate()
    sc = spark.sparkContext
    print(f"applicationId={sc.applicationId} master={sc.master} executors={sc.getConf().get('spark.executor.instances')}")
    print(f"defaultFS={sc._jsc.hadoopConfiguration().get('fs.defaultFS')}")

    raw = read_raw(spark, args.input)
    sales = clean(raw).cache()
    raw_rows, clean_rows = raw.count(), sales.count()
    print(f"raw_rows={raw_rows} clean_rows={clean_rows} rejected={raw_rows - clean_rows}")

    result = daily_metrics(sales)
    db = args.table.split(".")[0]
    spark.sql(f"CREATE DATABASE IF NOT EXISTS {db}")
    (
        result.repartition("tx_month")
        .write.mode("overwrite")
        .format("parquet")
        .partitionBy("tx_month")
        .saveAsTable(args.table)
    )

    written = spark.table(args.table)
    print(f"table={args.table} rows={written.count()} partitions={written.select('tx_month').distinct().count()}")
    written.groupBy("tx_month").agg(F.sum("tx_count").alias("tx"), F.sum("revenue").alias("revenue")) \
        .orderBy("tx_month").show(12, truncate=False)
    spark.stop()


if __name__ == "__main__":
    main()
