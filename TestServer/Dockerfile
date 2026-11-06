# A stand-in for a real server, for developing against. Started by Scripts/test-server.sh.
ARG BASE_IMAGE=ubuntu:24.04

# Only the docker CLI is needed, to reach neighboring containers through the mounted socket.
FROM docker:27-cli AS docker-cli

FROM ${BASE_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server rsync mariadb-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh new-host-key.sh seed-files.sh change-files.sh start-database.sh /usr/local/bin/
COPY databases/mysql-seed.sql /usr/local/share/hive-test/mysql-seed.sql

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
