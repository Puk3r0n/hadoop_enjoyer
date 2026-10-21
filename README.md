# hadoop enjoyer

Команда team-09: Шарифуллин Карим, Керопьян Артур, Латышев Иван, Киселева Анна.

ДЗ отправляется от лидера команды: Шарифуллин Карим, @puker0n.

hw1_hdfs - развёртывание HDFS: NameNode, Secondary NameNode, 3 DataNode.
hw2_yarn - развёртывание YARN и публикация веб-интерфейсов демонов наружу.
hw3_hive - развёртывание Hive с внешним metastore на PostgreSQL и загрузка данных в партиционированную таблицу.

inventory.env - параметры стенда: узлы, роли, версии, пути, ресурсы.
common/lib.sh - общие функции скриптов.

## Стенд

4 ВМ Ubuntu 24.04, 2 vCPU, 3 ГБ RAM. Снаружи доступна только edge-нода.

    team-09-en  10.9.0.10  edge: клиент, отсюда запускаются скрипты, nginx, Hive Metastore, HiveServer2, PostgreSQL
    team-09-nn  10.9.0.11  NameNode, DataNode, ResourceManager, NodeManager
    team-09-00  10.9.0.12  Secondary NameNode, DataNode, NodeManager
    team-09-01  10.9.0.13  DataNode, NodeManager, JobHistory Server

Hadoop 3.4.2, Hive 4.0.0-alpha-2, PostgreSQL 16, OpenJDK 11.

## Запуск

Скрипты запускаются с edge-ноды. Ей нужен ssh-доступ по ключу ко всем узлам и sudo без пароля.

    scp -r hadoop_enjoyer team@171.22.73.198:~/
    ssh team@171.22.73.198
    cd ~/hadoop_enjoyer
    ./hw1_hdfs/scripts/deploy_hdfs.sh
    ./hw2_yarn/scripts/deploy_yarn.sh
    ./hw3_hive/scripts/deploy_hive.sh

Подробности в hw1_hdfs/README.md, hw2_yarn/README.md и hw3_hive/README.md.

## Перенос в другую среду

Правится только inventory.env: узлы и их IP, роли, доступ с edge на узлы, внешний адрес и карта публикации интерфейсов, версии Hadoop и Hive, ресурсы NodeManager, узел и порты Hive. Конфиги Hadoop и конфигурация nginx генерируются из инвентаря, скрипты править не нужно.

## Повторный запуск

Безопасен. Установленное не переустанавливается, NameNode не переформатируется, схема metastore не пересоздаётся, запущенные демоны не перезапускаются, блоки в /etc/hosts и hadoop-env.sh заменяются по маркерам BEGIN/END hadoop_hw. Загрузка в Hive идёт через INSERT OVERWRITE по партициям, повторный запуск не дублирует строки.

## Остановка

    ./hw3_hive/scripts/stop_hive.sh
    ./hw2_yarn/scripts/unpublish_ui.sh
    ./hw2_yarn/scripts/stop_yarn.sh
    ./hw1_hdfs/scripts/stop_hdfs.sh

Данные в /data/hadoop и метаданные Hive в PostgreSQL сохраняются.

Пароль базы metastore генерируется в .secrets/ при первом запуске и в репозиторий не попадает.
