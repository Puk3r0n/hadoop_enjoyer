import argparse
import os
import sys

from prefect import flow, get_run_logger, task
from prefect.cache_policies import NO_CACHE

SPARK_HOME = os.environ.get("SPARK_HOME", "/opt/spark")
sys.path[:0] = [f"{SPARK_HOME}/python", f"{SPARK_HOME}/python/lib/py4j-0.10.9.7-src.zip"]

from pyspark.sql import SparkSession, Window  # noqa: E402
from pyspark.sql import functions as F  # noqa: E402
from pyspark.sql.types import StringType, StructField, StructType  # noqa: E402

RAW_COLUMNS = ["tx_id", "tx_time", "region", "category", "amount", "quantity", "payment_type"]


@task(name="1. Spark-сессия под YARN", cache_policy=NO_CACHE)
def start_spark(app_name):
    spark = (
        SparkSession.builder.appName(app_name).master("yarn")
        .config("spark.ui.showConsoleProgress", "false")
        .enableHiveSupport().getOrCreate()
    )
    sc = spark.sparkContext
    get_run_logger().info(
        "applicationId=%s master=%s deployMode=%s executors=%s",
        sc.applicationId, sc.master, sc.getConf().get("spark.submit.deployMode"),
        sc.getConf().get("spark.executor.instances"),
    )
    return spark


@task(name="2. Подключение к HDFS", cache_policy=NO_CACHE)
def connect_hdfs(spark, input_dir):
    jvm = spark.sparkContext._jvm
    conf = spark.sparkContext._jsc.hadoopConfiguration()
    fs = jvm.org.apache.hadoop.fs.FileSystem.get(conf)
    path = jvm.org.apache.hadoop.fs.Path(input_dir)
    if not fs.exists(path):
        raise FileNotFoundError(f"нет {input_dir} в HDFS: сначала hw3_hive/scripts/05_load_data.sh")
    files = [(s.getPath().toString(), s.getLen()) for s in fs.listStatus(path) if s.isFile()]
    logger = get_run_logger()
    logger.info("fs.defaultFS=%s", conf.get("fs.defaultFS"))
    for name, size in files:
        logger.info("  %s  %d байт", name, size)
    return [name for name, _ in files]


@task(name="3. Чтение данных из HDFS", cache_policy=NO_CACHE)
def read_raw(spark, input_dir):
    schema = StructType([StructField(c, StringType()) for c in RAW_COLUMNS])
    raw = spark.read.option("header", "true").schema(schema).csv(input_dir)
    get_run_logger().info("прочитано строк: %d", raw.count())
    return raw


@task(name="4. Трансформации", cache_policy=NO_CACHE)
def transform(raw):
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
    sales = typed.filter(valid).dropDuplicates(["tx_id"]).withColumn("tx_month", F.date_format("tx_time", "yyyy-MM"))

    monthly = sales.groupBy("tx_month", "region", "category").agg(
        F.count("*").alias("tx_count"),
        F.sum("quantity").cast("bigint").alias("items_sold"),
        F.sum("amount").cast("decimal(16,2)").alias("revenue"),
        F.avg("amount").cast("decimal(12,2)").alias("avg_check"),
        F.round(F.avg((F.col("payment_type") == "card").cast("int")), 4).alias("card_share"),
    )
    region_month = Window.partitionBy("tx_month", "region")
    history = Window.partitionBy("region", "category").orderBy("tx_month")
    result = (
        monthly
        .withColumn("region_share", F.round(F.col("revenue") / F.sum("revenue").over(region_month), 4))
        .withColumn("prev_revenue", F.lag("revenue").over(history))
        .withColumn(
            "mom_growth",
            F.round((F.col("revenue") - F.col("prev_revenue")) / F.col("prev_revenue"), 4).cast("double"),
        )
        .drop("prev_revenue")
    )
    get_run_logger().info("валидных транзакций: %d, строк витрины: %d", sales.count(), result.count())
    return result


@task(name="5. Сохранение таблицы", cache_policy=NO_CACHE)
def save_table(spark, df, table):
    db = table.split(".")[0]
    spark.sql(f"CREATE DATABASE IF NOT EXISTS {db}")
    (
        df.repartition("tx_month")
        .write.mode("overwrite")
        .format("parquet")
        .partitionBy("tx_month")
        .saveAsTable(table)
    )
    written = spark.table(table)
    rows, parts = written.count(), written.select("tx_month").distinct().count()
    tx = written.agg(F.sum("tx_count")).first()[0]
    get_run_logger().info("table=%s rows=%d partitions=%d tx_total=%d", table, rows, parts, tx)
    return {"table": table, "rows": rows, "partitions": parts, "tx_total": tx}


@flow(name="hw5-sales-monthly", log_prints=True)
def sales_pipeline(input_dir="/data/raw/sales", table="hw5.sales_monthly"):
    spark = start_spark("hw5_sales_monthly")
    try:
        connect_hdfs(spark, input_dir)
        raw = read_raw(spark, input_dir)
        result = transform(raw)
        return save_table(spark, result, table)
    finally:
        spark.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="/data/raw/sales")
    parser.add_argument("--table", default="hw5.sales_monthly")
    args = parser.parse_args()
    print(sales_pipeline(args.input, args.table))
