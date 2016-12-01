#!/bin/bash
set -e

echo "-- Building MongoDB 3.0 image"
docker build -t mongo-3.0 ../3.0/
docker network create mongo_net
DIR_VOLUME=$(pwd)/vol30
mkdir -p ${DIR_VOLUME}/backup

echo
echo "-- Testing backup/checking on MongoDB 3.0"
docker run --name base_1 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc; sleep 20
docker exec -it base_1 mongo --eval 'db.createCollection("db_test");db.db_test.insert({name: "Tom"})'; sleep 5
docker exec -it base_1 mongo admin --eval 'db.createUser({user: "backuper", pwd: "pass", roles: [ "backup", "restore" ]})'; sleep 5
echo
echo "-- Backup"
docker run -it --rm --net mongo_net -e 'MONGO_MODE=backup' -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0 --host base_1 -u backuper -p pass; sleep 10
echo
echo "-- Clear"
docker rm -f -v base_1; sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0  | tail -n 1 | grep -c 'Success'; sleep 10
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db'  -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0  2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10

echo
echo "-- Restore backup on MongoDB 3.0"
docker run --name base_1 -d -e 'MONGO_RESTORE=default' -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc; sleep 25
docker exec -it base_1 mongo --eval 'db.db_test.find({name: "Tom"}).forEach(printjson)' | grep -wc 'Tom'; sleep 5
echo
echo
echo "-- Clear"
docker rm -f -v base_1; sleep 5
rm -rf ${DIR_VOLUME}

echo
echo "-- Testing Replica Set Cluster on MongoDB 3.0"
docker run --name node_1 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_2 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
docker run --name node_3 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --noprealloc --replSet "rs_test"; sleep 20
echo
echo "-- Configure replica set"
docker exec -i node_1 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_1 mongo <<EOF
rs.add("node_2:27017")
rs.add("node_3:27017")
EOF
sleep 10
docker exec -i node_1 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "node_1:27017"
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
docker exec -it node_1 mongo --eval 'db.db_test.find().forEach(printjson)' | grep -wc 'Bob'; sleep 5

echo
echo "-- Backup replica"
mkdir -p ${DIR_VOLUME}/backup
docker run -it --rm --net mongo_net -e 'MONGO_MODE=backup' -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0 -h node_2 --oplog; sleep 10
echo "-- Clear"
docker rm -f -v node_1 node_2 node_3; sleep 5
echo
echo "-- Check"
docker run -it --rm -e 'MONGO_CHECK=default' -e 'COLLECTION_NAME=db_test'  -v ${DIR_VOLUME}/backup:/tmp/backup mongo-3.0 | tail -n 1 | grep -c 'Success'; sleep 10
rm -rf ${DIR_VOLUME}


echo
echo "-- Testing Sharded Cluster on MongoDB 3.0"
echo
echo "-- Create shards"
docker run --name node_1 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc; sleep 20
docker run --name node_2 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc; sleep 20

echo "-- Create a Config Server"
docker run --name cnf_1 -d --net mongo_net mongo-3.0 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d --net mongo_net -e 'MONGO_MODE=mongos' mongo-3.0 --configdb cnf_1:27017; sleep 20
echo
echo "-- Configure Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("node_1:27017")
sh.addShard("node_2:27017")
EOF

sleep 20

(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "node_2"


echo
echo '-- Clear'
docker rm -f -v node_1 node_2 cnf_1 mongos; sleep 5


echo
echo "-- Testing Sharded Cluster with Replica set on MongoDB 3.0"
echo
echo "-- Create replica set #1"
docker run --name node_11 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_12 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
docker run --name node_13 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs1"; sleep 20
echo
echo "-- Configure replica set #1"
docker exec -i node_11 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_11 mongo <<EOF
rs.add("node_12:27017")
rs.add("node_13:27017")
EOF
sleep 10
docker exec -i node_11 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "node_11:27017"
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
docker run --name node_21 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_22 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
docker run --name node_23 -d --net mongo_net mongo-3.0 --storageEngine wiredTiger --smallfiles --nojournal --noprealloc --replSet "rs2"; sleep 20
echo
echo "-- Configure replica set #2"
docker exec -i node_21 mongo <<EOF
rs.initiate()
EOF
sleep 5
docker exec -i node_21 mongo <<EOF
rs.add("node_22:27017")
rs.add("node_23:27017")
EOF
sleep 10
docker exec -i node_21 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "node_21:27017"
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
docker run --name cnf_1 -d --net mongo_net mongo-3.0 --port 27017 --noprealloc --smallfiles --nojournal --configsvr; sleep 20

echo
echo "-- Create a Router (mongos)"
docker run --name mongos -d --net mongo_net -e 'MONGO_MODE=mongos' mongo-3.0 --configdb cnf_1:27017; sleep 20
echo
echo "-- Configure Router (mongos)"
docker exec -i mongos mongo <<EOF
sh.addShard("rs1/node_11:27017")
sh.addShard("rs2/node_21:27017")
EOF

sleep 20
(docker exec -i mongos mongo  <<EOF
sh.status()
EOF
) | grep -wc "node_22:27017"


echo
echo "-- Clear"
docker rm -f -v node_11 node_12 node_13 node_21 node_22 node_23 mongos cnf_1; sleep 5
docker network rm mongo_net
docker rmi mongo-3.0; sleep 5
rm -fr ${DIR_VOLUME}

echo
echo "Done"