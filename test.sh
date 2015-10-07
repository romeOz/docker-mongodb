#!/bin/bash
set -e


echo "-- Building MongoDB 2.6 image"
docker build -t mongo-2.6 2.6/

echo
echo "-- Testing backup/checking on MongoDB 2.6"
docker run --name base_1 -d mongo-2.6 --smallfiles --noprealloc; sleep 20
docker exec -it base_1 mongo --eval 'db.createCollection("db_test");db.db_test.insert({name: "Tom"})'; sleep 5
docker exec -it base_1 mongo admin --eval 'db.createUser({user: "backuper", pwd: "pass", roles: [ "backup", "restore" ]})'; sleep 5
echo
echo "-- Backup"
docker run -it --rm --link base_1:base_1 -e 'MONGO_MODE=backup' -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 --host base_1 -u backuper -p pass; sleep 10
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 | tail -n 1 | grep -c 'Success'; sleep 10
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db'  -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10

echo
echo "-- Restore backup on MongoDB 2.6"
docker run --name base_1 -d -e 'MONGO_RESTORE=default' -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 --smallfiles --noprealloc; sleep 20
docker exec -it base_1 mongo --eval 'db.db_test.find({name: "Tom"}).forEach(printjson)' | grep -wc 'Tom'; sleep 5
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol26*

echo
echo "-- Testing Replica Set Cluster on MongoDB 2.6"
docker run --name node_1 -d mongo-2.6 --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_2 -d mongo-2.6 --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_3 -d mongo-2.6 --smallfiles --noprealloc --replSet "rs_test"; sleep 20
echo
echo "-- Configure replica set"
id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)
id_3=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_3)
docker exec -i node_1 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_1 mongo <<EOF
rs.add("${id_2}:27017")
rs.add("${id_3}:27017")
EOF
sleep 10
docker exec -i node_1 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_1}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_1 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_2 mongo <<EOF
rs.status().ok
EOF
sleep 5
echo
echo "-- Create db and insert record"
docker exec -it node_1 mongo --eval 'db.createCollection("db_test");db.db_test.insert({name: "Bob"})'; sleep 5
docker exec -it node_1 mongo --eval 'db.db_test.find().forEach(printjson)' | grep -wc 'Bob'

echo
echo "-- Backup replica"
docker run -it --rm --link node_2:node_2 -e 'MONGO_MODE=backup' -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 -h node_2 node_2 --oplog; sleep 10
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v $(pwd)/vol26/backup:/tmp/backup mongo-2.6 | tail -n 1 | grep -c 'Success'; sleep 10


echo
echo "-- Testing Sharded Cluster on MongoDB 2.6"
echo
echo "-- Create shards"
docker run --name node_1 -d mongo-2.6 --smallfiles --nojournal --noprealloc; sleep 20
docker run --name node_2 -d mongo-2.6 --smallfiles --nojournal --noprealloc; sleep 20

id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)

echo "-- Create a Config Server"
docker run --name cnf_1 -d mongo-2.6 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

id=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cnf_1)
echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d -e 'MONGO_MODE=mongos' mongo-2.6 --configdb ${id}:27017; sleep 20
echo
echo "-- Configure a Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("${id_1}:27017")
sh.addShard("${id_2}:27017")
EOF

sleep 20

(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "${id_2}"


echo
echo '-- Clear'
docker rm -f -v $(sudo docker ps -aq); sleep 5


echo
echo "-- Testing Sharded Cluster with Replica set on MongoDB 2.6"
echo
echo "-- Create replica set #1"
docker run --name node_11 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_12 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_13 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
echo
echo "-- Configure replica set #1"
id_11=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_11)
id_12=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_12)
id_13=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_13)
docker exec -i node_11 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_11 mongo <<EOF
rs.add("${id_12}:27017")
rs.add("${id_13}:27017")
EOF
sleep 10
docker exec -i node_11 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_11}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_11 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_12 mongo <<EOF
rs.status().ok
EOF
sleep 5

echo
echo "-- Create replica set #2"
docker run --name node_21 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_22 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_23 -d mongo-2.6 --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
echo
echo "-- Configure replica set #2"
id_21=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_21)
id_22=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_22)
id_23=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_23)
docker exec -i node_21 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_21 mongo <<EOF
rs.add("${id_22}:27017")
rs.add("${id_23}:27017")
EOF
sleep 10
docker exec -i node_21 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_21}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_21 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_22 mongo <<EOF
rs.status().ok
EOF
sleep 5
echo
echo "-- Create a Config Server"
docker run --name cnf_1 -d mongo-2.6 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

id=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cnf_1)
echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d -e 'MONGO_MODE=mongos' mongo-2.6 --configdb ${id}:27017; sleep 20
echo
echo "-- Configure Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("rs1/${id_11}:27017")
sh.addShard("rs2/${id_21}:27017")
EOF

sleep 20
(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "${id_22}:27017"


echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi mongo-2.6; sleep 5
rm -fr vol26*



echo
echo
echo "-- Building MongoDB 3.0 image"
docker build -t mongo-3.0 3.0/

echo
echo "-- Testing backup/checking on MongoDB 3.0"
docker run --name base_1 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc; sleep 20
docker exec -it base_1 mongo --eval 'db.createCollection("db_test");db.db_test.insert({name: "Tom"})'; sleep 5
docker exec -it base_1 mongo admin --eval 'db.createUser({user: "backuper", pwd: "pass", roles: [ "backup", "restore" ]})'; sleep 5
echo
echo "-- Backup"
docker run -it --rm --link base_1:base_1 -e 'MONGO_MODE=backup' -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0 --host base_1 -u backuper -p pass; sleep 10
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0  | tail -n 1 | grep -c 'Success'; sleep 10
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db'  -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0  2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10

echo
echo "-- Restore backup on MongoDB 3.0"
docker run --name base_1 -d -e 'MONGO_RESTORE=default' -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc; sleep 25
docker exec -it base_1 mongo --eval 'db.db_test.find({name: "Tom"}).forEach(printjson)' | grep -wc 'Tom'; sleep 5
echo
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol30*

echo
echo "-- Testing Replica Set Cluster on MongoDB 3.0"
docker run --name node_1 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_2 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_3 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
echo
echo "-- Configure replica set"
id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)
id_3=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_3)
docker exec -i node_1 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_1 mongo <<EOF
rs.add("${id_2}:27017")
rs.add("${id_3}:27017")
EOF
sleep 10
docker exec -i node_1 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_1}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_1 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_2 mongo <<EOF
rs.status().ok
EOF
sleep 5
echo
echo "-- Create db and insert record"
docker exec -it node_1 mongo --eval 'db.createCollection("db_test");db.db_test.insert({name: "Bob"})'; sleep 5
docker exec -it node_1 mongo --eval 'db.db_test.find().forEach(printjson)' | grep -wc 'Bob'

echo
echo "-- Backup replica"
docker run -it --rm --link node_2:node_2 -e 'MONGO_MODE=backup' -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0 -h node_2 --oplog; sleep 10
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v $(pwd)/vol30/backup:/tmp/backup mongo-3.0 | tail -n 1 | grep -c 'Success'; sleep 10

echo
echo "-- Testing Sharded Cluster on MongoDB 3.0"
echo
echo "-- Create shards"
docker run --name node_1 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc; sleep 20
docker run --name node_2 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc; sleep 20

id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)

echo "-- Create a Config Server"
docker run --name cnf_1 -d mongo-3.0 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

id=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cnf_1)
echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d -e 'MONGO_MODE=mongos' mongo-3.0 --configdb ${id}:27017; sleep 20
echo
echo "-- Configure Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("${id_1}:27017")
sh.addShard("${id_2}:27017")
EOF

sleep 20

(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "${id_2}"


echo
echo '-- Clear'
docker rm -f -v $(sudo docker ps -aq); sleep 5


echo
echo "-- Testing Sharded Cluster with Replica set on MongoDB 3.0"
echo
echo "-- Create replica set #1"
docker run --name node_11 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_12 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_13 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
echo
echo "-- Configure replica set #1"
id_11=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_11)
id_12=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_12)
id_13=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_13)
docker exec -i node_11 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_11 mongo <<EOF
rs.add("${id_12}:27017")
rs.add("${id_13}:27017")
EOF
sleep 10
docker exec -i node_11 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_11}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_11 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_12 mongo <<EOF
rs.status().ok
EOF
sleep 5

echo
echo "-- Create replica set #2"
docker run --name node_21 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_22 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_23 -d mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
echo
echo "-- Configure replica set #2"
id_21=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_21)
id_22=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_22)
id_23=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_23)
docker exec -i node_21 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_21 mongo <<EOF
rs.add("${id_22}:27017")
rs.add("${id_23}:27017")
EOF
sleep 10
docker exec -i node_21 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_21}:27017"
rs.reconfig(cfg)
EOF
sleep 20
docker exec -i node_21 mongo <<EOF
rs.status().ok
EOF
docker exec -i node_22 mongo <<EOF
rs.status().ok
EOF
sleep 5
echo
echo "-- Create a Config Server"
docker run --name cnf_1 -d mongo-3.0 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

id=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cnf_1)
echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d -e 'MONGO_MODE=mongos' mongo-3.0 --configdb ${id}:27017; sleep 20
echo
echo "-- Configure Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("rs1/${id_11}:27017")
sh.addShard("rs2/${id_21}:27017")
EOF

sleep 20
(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "${id_22}:27017"


echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi mongo-3.0; sleep 5
rm -fr vol30*

echo ""
echo "-- Done"