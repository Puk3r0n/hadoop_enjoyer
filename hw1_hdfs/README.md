# ДЗ 1. Развёртывание HDFS

Кластер из 3 DataNode, NameNode и Secondary NameNode. Параметры в ../inventory.env.

    team-09-nn   NameNode (RPC 9000, UI 9870), DataNode (9864)
    team-09-00   Secondary NameNode (UI 9868), DataNode (9864)
    team-09-01   DataNode (9864)
    team-09-en   только клиент hdfs, демонов нет

DataNode стоят на всех трёх внутренних узлах - так получаются нужные 3 DataNode при четырёх выданных ВМ. Secondary NameNode вынесен с узла NameNode, чтобы контрольные точки не терялись вместе с ним.

## Конфигурация

fs.defaultFS = hdfs://team-09-nn:9000, dfs.replication = 3, то есть каждый блок лежит на всех трёх DataNode.

Данные в /data/hadoop/{namenode,namesecondary,datanode}, логи в /var/log/hadoop, pid-файлы в /data/hadoop/pids. В /tmp их держать нельзя: systemd их вычищает и демоны перестают останавливаться штатно.

Демоны работают от пользователя hadoop, он же суперпользователь HDFS. dfs.hosts указывает на файл workers, поэтому зарегистрироваться в NameNode могут только перечисленные в нём DataNode. Heap под узлы с 3 ГБ RAM: NameNode 512 МБ, Secondary NameNode и DataNode по 256 МБ.

## Запуск

    ./hw1_hdfs/scripts/deploy_hdfs.sh

Или по шагам:

01_prepare_nodes.sh - ставит OpenJDK 11, создаёт пользователя hadoop, каталоги данных, логов и pid, правит /etc/hosts.
02_install_hadoop.sh - скачивает hadoop-3.4.2.tar.gz на edge, сверяет sha512 с downloads.apache.org, раскладывает на узлы в /opt, прописывает переменные окружения.
03_configure_hdfs.sh - генерирует core-site.xml, hdfs-site.xml, workers, блок в hadoop-env.sh и рассылает на узлы.
04_start_hdfs.sh - форматирует NameNode, если он ещё не отформатирован, и запускает демоны.
05_verify_hdfs.sh - проверка кластера.
stop_hdfs.sh - останавливает демоны, данные сохраняются.

## Про строку 127.0.1.1

Ubuntu резолвит собственное имя узла в 127.0.1.1. Hadoop строит адреса демонов от имени хоста, поэтому NameNode занимает loopback и DataNode с других узлов до него не доходят - кластер собирается с одной живой нодой вместо трёх. Поэтому 01_prepare_nodes.sh комментирует эту строку и добавляет блок с внутренними адресами всех узлов.

## Проверка

    ./hw1_hdfs/scripts/05_verify_hdfs.sh

Скрипт ждёт регистрации DataNode и выхода из safe mode, читает dfsadmin -report, проверяет веб-интерфейсы NameNode и Secondary NameNode, читает состояние NameNode через JMX, записывает и читает файл в HDFS, считает ERROR/FATAL в логах всех демонов без штатных сообщений об остановке.

Результат на стенде:

    Live datanodes (3), мёртвых нет, у всех Decommission Status : Normal
    FSState: Operational, NumLiveDataNodes: 3, NumDeadDataNodes: 0, UnderReplicatedBlocks: 0
    fsck: Status HEALTHY, Average block replication 3.0
    ERROR/FATAL в логах: 0 на всех четырёх узлах

Оба варианта проверки из условия выполнены: в интерфейсе NameNode три работающих DataNode и ни одной деградировавшей, критических ошибок в логах нет.
