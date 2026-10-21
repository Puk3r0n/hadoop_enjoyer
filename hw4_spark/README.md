# ДЗ 4. Apache Spark под управлением YARN

Spark 3.5.9 на кластере из ДЗ 1-3: читает данные, которые в ДЗ 3 загружены в HDFS, трансформирует их, сохраняет партиционированной таблицей в Hive Metastore, и эта таблица читается стандартным клиентом Hive (beeline). Параметры в ../inventory.env.

    team-09-en   клиент Spark (spark-submit, driver), Hive Metastore :9083, HiveServer2 :10000
    team-09-nn   ResourceManager, NameNode, DataNode, NodeManager    executor Spark в контейнерах YARN
    team-09-00   DataNode, NodeManager                               executor Spark в контейнерах YARN
    team-09-01   DataNode, NodeManager, JobHistory                   ApplicationMaster или executor

Spark не держит своих демонов. На edge стоит только дистрибутив, приложение запускается spark-submit --master yarn: ResourceManager выдаёт контейнер под ApplicationMaster, AM запрашивает контейнеры под executor на NodeManager. Driver работает на edge (deploy mode client), поэтому вывод задачи виден прямо в консоли.

## Что делает задача

jobs/sales_daily.py:

    hdfs:///data/raw/sales/sales.csv          200 000 продаж из ДЗ 3, CSV
      | чтение со схемой из строковых колонок
      | приведение типов: tx_id -> bigint, tx_time -> timestamp, amount -> decimal(12,2), quantity -> int
      | очистка: trim и lower в справочных полях, отсев строк с NULL и неположительной суммой или количеством, дедупликация по tx_id
      | агрегация по дню, региону и категории: число продаж, штук, выручка, средний и максимальный чек, доля оплат картой
      | оконная функция: место категории по выручке в регионе за день (category_rank)
      | tx_month = yyyy-MM из даты
      v
    hw4.sales_daily                           Parquet, partitionBy(tx_month), saveAsTable в Hive Metastore
      /user/hive/warehouse/hw4.db/sales_daily/tx_month=2025-01/ ... tx_month=2025-12/

Сессия создаётся с enableHiveSupport(). Spark подключается к HDFS по fs.defaultFS из конфигов Hadoop (HADOOP_CONF_DIR) и к metastore по hive.metastore.uris из $SPARK_HOME/conf/hive-site.xml. Это тот же metastore, что у HiveServer2, поэтому таблица, записанная Spark, сразу видна в beeline.

Схема таблицы:

    tx_date        date            день
    region         string          регион
    category       string          категория
    tx_count       bigint          число продаж
    items_sold     bigint          продано штук
    revenue        decimal(16,2)   выручка
    avg_check      decimal(12,2)   средний чек
    max_check      decimal(12,2)   максимальный чек
    card_share     double          доля оплат картой
    category_rank  int             место категории по выручке в регионе за день
    tx_month       string          партиция, yyyy-MM

Повторный запуск безопасен: mode("overwrite") пересоздаёт таблицу целиком, строки не дублируются. Hive 4 регистрирует таблицу как EXTERNAL с external.table.purge = true, поэтому при пересоздании удаляются и старые файлы.

## Совместимость с Hive Metastore 4.0.0-alpha-2

У Spark 3.5 встроен клиент metastore версии 2.3.9, а spark.sql.hive.metastore.version можно поднять максимум до 3.1.3. Клиента для Hive 4 нет. Встроенный клиент 2.3.9 с metastore 4.0.0-alpha-2 работает: для CREATE DATABASE, CREATE и DROP TABLE, добавления партиций и чтения схемы thrift-API обратно совместим. Проверено на стенде: таблица и 12 партиций появились в TBLS и PARTITIONS в PostgreSQL, beeline их читает. Поэтому запасной вариант (Spark пишет Parquet в HDFS, а таблицу создаёт beeline) не понадобился.

Чтобы Hive мог прочитать таблицу, Spark должен сохранить её в Hive-совместимом виде. Для формата parquet он так и делает: в metastore записываются ParquetHiveSerDe и MapredParquetInputFormat, это проверяет 04_verify_spark.sh. Дополнительно стоит spark.sql.parquet.writeLegacyFormat = true: decimal пишутся так же, как их пишет Hive, а не в компактном формате Spark.

## Ресурсы

Узлы по 2 vCPU и 3 ГБ, NodeManager отдаёт YARN 1536 МБ, минимальный контейнер 256 МБ. Spark к памяти executor добавляет overhead не меньше 384 МБ, YARN округляет запрос вверх до кратного 256:

    driver           768 МБ   на edge, вне YARN
    ApplicationMaster 512 + 384 -> 1024 МБ
    executor x 2     768 + 384 -> 1280 МБ, 1 ядро

Итого 3.5 ГБ из 4.5 ГБ YARN, каждый executor помещается в один NodeManager. На edge, кроме driver, работают Metastore и HiveServer2, на 768 МБ driver памяти хватает.

spark.yarn.archive: jar-файлы Spark (300 МБ) один раз загружаются в HDFS архивом /apps/spark/spark-3.5.9-jars.zip. Без этого каждый spark-submit заново копирует их в HDFS.

spark.eventLog.dir = hdfs:///spark-logs: события приложения остаются после его завершения, по ним проверка находит узлы, на которых работали executor.

## Запуск

HDFS, YARN и Hive из ДЗ 1-3 должны быть запущены, данные ДЗ 3 загружены (hw3_hive/scripts/05_load_data.sh). С edge-ноды:

    ./hw4_spark/scripts/deploy_spark.sh

Или по шагам:

01_install_spark.sh - скачивает spark-3.5.9-bin-hadoop3.tgz, сверяет sha512, распаковывает в /opt, ссылка /opt/spark, PATH.
02_configure_spark.sh - генерирует spark-defaults.conf, spark-env.sh, hive-site.xml и log4j2.properties, создаёт /spark-logs в HDFS и загружает архив jar-файлов.
03_run_job.sh - spark-submit jobs/sales_daily.py под YARN. Полный лог - /var/log/spark/sales_daily_<время>.log на edge.
04_verify_spark.sh - проверка.

Spark не держит демонов, поэтому скрипта остановки нет: приложение освобождает контейнеры YARN после завершения.

Запуск задачи вручную:

    sudo -u hadoop -i spark-submit --name hw4_sales_daily ~/hadoop_enjoyer/hw4_spark/jobs/sales_daily.py \
      --input /data/raw/sales --table hw4.sales_daily

Проверка стандартным клиентом Hive вручную:

    sudo -u hadoop -i beeline -u jdbc:hive2://team-09-en:10000/default -n analyst -f ~/hadoop_enjoyer/hw4_spark/sql/check.sql

Приложение видно в интерфейсе ResourceManager: http://171.22.73.198:8088/cluster, или через hw2_yarn/scripts/connect_ui.sh, если входящие порты закрыты (см. hw2_yarn/README.md). Пока задача работает, Spark UI driver доступен на http://team-09-en:4040 во внутренней сети.

## Проверка

    ./hw4_spark/scripts/04_verify_spark.sh

Скрипт проверяет:

- последнее приложение hw4_sales_daily в YARN завершилось со статусом SUCCEEDED, а executor по event log работали на узлах кластера;
- таблица и её партиции есть в базе metastore в PostgreSQL;
- SerDe таблицы Hive-совместимый;
- beeline видит 12 партиций, каталоги tx_month=* лежат в HDFS;
- сумма tx_count по витрине равна числу строк в hw3.sales, то есть агрегаты сохранили все транзакции;
- выборка из одной партиции;
- выручка за июнь по витрине Spark совпадает с суммой amount из hw3.sales, которую считает Hive.

Результат на стенде:

    Spark version 3.5.9, встроенный клиент metastore hive-metastore-2.3.9.jar
    applicationId=application_1791069264184_0033 master=yarn executors=2
    defaultFS=hdfs://team-09-nn:9000
    raw_rows=200000 clean_rows=200000 rejected=0
    table=hw4.sales_daily rows=13140 partitions=12

    Application-Type : SPARK, Queue : root.default, Final-State : SUCCEEDED
    executor запускались на: team-09-00 team-09-nn
    hw4.sales_daily (EXTERNAL_TABLE), партиций в metastore: 12
    SerDe: org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe
    SHOW PARTITIONS: tx_month=2025-01 ... tx_month=2025-12, по одному файлу Parquet ~25 КБ
    hw4.sales_daily: строк 13140, транзакций в них 200000; в исходной hw3.sales: 200000

    лидеры по выручке 2025-03-01 (beeline, одна партиция):
    2025-03-01,Краснодар,electronics,19,275236.82,14486.15,0.1579
    2025-03-01,Санкт-Петербург,electronics,20,256525.25,12826.26,0.35
    2025-03-01,Казань,electronics,17,252061.89,14827.17,0.4118
    ...

    hw3.sales 2025-06: 112441873.75, hw4.sales_daily 2025-06: 112441873.75

13 140 строк = 365 дней x 6 регионов x 6 категорий: в каждый день продаётся каждая категория в каждом регионе.

Задача выполняется около минуты. Полный deploy_spark.sh поверх уже установленного Spark занял 4.5 минуты: установка и загрузка архива пропущены, таблица перезаписана теми же 13 140 строками. Большая часть времени уходит на запросы beeline в проверке, они идут через MapReduce.
