FROM ubuntu:bionic
MAINTAINER romeOz <serggalka@gmail.com>

ENV OS_LOCALE="en_US.UTF-8" \
    DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y locales && locale-gen ${OS_LOCALE}
ENV LANG=${OS_LOCALE} \
    LANGUAGE=${OS_LOCALE} \
    LC_ALL=${OS_LOCALE}

ENV MONGO_USER=mongodb \
    MONGO_DATA_DIR=/var/lib/mongodb \
    MONGO_LOG_DIR=/var/log/mongodb \
    MONGO_CONFIG=/etc/mongodb/mongod.conf

RUN dpkg-reconfigure locales && apt-get install -y sudo gnupg \
 && apt-get install -y --reinstall ca-certificates \
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4 \
 && echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.0.list \
 && apt-get update && apt-get install -y mongodb-org \
 && apt-get purge -y --auto-remove gnupg \
 && rm -rf /var/lib/apt/lists/*

COPY mongod.conf ${MONGO_CONFIG}
COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 27017
VOLUME ["${MONGO_DATA_DIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]