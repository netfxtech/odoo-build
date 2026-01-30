ARG PYTHON_VERSION=3.12-slim
ARG OS_VARIANT=bookworm
ARG ODOO_VERSION
ARG WKHTMLTOX_VERSION=0.12.6.1-3
ARG ODOO_USER=odoo
ARG ODOO_BASEPATH=/opt/odoo
ARG APP_UID=1000
ARG APP_GID=1000

FROM python:${PYTHON_VERSION}-${OS_VARIANT} AS base

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

USER root

ARG WKHTMLTOX_VERSION
ENV WKHTMLTOX_VERSION=${WKHTMLTOX_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    ca-certificates \
    curl \
    dirmngr \
    fonts-noto-cjk \
    gnupg \
    libssl-dev \
    node-less \
    npm \
    python3-num2words \
    python3-odf \
    python3-pdfminer \
    python3-pip \
    python3-phonenumbers \
    python3-pyldap \
    python3-qrcode \
    python3-renderpm \
    python3-setuptools \
    python3-slugify \
    python3-vobject \
    python3-watchdog \
    python3-xlrd \
    python3-xlwt \
    git-core \
    htop \
    ffmpeg \
    fonts-liberation2 \
    lsb-release \
    nano \
    ssh \
    sudo \
    unzip \
    vim \
    zip \
    xz-utils \
    xmlsec1 \
    && \
    if [ "$(uname -m)" = "aarch64" ]; then \
        curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}.$(lsb_release -cs)_arm64.deb \
    ; else \
        curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}.$(lsb_release -cs)_amd64.deb \
    ; fi \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && apt-get autopurge -yqq \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb /tmp/*

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    lsb-release \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get -qq install -y --no-install-recommends postgresql-client libpq-dev \
    && rm -f /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g rtlcss \
    && rm -Rf ~/.npm /tmp/*

FROM base AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    apt-utils dialog \
    apt-transport-https \
    build-essential \
    libcairo2-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libghc-zlib-dev \
    libharfbuzz-dev \
    libjpeg-dev \
    libgeoip-dev \
    libmaxminddb-dev \
    liblcms2-dev \
    libldap2-dev \
    libopenjp2-7-dev \
    libsasl2-dev \
    libtiff5-dev \
    libxml2-dev \
    libxslt1-dev \
    libmagic1 \
    libwebp-dev \
    tcl-dev \
    tk-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/*

ARG ODOO_VERSION

RUN pip3 install --prefix=/usr/local --no-cache-dir --upgrade --requirement https://raw.githubusercontent.com/odoo/odoo/19.0/requirements.txt \
    && pip3 -qq install --prefix=/usr/local --no-cache-dir --upgrade \
    rlpycairo \
    'websocket-client~=0.56' \
    astor \
    black \
    pylint-odoo \
    flake8 \
    pydevd-odoo \
    psycogreen \
    click-odoo-contrib \
    git-aggregator \
    inotify \
    python-json-logger \
    wdb \
    redis \
    && apt-get autopurge -yqq \
    && rm -rf /var/lib/apt/lists/* /tmp/*


RUN git clone --depth 100 -b 19.0 https://git.netfxtech.cloud/odoo/odoo.git /opt/odoo \
    && pip3 install --editable /opt/odoo \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN git clone --depth 100 -b 19.0 https://git.netfxtech.cloud/odoo/enterprise.git /opt/odoo/enterprise

ADD requirements.txt /tmp/requirements.txt
RUN pip3 install --prefix=/usr/local --no-cache-dir --upgrade --requirement /tmp/requirements.txt \
    && rm -rf /var/lib/apt/lists/* /tmp/*

RUN rm -rf /opt/odoo/.git /opt/odoo/enterprise/.git

FROM base AS production

ENV PIP_AUTO_INSTALL=${PIP_AUTO_INSTALL:-"0"}

ENV RUN_TESTS=${RUN_TESTS:-"0"}

ENV WITHOUT_TEST_TAGS=${WITHOUT_TEST_TAGS:-"0"}

ENV UPGRADE_ODOO=${UPGRADE_ODOO:-"0"}

ARG ODOO_BASEPATH
ENV ODOO_BASEPATH=${ODOO_BASEPATH}

# Create app user
ARG ODOO_USER
ENV ODOO_USER=${ODOO_USER}

ARG APP_UID
ENV APP_UID=${APP_UID}

ARG APP_GID
ENV APP_GID=${APP_GID}

RUN addgroup --system --gid ${APP_GID} ${ODOO_USER} \
    && adduser --system --uid ${APP_UID} --ingroup ${ODOO_USER} --home ${ODOO_BASEPATH} --disabled-login --shell /bin/bash ${ODOO_USER} \
    && echo ${ODOO_USER} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${ODOO_USER}\
    && chmod 0440 /etc/sudoers.d/${ODOO_USER}


ENV ODOO_RC=${ODOO_RC:-/etc/odoo/odoo.conf}
ENV ODOO_DATA_DIR=${ODOO_DATA_DIR:-/var/lib/odoo/data}
ENV ODOO_LOGS_DIR=${ODOO_LOGS_DIR:-/var/lib/odoo/logs}
ENV ODOO_EXTRA_ADDONS=${ODOO_EXTRA_ADDONS:-/mnt/extra-addons}
ENV ODOO_ADDONS_BASEPATH=${ODOO_BASEPATH}/addons
ENV ODOO_CMD=${ODOO_BASEPATH}/odoo-bin

RUN mkdir -p ${ODOO_DATA_DIR} ${ODOO_LOGS_DIR} ${ODOO_EXTRA_ADDONS} /etc/odoo/

RUN chown -R ${APP_UID}:${APP_GID} ${ODOO_DATA_DIR} ${ODOO_LOGS_DIR} ${ODOO_EXTRA_ADDONS} ${ODOO_BASEPATH} /etc/odoo

VOLUME ["${ODOO_DATA_DIR}", "${ODOO_LOGS_DIR}", "${ODOO_EXTRA_ADDONS}"]

ARG EXTRA_ADDONS_PATHS
ENV EXTRA_ADDONS_PATHS=${EXTRA_ADDONS_PATHS}

ARG EXTRA_MODULES
ENV EXTRA_MODULES=${EXTRA_MODULES}

COPY --link --chown=${APP_UID}:${APP_GID} --from=builder /usr/local /usr/local
COPY --link --chown=${APP_UID}:${APP_GID} --from=builder /opt/odoo ${ODOO_BASEPATH}

COPY --link --chown=${APP_UID}:${APP_GID} ./resources/entrypoint.sh /
COPY --link --chown=${APP_UID}:${APP_GID} ./resources/getaddons.py /


RUN chmod u+x /entrypoint.sh

EXPOSE 8069 8071 8072

ENTRYPOINT ["/entrypoint.sh"]

USER ${ODOO_USER}

CMD ["/opt/odoo/odoo-bin"]
