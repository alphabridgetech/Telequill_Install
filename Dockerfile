# syntax=docker/dockerfile:1

ARG LIBRENMS_VERSION="Dev"
ARG ALPINE_VERSION="3.22"
ARG SYSLOGNG_VERSION="4.8.3-r1"

FROM crazymax/yasu:latest AS yasu
FROM crazymax/alpine-s6:${ALPINE_VERSION}-2.2.0.3
COPY --from=yasu / /

# -------------------------------------------------
# Base packages + Ansible
# -------------------------------------------------
RUN apk --update --no-cache add \
    busybox-extras \
    acl \
    bash \
    bind-tools \
    binutils \
    ca-certificates \
    coreutils \
    curl \
    file \
    fping \
    git \
    graphviz \
    imagemagick \
    ipmitool \
    iputils \
    libcap-utils \
    mariadb-client \
    monitoring-plugins \
    mtr \
    net-snmp \
    net-snmp-tools \
    nginx \
    nmap \
    openssl \
    openssh-client \
    perl \
    php83 \
    php83-cli \
    php83-ctype \
    php83-curl \
    php83-dom \
    php83-fileinfo \
    php83-fpm \
    php83-gd \
    php83-gmp \
    php83-iconv \
    php83-json \
    php83-ldap \
    php83-mbstring \
    php83-mysqlnd \
    php83-opcache \
    php83-openssl \
    php83-pdo \
    php83-pdo_mysql \
    php83-pecl-memcached \
    php83-pear \
    php83-phar \
    php83-posix \
    php83-session \
    php83-simplexml \
    php83-snmp \
    php83-sockets \
    php83-tokenizer \
    php83-xml \
    php83-xmlwriter \
    php83-zip \
    python3 \
    py3-pip \
    rrdtool \
    runit \
    sed \
    shadow \
    ttf-dejavu \
    tzdata \
    util-linux \
    whois \
  && apk --update --no-cache add -t build-dependencies \
    build-base \
    make \
    mariadb-dev \
    musl-dev \
    python3-dev \
    libffi-dev \
    openssl-dev \
  && pip3 install --upgrade pip setuptools wheel --break-system-packages \
  && pip3 install ansible mysqlclient python-memcached --break-system-packages \
  && apk del build-dependencies

# -------------------------------------------------
# ✅ INSTALL COMPOSER (FIX)
# -------------------------------------------------
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin \
    --filename=composer

# -------------------------------------------------
# Syslog-ng
# -------------------------------------------------
ARG SYSLOGNG_VERSION
RUN apk --update --no-cache add syslog-ng=${SYSLOGNG_VERSION}

# -------------------------------------------------
# ENV
# -------------------------------------------------
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS="2" \
  LIBRENMS_PATH="/opt/librenms" \
  LIBRENMS_DOCKER="1" \
  TZ="UTC" \
  PUID="1000" \
  PGID="1000"

# -------------------------------------------------
# User setup
# -------------------------------------------------
RUN addgroup -g ${PGID} librenms \
  && adduser -D -h /home/librenms -u ${PUID} -G librenms -s /bin/sh librenms \
  && curl -sSLk https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro -o /usr/bin/distro \
  && chmod +x /usr/bin/distro

# -------------------------------------------------
# LibreNMS clone
# -------------------------------------------------
WORKDIR ${LIBRENMS_PATH}
ARG LIBRENMS_VERSION

RUN apk --update --no-cache add -t build-dependencies \
    build-base \
    linux-headers \
    musl-dev \
    python3-dev \
  && git clone --branch ${LIBRENMS_VERSION} --single-branch https://github.com/alphabridgetech/librenms.git . \
  && pip3 install --ignore-installed -r requirements.txt --upgrade --break-system-packages \
  && composer install --no-dev --no-interaction --no-ansi \
  && mkdir -p config.d \
  && cp config.php.default config.php \
  && cp snmpd.conf.example /etc/snmp/snmpd.conf \
  && sed -i '/runningUser/d' lnms \
  && echo 'foreach (glob("/data/config/*.php") as $filename) include $filename;' >> config.php \
  && echo 'foreach (glob("/opt/librenms/config.d/*.php") as $filename) include $filename;' >> config.php \
  && chown -R nobody:nogroup ${LIBRENMS_PATH}

# -------------------------------------------------
# 🔥 Paramiko AFTER LibreNMS clone
# -------------------------------------------------
RUN python3 -m venv /opt/librenms/librenms-ansible-inventory-plugin \
 && /opt/librenms/librenms-ansible-inventory-plugin/bin/pip install --upgrade pip setuptools wheel \
 && /opt/librenms/librenms-ansible-inventory-plugin/bin/pip install paramiko \
 && apk del build-dependencies \
 && rm -rf /tmp/* tests/ doc/

# Force ansible to use venv python
ENV ANSIBLE_PYTHON_INTERPRETER=/opt/librenms/librenms-ansible-inventory-plugin/bin/python

COPY rootfs /

EXPOSE 8000 514 514/udp 162 162/udp
VOLUME [ "/data" ]

ENTRYPOINT [ "/init" ]
