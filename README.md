# hadoop enjoyer

Команда team-09: Шарифуллин Карим, Керопьян Артур, Латышев Иван, Киселева Анна.

ДЗ отправляется от лидера команды: Шарифуллин Карим, @puker0n.

hw1_hdfs - развёртывание HDFS: NameNode, Secondary NameNode, 3 DataNode.
hw2_yarn - развёртывание YARN и публикация веб-интерфейсов демонов наружу.

inventory.env - параметры стенда: узлы, роли, версии, пути, ресурсы.
common/lib.sh - общие функции скриптов.

## Стенд

4 ВМ Ubuntu 24.04, 2 vCPU, 3 ГБ RAM. Снаружи доступна только edge-нода.

    team-09-en  10.9.0.10  edge: клиент, отсюда запускаются скрипты, nginx
    team-09-nn  10.9.0.11  NameNode, DataNode, ResourceManager, NodeManager
    team-09-00  10.9.0.12  Secondary NameNode, DataNode, NodeManager
    team-09-01  10.9.0.13  DataNode, NodeManager, JobHistory Server

Hadoop 3.4.2, OpenJDK 11.

## Запуск

Скрипты запускаются с edge-ноды. Ей нужен ssh-доступ по ключу ко всем узлам и sudo без пароля.

    scp -r hadoop_enjoyer team@171.22.73.198:~/
    ssh team@171.22.73.198
    cd ~/hadoop_enjoyer
    ./hw1_hdfs/scripts/deploy_hdfs.sh
    ./hw2_yarn/scripts/deploy_yarn.sh

Подробности в hw1_hdfs/README.md и hw2_yarn/README.md.

## Перенос в другую среду

Правится только inventory.env: узлы и их IP, роли, доступ с edge на узлы, внешний адрес и карта публикации интерфейсов, версия Hadoop, ресурсы NodeManager. Конфиги Hadoop и конфигурация nginx генерируются из инвентаря, скрипты править не нужно.

## Повторный запуск

Безопасен. Установленное не переустанавливается, NameNode не переформатируется, запущенные демоны не перезапускаются, блоки в /etc/hosts и hadoop-env.sh заменяются по маркерам BEGIN/END hadoop_hw.

## Остановка

    ./hw2_yarn/scripts/unpublish_ui.sh
    ./hw2_yarn/scripts/stop_yarn.sh
    ./hw1_hdfs/scripts/stop_hdfs.sh

Данные в /data/hadoop сохраняются.
