# ДЗ 5. Процесс обработки данных в потоке Prefect

Поток Prefect на edge-ноде запускает Spark-сессию под YARN на кластере из ДЗ 1-4, читает из HDFS продажи, загруженные в ДЗ 3, считает месячную витрину и сохраняет её таблицей в Hive Metastore. Параметры в ../inventory.env.

Почему Prefect, а не Airflow: на edge 4 ГБ памяти, и там уже работают Hive Metastore, HiveServer2, PostgreSQL и driver Spark. Airflow требует постоянных scheduler, webserver и своей базы. Prefect запускает поток обычным процессом Python: при запуске поднимается временный локальный API на SQLite, после завершения он останавливается.

## Поток

flows/sales_pipeline.py, поток hw5-sales-monthly, пять задач по шагам задания:

    1. Spark-сессия под YARN     SparkSession.builder.master("yarn").enableHiveSupport(); driver в процессе потока на edge, executor в контейнерах YARN
    2. Подключение к HDFS        FileSystem по fs.defaultFS из HADOOP_CONF_DIR, проверка, что /data/raw/sales существует, список файлов
    3. Чтение данных из HDFS     hdfs:///data/raw/sales/sales.csv, 200 000 строк, схема из строковых колонок
    4. Трансформации            приведение типов (bigint, timestamp, decimal(12,2), int), очистка и дедупликация по tx_id,
                                 агрегация по месяцу, региону и категории, доля категории в выручке региона (окно),
                                 рост выручки к прошлому месяцу (lag)
    5. Сохранение таблицы        hw5.sales_monthly, Parquet, partitionBy(tx_month), saveAsTable в Hive Metastore

Сессия Spark передаётся между задачами как объект: задачи выполняются в одном процессе, поэтому driver один на весь поток. В конце поток вызывает spark.stop(), и YARN освобождает контейнеры.

Схема таблицы hw5.sales_monthly:

    region        string          регион
    category      string          категория
    tx_count      bigint          число продаж
    items_sold    bigint          продано штук
    revenue       decimal(16,2)   выручка
    avg_check     decimal(12,2)   средний чек
    card_share    double          доля оплат картой
    region_share  double          доля категории в выручке региона за месяц
    mom_growth    double          рост выручки к прошлому месяцу, NULL для января
    tx_month      string          партиция, yyyy-MM

Таблица отдельная от hw4.sales_daily. Повторный запуск безопасен: mode("overwrite") пересоздаёт таблицу целиком, строки не дублируются.

## Запуск

HDFS, YARN, Hive и Spark из ДЗ 1-4 должны быть развёрнуты, данные ДЗ 3 загружены. С edge-ноды:

    ./hw5_prefect/scripts/deploy_prefect.sh

Или по шагам:

01_install_prefect.sh - venv /opt/prefect с Prefect, PREFECT_HOME в /var/lib/prefect, логи в /var/log/prefect.
02_run_flow.sh - запуск потока от пользователя hadoop. Полный лог - /var/log/prefect/sales_monthly_<время>.log на edge.
03_verify.sh - проверка.

Запуск потока вручную:

    sudo -u hadoop -i env PREFECT_HOME=/var/lib/prefect SPARK_HOME=/opt/spark PYSPARK_PYTHON=python3 \
      /opt/prefect/bin/python ~/hadoop_enjoyer/hw5_prefect/flows/sales_pipeline.py \
      --input /data/raw/sales --table hw5.sales_monthly

## Проверка

    ./hw5_prefect/scripts/03_verify.sh

Скрипт проверяет:

- в логе потока все пять задач и сам поток в состоянии Completed;
- приложение hw5_sales_monthly в YARN завершилось SUCCEEDED, executor по event log работали на узлах кластера;
- таблица в Hive-совместимом формате (ParquetHiveSerDe), beeline видит 12 партиций;
- сумма tx_count по витрине равна числу строк в hw3.sales;
- выручка за июнь по витрине совпадает с суммой amount из hw3.sales, которую считает Hive;
- выборка: лидер по выручке в каждом регионе за июнь.

Результат на стенде (deploy_prefect.sh поверх установленного Prefect, около 5 минут; сам поток около минуты):

    Task run '1. Spark-сессия под YARN'   applicationId=application_1791069264184_0048 master=yarn deployMode=client executors=2
    Task run '2. Подключение к HDFS'      fs.defaultFS=hdfs://team-09-nn:9000, sales.csv 14007031 байт
    Task run '3. Чтение данных из HDFS'   прочитано строк: 200000
    Task run '4. Трансформации'           валидных транзакций: 200000, строк витрины: 432
    Task run '5. Сохранение таблицы'      table=hw5.sales_monthly rows=432 partitions=12 tx_total=200000
    Flow run 'dancing-piculet' - Finished in state Completed()

    application_1791069264184_0048 hw5_sales_monthly SPARK Final-State : SUCCEEDED
    executor запускались на: team-09-01 team-09-nn
    SerDe: org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe, партиций: 12
    hw5.sales_monthly: строк 432, транзакций в них 200000; в hw3.sales: 200000
    выручка 2025-06: hw3.sales 112441873.75, hw5.sales_monthly 112441873.75

    лидер каждого региона в 2025-06 (beeline): регион, категория, продаж, выручка, доля в регионе, рост к маю
    2025-06,Санкт-Петербург,electronics,489,8818482.70,0.4470,0.0816
    2025-06,Казань,electronics,488,8749244.39,0.4573,0.0421
    2025-06,Краснодар,electronics,484,8622819.08,0.4610,-0.0289
    ...

432 строки = 12 месяцев x 6 регионов x 6 категорий.
