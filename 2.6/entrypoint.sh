#!/bin/bash
set -e

MONGO_MODE=${MONGO_MODE:-}
MONGO_BACKUP_DIR=${MONGO_BACKUP_DIR:-"/tmp/backup"}
MONGO_BACKUP_FILENAME=${MONGO_BACKUP_FILENAME:-"backup.last.tar.gz"}
MONGO_ROTATE_BACKUP=${MONGO_ROTATE_BACKUP:-true}
RESTORE_OPTS=${RESTORE_OPTS:-}
DB_NAME=${DB_NAME:-test}


create_data_dir()
{
  mkdir -p ${MONGO_DATA_DIR}
  chmod -R 0755 ${MONGO_DATA_DIR}
  chown -R ${MONGO_USER}:${MONGO_USER} ${MONGO_DATA_DIR}
}

create_log_dir()
{
  mkdir -p ${MONGO_LOG_DIR}
  chmod -R 0755 ${MONGO_LOG_DIR}
  chown -R ${MONGO_USER}:${MONGO_USER} ${MONGO_LOG_DIR}
}

start_server()
{
    sudo -Hu ${MONGO_USER} mongod --config ${MONGO_CONFIG} --smallfiles --noprealloc &
    timeout=30
    echo "Waiting for confirmation of MongoDB service startup"
    while ! mongo admin --eval "help" >/dev/null 2>&1
    do
      timeout=$(($timeout - 1))
      if [ $timeout -eq 0 ]; then
        echo -e "\nCould not connect to database server. Aborting..."
        exit 1
      fi
      sleep 5
    done
}
rotate_backup()
{
    echo "Rotate backup..."

    if [[ ${MONGO_ROTATE_BACKUP} == true ]]; then

        WEEK=$(date +"%V")
        MONTH=$(date +"%b")
        let "INDEX = WEEK % 5" || true
        if [[ ${INDEX} == 0  ]]; then
          INDEX=4
        fi

        test -e ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz && rm ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz
        mv ${MONGO_BACKUP_DIR}/backup.tar.gz ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz
        echo "Create backup file: ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz"

        test -e ${MONGO_BACKUP_DIR}/backup.${MONTH}.tar.gz && rm ${MONGO_BACKUP_DIR}/backup.${MONTH}.tar.gz
        ln ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz ${MONGO_BACKUP_DIR}/backup.${MONTH}.tar.gz
        echo "Create backup file: ${MONGO_BACKUP_DIR}/backup.${MONTH}.tar.gz"

        test -e ${MONGO_BACKUP_DIR}/backup.last.tar.gz && rm ${MONGO_BACKUP_DIR}/backup.last.tar.gz
        ln ${MONGO_BACKUP_DIR}/backup.${INDEX}.tar.gz ${MONGO_BACKUP_DIR}/backup.last.tar.gz
        echo "Create backup file: ${MONGO_BACKUP_DIR}/backup.last.tar.gz"
        else
        mv ${MONGO_BACKUP_DIR}/backup.tar.gz ${MONGO_BACKUP_DIR}/backup.last.tar.gz
            echo "Create backup file: ${MONGO_BACKUP_DIR}/backup.last.tar.gz"
    fi
}

import_backup()
{
    echo "Import dump..."
    FILE=$1
    if [[ ${FILE} == default ]]; then
        FILE="${MONGO_BACKUP_DIR}/${MONGO_BACKUP_FILENAME}"
    fi
    if [[ ! -f "${FILE}" ]]; then
        echo "Unknown backup: ${FILE}"
        exit 1
    fi
    mkdir -p ${MONGO_BACKUP_DIR}/tmp
    tar -C ${MONGO_BACKUP_DIR}/tmp -xf ${FILE}
    sudo -Hu ${MONGO_USER} mongorestore ${RESTORE_OPTS} --dbpath ${MONGO_DATA_DIR} ${MONGO_BACKUP_DIR}/tmp
    rm -rf ${MONGO_BACKUP_DIR}/tm*
}

create_data_dir
create_log_dir

# Start mongos
if [[ ${MONGO_MODE} == mongos ]]; then
    # allow arguments to be passed to mongos
    if [[ ${1:0:1} = '-' ]]; then
      EXTRA_OPTS="$@"
      set --
    elif [[ ${1} == mongod || ${1} == $(which mongos) ]]; then
      EXTRA_OPTS="${@:2}"
      set --
    fi

    # default behaviour is to launch mongos
    if [[ -z ${1} ]]; then
      echo "Starting mongos..."
      exec start-stop-daemon --start --chuid ${MONGO_USER}:${MONGO_USER} \
        --exec $(which mongos) -- ${EXTRA_OPTS}
    else
      exec "$@"
    fi
fi

# allow arguments to be passed to mongod
if [[ ${1:0:1} = '-' ]]; then
    EXTRA_OPTS="$@"
    set --
elif [[ ${1} == mongod || ${1} == $(which mongod) ]]; then
    EXTRA_OPTS="${@:2}"
    set --
fi

# Backup
if [[ ${MONGO_MODE} == backup ]]; then
    echo "Backup databases..."
    if [[ ! "${EXTRA_OPTS}" =~ --host|-h ]]; then
        echo "Unknown host. '--host' does not null"
        exit 1;
    fi
    mkdir -p ${MONGO_BACKUP_DIR}/tmp
    mongodump ${EXTRA_OPTS} --out ${MONGO_BACKUP_DIR}/tmp
    cd ${MONGO_BACKUP_DIR}/tmp
    tar -zcvf ${MONGO_BACKUP_DIR}/backup.tar.gz * && rm -rf ${MONGO_BACKUP_DIR}/tm*
    cd -
    rotate_backup
    exit 0
fi

 # Check backup
if [[ -n ${MONGO_CHECK} ]]; then

    echo "Check backup..."
    if [[ -z ${COLLECTION_NAME} ]]; then
        echo "Unknown database. COLLECTION_NAME does not null"
        exit 1;
    fi
    import_backup "${MONGO_CHECK}"
    start_server
    if [[ $( mongo ${DB_NAME} --eval 'db.getCollectionNames()' | grep -wc ${COLLECTION_NAME} ) == 1 ]]; then
        echo "Success checking backup"
    else
        echo "Fail checking backup"
        exit 1;
    fi
    exit 0;
fi

# Restore from backup
if [[ -n ${MONGO_RESTORE} ]]; then
    echo "Restore from backup..."
    import_backup "${MONGO_RESTORE}"
fi

# default behaviour is to launch mongod
if [[ -z ${1} ]]; then
  echo "Starting mongod..."
  exec start-stop-daemon --start --chuid ${MONGO_USER}:${MONGO_USER} \
    --exec $(which mongod) -- --config ${MONGO_CONFIG} ${EXTRA_OPTS}
else
  exec "$@"
fi