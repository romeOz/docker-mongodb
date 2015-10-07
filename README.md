Table of Contents
-------------------

 * [Installation](#installation)
 * [Quick Start](#quick-start)
 * [Command-line arguments](#command-line-arguments)
 * [Persistence](#persistence) 
 * [Backuping](#backuping)
 * [Checking a backup](#checking-backup)
 * [Restoring from backup](#restoring-from-backup)
 * [Replica Set Cluster](#replica-set-cluster)
 * [Sharded Cluster](#sharded-cluster)  
 * [Environment variables](#environment-variables)
 * [Logging](#logging) 
 * [Out of the box](#out-of-the-box)
 
Installation
-------------------

 * [Install Docker](https://docs.docker.com/installation/) or [askubuntu](http://askubuntu.com/a/473720)
 * Pull the latest version of the image.
 
```bash
docker pull romeoz/docker-mongodb
```

Alternately you can build the image yourself.

```bash
git clone https://github.com/romeoz/docker-mongodb.git
cd docker-mongodb
docker build -t="$USER/mongodb" .
```

Quick Start
-------------------

Run the mongodb image:

```bash
docker run --name mongodb -d romeoz/docker-mongodb
```

The simplest way to login to the app container is to use the `docker exec` command to attach a new process to the running container.

```bash
docker exec -it mongodb mongo
```

Command-line arguments
-------------------

You can customize the launch command of MongoDB server by specifying arguments to `mongod` on the docker run command. For example the following command for use "WiredTiger" storage engine:

```bash
docker run --name mongodb -d \  
  romeoz/docker-mongodb --storageEngine wiredTiger
```

Persistence
-------------------

For data persistence a volume should be mounted at `/var/lib/mongodb`.

SELinux users are also required to change the security context of the mount point so that it plays nicely with selinux.

```bash
mkdir -p /to/path/data
sudo chcon -Rt svirt_sandbox_file_t /to/path/data
```

The updated run command looks like this.

```bash
docker run --name mongodb -d \
  -v /host/to/path/data:/var/lib/mongodb \
  romeoz/docker-mongodb
```

This will make sure that the data stored in the database is not lost when the image is stopped and started again.

Backuping
-------------------

The backup is made over [`mongodump`](http://docs.mongodb.org/manual/reference/program/mongodump/).

Create a temporary container for backup:

```bash
docker run -it --rm \
  --link mongodb:mongodb \
  -e 'MONGO_MODE=backup' -e 'MONGO_HOST=mongodb' \
  -v host/to/path/backup:/tmp/backup \
  romeoz/docker-mongodb
```

Archive will be available in the `/host/to/path/backup`.

> Algorithm: one backup per week (total 4), one backup per month (total 12) and the last backup. Example: `backup.last.tar.tar.gz`, `backup.1.tar.tar.gz` and `/backup.dec.tar.tar.gz`.

You can disable the rotation by using env `SPHINX_ROTATE_BACKUP=false`.

Also, you can set command-line arguments for `mongodump`:

```bash
docker run -it --rm \
  --link mongodb:mongodb \
  -e 'MONGO_MODE=backup' \
  -v host/to/path/backup:/tmp/backup \
  romeoz/docker-mongodb --host mongodb -u backuper -p pass
```

Checking backup
-------------------

As the check-parameter is used a collection name `COLLECTION_NAME`. If necessary, you can specify a database name `DB_NAME`.

```bash
docker run -it --rm \
    -e 'MONGO_CHECK=default' \
    -e 'COLLECTION_NAME=foo' \
    -v /host/to/path/backup:/tmp/backup \
    romeoz/docker-mongodb
```

Default used the `/tmp/backup/backup.last.tar.gz`.

Restoring from backup
-------------------

The backup is made over [`mongoresore`](http://docs.mongodb.org/manual/reference/program/mongorestore/).

```bash
docker run --name mongodb -d \
  -e 'MONGO_RESTORE=default' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mongodb
```

You can set command-line arguments for `mongod`:

```bash
docker run --name mongodb -d \
  -e 'MONGO_RESTORE=default' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mongodb --storageEngine wiredTiger
```

Replica Set Cluster
-------------------------

Create replica set:

```bash
docker run --name node_1 -d romeoz/docker-mongodb --replSet "rs"
docker run --name node_2 -d romeoz/docker-mongodb --replSet "rs"
docker run --name node_3 -d romeoz/docker-mongodb --replSet "rs"  
```

Configure replica set:

```bash
id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)
id_3=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_3)

docker exec -i node_1 mongo <<EOF
rs.initiate()
rs.add("${id_2}:27017")
rs.add("${id_3}:27017")
EOF
```
Docker will assign an auto-generated hostname for containers and by default MongoDB will use this hostname while initializing the replica set. 
As we need to access the nodes of the replica set from outside the container we will use IP adresses instead.

Use these MongoDB shell commands to change the hostname to the IP address:

```bash
docker exec -i node_1 mongo <<EOF
cfg = rs.conf()
cfg.members[0].host = "${id_1}:27017"
rs.reconfig(cfg)
rs.status()
EOF
```

More information you can [see here](http://docs.mongodb.org/manual/core/replication-introduction/).

Sharded Cluster
---------------------

Create a shards:

```bash
docker run --name node_1 -d romeoz/docker-mongodb
docker run --name node_2 -d romeoz/docker-mongodb
```

Configure a Sharded Cluster:

```bash
id_1=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_1)
id_2=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' node_2)

# Create a Config Server
docker run --name cnf -d \
  romeoz/docker-mongodb \
  --port 27017 --configsvr
  
id_cnf=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' cnf)
```

Create a Router (`mongos`):

```bash
docker run --name mongos -d \
  -e 'MONGO_MODE=mongos' \
  romeoz/docker-mongodb \
  --configdb ${id_cnf}:27017
```

Configure a Router (`mongos`):

```bash
docker exec -i mongos mongo <<EOF
sh.addShard("${id_1}:27017")
sh.addShard("${id_2}:27017")
sh.status()
EOF
```

More information you can [see here](http://docs.mongodb.org/manual/core/sharding-introduction/).

Environment variables
---------------------

`MONGO_BACKUP_DIR`: Set a specific backup directory (default "/tmp/backup").

`MONGO_BACKUP_FILENAME`: Set a specific filename backup (default "backup.last.tar.gz").

`MONGO_MODE`: Set a specific mode. Takes on the values `backup` or `mongos`.

`MONGO_RESTORE`: Defines name of backup-file to initialize the database. Note that the scripts must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.tar.gz`

`RESTORE_OPTS`: Defines options of `mongorestore`. 
 
`MONGO_CHECK`: Defines name of backup-file to initialize the database. Note that the dump must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.tar.gz`

`MONGO_ROTATE_BACKUP`: Determines whether to use the rotation of backups (default "true").
 
`DB_NAME`: Set a specific name of database for checking (default "test")

`COLLECTION_NAME`: Set a specific name of collection for checking

Logging
-------------------

All the logs are forwarded to stdout and sterr. You have use the command `docker logs`.

```bash
docker logs mongodb
```

####Split the logs

You can then simply split the stdout & stderr of the container by piping the separate streams and send them to files:

```bash
docker logs mongodb > stdout.log 2>stderr.log
cat stdout.log
cat stderr.log
```

or split stdout and error to host stdout:

```bash
docker logs mongodb > -
docker logs mongodb 2> -
```

####Rotate logs

Create the file `/etc/logrotate.d/docker-containers` with the following text inside:

```
/var/lib/docker/containers/*/*.log {
    rotate 31
    daily
    nocompress
    missingok
    notifempty
    copytruncate
}
```
> Optionally, you can replace `nocompress` to `compress` and change the number of days.

Out of the box
-------------------
 * Ubuntu 14.04.3 (LTS)
 * MongoDB 2.6/3.0

License
-------------------

MongoDB container image is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT)