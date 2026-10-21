# ДЗ 3. Развёртывание Apache Hive и загрузка в партиционированную таблицу

Hive 4.0.0-alpha-2 поверх HDFS и YARN из ДЗ 1 и ДЗ 2. Параметры в ../inventory.env.

    team-09-en   PostgreSQL (metastore DB, 5432 только localhost), Hive Metastore (9083), HiveServer2 (10000, UI 10002), клиент beeline
    team-09-nn   NameNode, ResourceManager, DataNode, NodeManager
    team-09-00   Secondary NameNode, DataNode, NodeManager
    team-09-01   DataNode, NodeManager, JobHistory

Запросы Hive превращаются в задачи MapReduce, они выполняются в контейнерах на трёх NodeManager.

Hive стоит на edge-ноде: на ней нет демонов Hadoop и свободно около 3 ГБ памяти, а на внутренних узлах уже по 4-5 JVM. Клиентам нужен только адрес HiveServer2.

## Почему не embedded

В лекции Hive поднимается с embedded Derby: база metastore лежит файлом в каталоге запуска, её открывает один процесс, второй клиент получает блокировку. По условию нужен доступ нескольких клиентов, поэтому схема другая:

    beeline / JDBC-клиенты (сколько угодно)
            |
      HiveServer2 :10000         принимает сессии, компилирует HiveQL, отправляет задачи в YARN
            |  thrift
      Hive Metastore :9083       отдельный процесс, единственный, кто ходит в базу метаданных
            |  JDBC
      PostgreSQL 16 :5432        база metastore, схема создаётся schematool -dbType postgres

Metastore вынесен в отдельный сервис (hive.metastore.uris = thrift://team-09-en:9083), а не встроен в HiveServer2. К нему могут подключаться и другие движки: Spark из следующего ДЗ сможет читать и писать те же таблицы через этот thrift-адрес.

hive.server2.enable.doAs = false: запросы на кластере выполняются от пользователя hadoop, имя клиента (beeline -n) остаётся пользователем сессии. Так не нужно настраивать proxyuser в core-site.xml и перезапускать HDFS.

Пароль пользователя hive в PostgreSQL генерируется при первом запуске в .secrets/metastore_db_password. Каталог в .gitignore, в репозиторий пароль не попадает, hive-site.xml на узле читается только пользователем hadoop. PostgreSQL слушает только localhost, metastore стоит на той же машине.

## Совместимость

Hive 4.0.0-alpha-2 собран под Hadoop 3.3, на стенде Hadoop 3.4.2 и OpenJDK 11. При развёртывании всплыло:

- Hadoop 3.4 больше не кладёт в classpath commons-collections 3.x, перешёл на commons-collections4. Hive её использует, и первая же задача MapReduce падала в map с NoClassDefFoundError: org/apache/commons/collections/CollectionUtils. 02_install_hive.sh копирует commons-collections-3.2.2.jar из lib/ Hive в auxlib/. Всё из auxlib bin/hive сам добавляет в HIVE_AUX_JARS_PATH, и jar уезжает вместе с каждой задачей.
- В lib/ Hive лежит guava 19, у Hadoop 3.4 guava 27. Скрипт отключает guava Hive (переименовывает в .disabled) и кладёт guava из Hadoop, чтобы на classpath была одна версия. Смешение версий guava - известная причина NoSuchMethodError при запуске Hive на Hadoop 3.
- capacity-scheduler по умолчанию отдаёт под ApplicationMaster 10% памяти кластера: 0.1 x 3 x 1536 МБ = 460 МБ, меньше одного AM на 512 МБ. YARN всё равно запускает первый AM, но остальные ждут, и запросы разных клиентов выполнялись строго по очереди: 43, 77 и 108 с вместо одновременного завершения. 03_configure_hive.sh поднимает yarn.scheduler.capacity.maximum-am-resource-percent до 0.5 на ResourceManager и перечитывает очереди без перезапуска (yarn rmadmin -refreshQueues). После этого три клиента завершаются за 52-61 с одновременно.
- skip.header.line.count на пути INSERT ... SELECT через MapReduce не соблюдается, строка заголовка CSV попадала в партицию tx_month=tx_time. В загрузке стоит WHERE tx_id IS NOT NULL: tx_id заголовка при приведении к BIGINT даёт NULL.
- EXPLAIN DEPENDENCY в этой сборке требует классы Tez, поэтому отсекание партиций проверяется по EXPLAIN EXTENDED: в плане перечислены каталоги, которые будут прочитаны.

JDBC-драйвер PostgreSQL (postgresql-42.4.1.jar) входит в дистрибутив, отдельно его ставить не нужно.

Движок выполнения - MapReduce (hive.execution.engine = mr). В Hive 4 он помечен устаревшим, но YARN с MapReduce уже развёрнут в ДЗ 2, а Tez потребовал бы отдельной установки.

Hive 4 при создании таблицы без ACID-свойств регистрирует её в metastore как EXTERNAL_TABLE с external.table.purge = true. Каталог остаётся в warehouse, DROP TABLE удаляет и данные, то есть поведение как у managed-таблицы.

## Данные и партиционирование

data/generate_sales.py генерирует продажи за 2025 год: tx_id, tx_time, region, category, amount, quantity, payment_type. Генератор детерминированный (seed 42), при каждом запуске получается один и тот же CSV на 200 000 строк, около 14 МБ. Размер задаётся SALES_ROWS в inventory.env.

Загрузка в два слоя:

    /data/raw/sales/sales.csv                       сырой CSV в HDFS
            |  hw3.sales_raw                         EXTERNAL TEXTFILE, заголовок отсекается в SELECT
            |  INSERT OVERWRITE ... PARTITION (tx_month)
            v
    /user/hive/warehouse/hw3.db/sales/tx_month=2025-01/...   Parquet
                                     tx_month=2025-02/...
                                     ...                     12 партиций

Партиции динамические: hive.exec.dynamic.partition.mode = nonstrict, значение tx_month берётся из последней колонки SELECT (substr(tx_time, 1, 7)). Hive сам раскладывает строки по каталогам и регистрирует партиции в metastore.

Повторный запуск безопасен: CSV кладётся с -put -f, таблицы создаются через IF NOT EXISTS, INSERT OVERWRITE перезаписывает пришедшие партиции, поэтому строки не дублируются. Если в CSV появится новый месяц, добавится новая партиция, остальные перезапишутся теми же данными.

Партиционирование по месяцу выбрано под типичный запрос "за период". Запрос с WHERE tx_month = '2025-03' читает один каталог из двенадцати, это видно в EXPLAIN EXTENDED.

## Запуск

HDFS и YARN из ДЗ 1 и ДЗ 2 должны быть запущены. С edge-ноды:

    ./hw3_hive/scripts/deploy_hive.sh

Или по шагам:

01_install_postgres.sh - ставит PostgreSQL, генерирует пароль, создаёт пользователя hive и базу metastore.
02_install_hive.sh - скачивает apache-hive-4.0.0-alpha-2-bin.tar.gz с archive.apache.org, сверяет sha256, распаковывает в /opt, заменяет guava, кладёт commons-collections в auxlib, прописывает HIVE_HOME и PATH.
03_configure_hive.sh - генерирует hive-site.xml, hive-env.sh, hive-log4j2.properties, создаёт /tmp/hive и /user/hive/warehouse в HDFS, поднимает долю памяти под AM в YARN, инициализирует схему metastore в PostgreSQL, если её ещё нет.
04_start_hive.sh - запускает Hive Metastore и HiveServer2 и ждёт, пока откроются порты.
05_load_data.sh - генерирует CSV, кладёт в HDFS, создаёт таблицы и загружает данные в партиции.
06_verify_hive.sh - проверка.
stop_hive.sh - останавливает HiveServer2 и Metastore. PostgreSQL и данные остаются.

SQL лежит отдельно в sql/: 01_ddl.sql, 02_load_partitions.sql, 03_check.sql. Его можно выполнить и вручную:

    sudo -u hadoop -i beeline -u jdbc:hive2://team-09-en:10000/default -n $USER \
      --hivevar raw_dir=/data/raw/sales -f ~/hadoop_enjoyer/hw3_hive/sql/01_ddl.sql

## Ручная работа с Hive

    sudo -u hadoop -i beeline -u jdbc:hive2://team-09-en:10000/default -n analyst

    SHOW DATABASES;
    SHOW PARTITIONS hw3.sales;
    SELECT tx_month, count(*) FROM hw3.sales GROUP BY tx_month ORDER BY tx_month;

Интерфейс HiveServer2: http://team-09-en:10002/ во внутренней сети. Снаружи порты закрыты фаерволом площадки (см. hw2_yarn/README.md), открывается через проброс:

    ssh -L 10002:team-09-en:10002 team@171.22.73.198

## Проверка

    ./hw3_hive/scripts/06_verify_hive.sh

Скрипт проверяет процессы и порты Metastore, HiveServer2 и PostgreSQL, что metastore смотрит в PostgreSQL и что в его таблицах TBLS и PARTITIONS есть hw3.sales и её партиции, веб-интерфейс HiveServer2, 12 партиций в SHOW PARTITIONS и каталоги tx_month=* в HDFS, совпадение числа строк в sales_raw и sales, отсекание партиций в плане запроса. Потом запускает три сессии beeline параллельно от разных пользователей, каждая читает свою партицию, и считает открытые соединения к HiveServer2 во время выполнения.

Результат на стенде:

    HiveMetaStore RSS 329 МБ, HiveServer2 RSS 619 МБ
    слушают: 127.0.0.1:5432, *:9083, 10.9.0.10:10000, 10.9.0.10:10002
    jdbc:postgresql://localhost:5432/metastore, thrift://team-09-en:9083
    schema version в PostgreSQL: 4.0.0-alpha-2
    в metastore: hw3.sales, hw3.sales_raw, партиций 12
    HiveServer2 UI http://team-09-en:10002/ -> 200
    SHOW PARTITIONS: tx_month=2025-01 ... tx_month=2025-12, 12 каталогов Parquet по ~0.5 МБ в HDFS
    sales_raw = sales = 200000
    запрос с tx_month = '2025-03' читает один каталог из 12
    analyst1 2025-01 -> analyst1,16926, 13:11:27-13:12:19
    analyst2 2025-06 -> analyst2,16399, 13:11:27-13:12:19
    analyst3 2025-12 -> analyst3,17073, 13:11:27-13:12:28
    максимум одновременных соединений к HiveServer2: 3
    ERROR/FATAL в hive.log: 0

Полный deploy_hive.sh поверх уже развёрнутого Hive отработал за 7 минут: установка и схема пропущены, данные перезаписаны теми же 200 000 строк, дублей нет.

Загрузка по месяцам:

    tx_month | rows  | revenue
    2025-01  | 16926 | 114856532.15
    2025-02  | 15112 | 102816685.08
    2025-03  | 16881 | 114209568.51
    ...
    2025-12  | 17073 | 116335065.21

## Остановка

    ./hw3_hive/scripts/stop_hive.sh

Таблицы и данные сохраняются: метаданные в PostgreSQL, файлы в HDFS. После 04_start_hive.sh всё доступно снова.
