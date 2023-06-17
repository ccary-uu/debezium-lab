
## Building the lab

This lab setup is built off examples from <https://github.com/debezium/debezium-examples>

Setup the environment by making sure httpie is installed and the debezium version is set in the terminal

```shell
# Terminal 1
brew install httpie
export DEBEZIUM_VERSION=2.2
docker-compose up -d --build
```

Then register an instance of the Debezium Postgres connector and an instance of the JDBC sink connector:

```shell
# Terminal 1
http PUT http://localhost:8083/connectors/inventory-connector/config < debezium-source.json

# Output
{
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.dbname": "sourcedb",
        "database.hostname": "source-db",
        "database.password": "postgrespw",
        "database.port": "5432",
        "database.user": "postgresusersource",
        "name": "inventory-connector",
        "snapshot.mode": "never",
        "tasks.max": "1",
        "topic.prefix": "dbserver1"
    },
    "name": "inventory-connector",
    "tasks": [],
    "type": "source"
}

http PUT http://localhost:8083/connectors/sink-connector/config < jdbc-sink.json

# Output
{
    "config": {
        "auto.create": "true",
        "auto.evolve": "true",
        "connection.url": "jdbc:postgresql://sink-db:5432/sinkdb?currentSchema=inventorysink&user=postgresusersink&password=postgrespw",
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "delete.enabled": "false",
        "insert.mode": "insert",
        "name": "sink-connector",
        "table.name.format": "customers",
        "tasks.max": "1",
        "topics": "dbserver1.inventory.customers",
        "transforms": "unwrap",
        "transforms.unwrap.add.fields": "op,table,lsn,source.ts_ms",
        "transforms.unwrap.add.headers": "db",
        "transforms.unwrap.delete.handling.mode": "rewrite",
        "transforms.unwrap.drop.tombstones": "true",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
    },
    "name": "sink-connector",
    "tasks": [],
    "type": "sink"
}
```

In separate terminals, start the pgcli for the source and the sink

```shell
# Terminal 2
docker run --tty --rm -i \
    --network debezium-lab_default \
    debezium/tooling:1.2 \
    bash -c 'pgcli postgresql://postgresusersource:postgrespw@source-db:5432/sourcedb'

sourcedb> select id, first_name, last_name, email from inventory.customers

# Output
+------+--------------+-------------+-----------------------+
| id   | first_name   | last_name   | email                 |
|------+--------------+-------------+-----------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com |
| 1002 | George       | Bailey      | gbailey@foobar.com    |
| 1003 | Edward       | Walker      | ed@walker.com         |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    |
+------+--------------+-------------+-----------------------+
```

```shell
# Terminal 3
docker run --tty --rm -i \
    --network debezium-lab_default \
    debezium/tooling:1.2 \
    bash -c 'pgcli postgresql://postgresusersink:postgrespw@sink-db:5432/sinkdb'

sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
relation "inventorysink.customers" does not exist
LINE 1: ...mail, __deleted, __lsn, __op, __source_ts_ms from inventorys...
```

## Initial Snapshots vs Never

Delete the source connector and change the snapshot mode to initial in the source connector config and recreate

```shell
# Terminal 1
http DELETE http://localhost:8083/connectors/inventory-connector
```

Update a record in the source db

```shell
# Terminal 2
sourcedb> update inventory.customers set first_name = 'Brian' where id = 1003;
sourcedb> select id, first_name, last_name, email from inventory.customers order by id

#Output
+------+--------------+-------------+-----------------------+
| id   | first_name   | last_name   | email                 |
|------+--------------+-------------+-----------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com |
| 1002 | George       | Bailey      | gbailey@foobar.com    |
| 1003 | Brian        | Walker      | ed@walker.com         |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    |
+------+--------------+-------------+-----------------------+
```

```shell
# Terminal 1
# Change snapshot.mode in debezium-source.json to initial
http PUT http://localhost:8083/connectors/inventory-connector/config < debezium-source.json

# Output
{
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.dbname": "sourcedb",
        "database.hostname": "source-db",
        "database.password": "postgrespw",
        "database.port": "5432",
        "database.user": "postgresusersource",
        "name": "inventory-connector",
        "snapshot.mode": "initial",
        "tasks.max": "1",
        "topic.prefix": "dbserver1"
    },
    "name": "inventory-connector",
    "tasks": [],
    "type": "source"
}
```

Examine the sink DB and notice that Edward is not present

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

Mock changes to the source db

```shell
# Terminal 2
sourcedb> update inventory.customers set first_name = 'Dana' where id = 1001;
sourcedb> delete from inventory.orders where purchaser = 1002;
sourcedb> delete from inventory.customers where id = 1002;
sourcedb> INSERT INTO inventory.customers (id, first_name, last_name, email) VALUES (1005, 'Tim', 'Burton', 'tim@burton.com');
sourcedb> select id, first_name, last_name, email from inventory.customers

# Output
+------+--------------+-------------+-----------------------+
| id   | first_name   | last_name   | email                 |
|------+--------------+-------------+-----------------------|
| 1003 | Brian        | Walker      | ed@walker.com         |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com |
| 1005 | Tim          | Burton      | tim@burton.com        |
+------+--------------+-------------+-----------------------+
```

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

Delete the source connector

```shell
# Terminal 1
http DELETE http://localhost:8083/connectors/inventory-connector
```

Create a few updates and validate that the replication slot still exists

```shell
# Terminal 2
sourcedb> update inventory.customers set first_name = 'Dana-1' where id = 1001;
sourcedb> update inventory.customers set first_name = 'Dana-2' where id = 1001;
sourcedb> update inventory.customers set first_name = 'Dana-3' where id = 1001;
sourcedb> select slot_name, slot_type, database, catalog_xmin, restart_lsn, confirmed_flush_lsn from pg_replication_slots

# Output                                                                       
+-------------+-------------+------------+----------------+---------------+-----------------------+
| slot_name   | slot_type   | database   | catalog_xmin   | restart_lsn   | confirmed_flush_lsn   |
|-------------+-------------+------------+----------------+---------------+-----------------------|
| debezium    | logical     | sourcedb   | 777            | 0/245BCD0     | 0/245F5B0             |
+-------------+-------------+------------+----------------+---------------+-----------------------+

```

Nothing should change in the sink as there is no source

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

Recreate the source connector and verify that the updates are present

```shell
# Terminal 1
http PUT http://localhost:8083/connectors/inventory-connector/config < debezium-source.json

# Output
{
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.dbname": "sourcedb",
        "database.hostname": "source-db",
        "database.password": "postgrespw",
        "database.port": "5432",
        "database.user": "postgresusersource",
        "name": "inventory-connector",
        "snapshot.mode": "initial",
        "tasks.max": "1",
        "topic.prefix": "dbserver1"
    },
    "name": "inventory-connector",
    "tasks": [],
    "type": "source"
}
```

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output                                                       
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
| 1001 | Dana-1       | Thomas      | sally.thomas@acme.com | false       | 38140024 | u      | 1686500530106    |
| 1001 | Dana-2       | Thomas      | sally.thomas@acme.com | false       | 38140312 | u      | 1686500533780    |
| 1001 | Dana-3       | Thomas      | sally.thomas@acme.com | false       | 38140544 | u      | 1686500537549    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

Once more delete the source connector and create some updates

```shell
# Terminal 1
http DELETE http://localhost:8083/connectors/inventory-connector
```

```shell
# Terminal 2
sourcedb> update inventory.customers set first_name = 'Dana-4' where id = 1001;
sourcedb> update inventory.customers set first_name = 'Dana-5' where id = 1001;
sourcedb> update inventory.customers set first_name = 'Dana-6' where id = 1001;
sourcedb> delete from inventory.orders where purchaser = 1001;
sourcedb> delete from inventory.customers where id = 1001;
sourcedb> INSERT INTO inventory.customers (id, first_name, last_name, email) VALUES (1006, 'Jack', 'Bauer', 'jack@bauer.com');
sourcedb> update inventory.customers set first_name = 'Jack-2' where id = 1006;
sourcedb> select id, first_name, last_name, email from inventory.customers 

# Output
+------+--------------+-------------+--------------------+
| id   | first_name   | last_name   | email              |
|------+--------------+-------------+--------------------|
| 1003 | Brian        | Walker      | ed@walker.com      |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org |
| 1005 | Tim          | Burton      | tim@burton.com     |
| 1006 | Jack-2       | Bauer       | jack@bauer.com     |
+------+--------------+-------------+--------------------+
```

Create a source with the same config but a different name

```shell
# Terminal 1
http PUT http://localhost:8083/connectors/inventory-connector-2/config < debezium-source.json

# Output
{
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.dbname": "sourcedb",
        "database.hostname": "source-db",
        "database.password": "postgrespw",
        "database.port": "5432",
        "database.user": "postgresusersource",
        "name": "inventory-connector-2",
        "snapshot.mode": "initial",
        "tasks.max": "1",
        "topic.prefix": "dbserver1"
    },
    "name": "inventory-connector-2",
    "tasks": [],
    "type": "source"
}
```

View the results in the sink and notice the missing updates for Dana-4 and Dana-5

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
| 1001 | Dana-1       | Thomas      | sally.thomas@acme.com | false       | 38140024 | u      | 1686500530106    |
| 1001 | Dana-2       | Thomas      | sally.thomas@acme.com | false       | 38140312 | u      | 1686500533780    |
| 1001 | Dana-3       | Thomas      | sally.thomas@acme.com | false       | 38140544 | u      | 1686500537549    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38179664 | r      | 1686500777247    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38179664 | r      | 1686500777247    |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        | false       | 38179664 | r      | 1686500777247    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

Delete the connector and create updates again

```shell
# Terminal 1
http DELETE http://localhost:8083/connectors/inventory-connector-2
```

```shell
# Terminal 2
sourcedb> update inventory.customers set first_name = 'Anne-1' where id = 1004;
sourcedb> update inventory.customers set first_name = 'Anne-2' where id = 1004;
sourcedb> update inventory.customers set first_name = 'Anne-3' where id = 1004;
sourcedb> INSERT INTO inventory.customers (id, first_name, last_name, email) VALUES (1007, 'Jonny', 'Knoxville', 'jonny@knoxville.com');
sourcedb> select id, first_name, last_name, email from inventory.customers

#Output
+------+--------------+-------------+----------------------+
| id   | first_name   | last_name   | email                |
|------+--------------+-------------+----------------------|
| 1003 | Brian        | Walker      | ed@walker.com        |
| 1005 | Tim          | Burton      | tim@burton.com       |
| 1006 | Jack-2       | Bauer       | jack@bauer.com       |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org   |
| 1007 | Jonny        | Knoxville   | jonny@knoxville.com  |
+------+--------------+-------------+----------------------+
```

Change the configs for the source connector to have "never" for the snapshot mode and create a new source connector with a new name

```shell
# Terminal 1
http PUT http://localhost:8083/connectors/inventory-connector-3/config < debezium-source.json

# Output
{
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.dbname": "sourcedb",
        "database.hostname": "source-db",
        "database.password": "postgrespw",
        "database.port": "5432",
        "database.user": "postgresusersource",
        "name": "inventory-connector-3",
        "snapshot.mode": "never",
        "tasks.max": "1",
        "topic.prefix": "dbserver1"
    },
    "name": "inventory-connector-3",
    "tasks": [],
    "type": "source"
}
```

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
| 1001 | Dana-1       | Thomas      | sally.thomas@acme.com | false       | 38140024 | u      | 1686500530106    |
| 1001 | Dana-2       | Thomas      | sally.thomas@acme.com | false       | 38140312 | u      | 1686500533780    |
| 1001 | Dana-3       | Thomas      | sally.thomas@acme.com | false       | 38140544 | u      | 1686500537549    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38179664 | r      | 1686500777247    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38179664 | r      | 1686500777247    |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne-1       | Kretchmar   | annek@noanswer.org    | false       | 38181440 | u      | 1686500982755    |
| 1004 | Anne-2       | Kretchmar   | annek@noanswer.org    | false       | 38181672 | u      | 1686500986795    |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org    | false       | 38181960 | u      | 1686500990077    |
| 1007 | Jonny        | Knoxville   | jonny@knoxville.com   | false       | 38182480 | c      | 1686501025056    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

## Commits

When we have multiple updates within a commit the __source_ts_ms will be same for all of the commits

```shell
# Terminal 2
sourcedb> BEGIN;
sourcedb> update inventory.customers set first_name = 'Jonny-1' where id = 1007;
sourcedb> update inventory.customers set last_name = 'Knoxville-1' where id = 1007;
sourcedb> update inventory.customers set first_name = 'jonny@knoxville.com-1' where id = 1007;
sourcedb> COMMIT;
sourcedb> select id, first_name, last_name, email from inventory.customers

# Output
+------+--------------+-------------+-----------------------+
| id   | first_name   | last_name   | email                 |
|------+--------------+-------------+-----------------------|
| 1003 | Brian        | Walker      | ed@walker.com         |
| 1005 | Tim          | Burton      | tim@burton.com        |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org    |
| 1007 | Jonny-1      | Knoxville-1 | jonny@knoxville.com-1 |
+------+--------------+-------------+-----------------------+
```

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
| 1001 | Dana-1       | Thomas      | sally.thomas@acme.com | false       | 38140024 | u      | 1686500530106    |
| 1001 | Dana-2       | Thomas      | sally.thomas@acme.com | false       | 38140312 | u      | 1686500533780    |
| 1001 | Dana-3       | Thomas      | sally.thomas@acme.com | false       | 38140544 | u      | 1686500537549    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38179664 | r      | 1686500777247    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38179664 | r      | 1686500777247    |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne-1       | Kretchmar   | annek@noanswer.org    | false       | 38181440 | u      | 1686500982755    |
| 1004 | Anne-2       | Kretchmar   | annek@noanswer.org    | false       | 38181672 | u      | 1686500986795    |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org    | false       | 38181960 | u      | 1686500990077    |
| 1007 | Jonny        | Knoxville   | jonny@knoxville.com   | false       | 38182480 | c      | 1686501025056    |
| 1007 | Jonny-1      | Knoxville   | jonny@knoxville.com   | false       | 38183420 | u      | 1686502055052    |
| 1007 | Jonny-1      | Knoxville-1 | jonny@knoxville.com   | false       | 38183640 | u      | 1686502055052    |
| 1007 | Jonny-1      | Knoxville-1 | jonny@knoxville.com-1 | false       | 38183880 | u      | 1686502055052    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+


sinkdb> select distinct on (id, __source_ts_ms) id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by id, __source_ts_ms, __source_ts_ms DESC)

```

## Adhoc Snapshots

Lastly we will create an "Adhoc" snapshot

```shell
# Terminal 2
sourcedb> insert into inventory.debezium_signals (type,data) select 'execute-snapshot','  {"data-collections": ["inventory.customers"]}'
```

```shell
# Terminal 3
sinkdb> select id, first_name, last_name, email, __deleted, __lsn, __op, __source_ts_ms from inventorysink.customers order by __source_ts_ms asc

# Output
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
| id   | first_name   | last_name   | email                 | __deleted   | __lsn    | __op   | __source_ts_ms   |
|------+--------------+-------------+-----------------------+-------------+----------+--------+------------------|
| 1001 | Sally        | Thomas      | sally.thomas@acme.com | false       | 38124712 | r      | 1686500174119    |
| 1002 | George       | Bailey      | gbailey@foobar.com    | false       | 38124712 | r      | 1686500174119    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38124712 | r      | 1686500174119    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38124712 | r      | 1686500174119    |
| 1001 | Dana         | Thomas      | sally.thomas@acme.com | false       | 38125760 | u      | 1686500443536    |
| 1002 |              |             |                       | true        | 38126440 | d      | 1686500453631    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38139312 | c      | 1686500458280    |
| 1001 | Dana-1       | Thomas      | sally.thomas@acme.com | false       | 38140024 | u      | 1686500530106    |
| 1001 | Dana-2       | Thomas      | sally.thomas@acme.com | false       | 38140312 | u      | 1686500533780    |
| 1001 | Dana-3       | Thomas      | sally.thomas@acme.com | false       | 38140544 | u      | 1686500537549    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne         | Kretchmar   | annek@noanswer.org    | false       | 38179664 | r      | 1686500777247    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | 38179664 | r      | 1686500777247    |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        | false       | 38179664 | r      | 1686500777247    |
| 1004 | Anne-1       | Kretchmar   | annek@noanswer.org    | false       | 38181440 | u      | 1686500982755    |
| 1004 | Anne-2       | Kretchmar   | annek@noanswer.org    | false       | 38181672 | u      | 1686500986795    |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org    | false       | 38181960 | u      | 1686500990077    |
| 1007 | Jonny        | Knoxville   | jonny@knoxville.com   | false       | 38182480 | c      | 1686501025056    |
| 1007 | Jonny-1      | Knoxville   | jonny@knoxville.com   | false       | 38183420 | u      | 1686502055052    |
| 1007 | Jonny-2      | Knoxville   | jonny@knoxville.com   | false       | 38183640 | u      | 1686502055052    |
| 1007 | Jonny-3      | Knoxville   | jonny@knoxville.com   | false       | 38183880 | u      | 1686502055052    |
| 1003 | Brian        | Walker      | ed@walker.com         | false       | <null>   | r      | 1686594314204    |
| 1004 | Anne-3       | Kretchmar   | annek@noanswer.org    | false       | <null>   | r      | 1686594314205    |
| 1005 | Tim          | Burton      | tim@burton.com        | false       | <null>   | r      | 1686594314205    |
| 1006 | Jack-2       | Bauer       | jack@bauer.com        | false       | <null>   | r      | 1686594314205    |
| 1007 | Jonny-3      | Knoxville   | jonny@knoxville.com   | false       | <null>   | r      | 1686594314205    |
+------+--------------+-------------+-----------------------+-------------+----------+--------+------------------+
```

## Clean Up

```shell
# Terminal 2
sourcedb> exit
```

```shell
# Terminal 3
sinkdb> exit
```

```shell
# Terminal 1
docker-compose down
```
