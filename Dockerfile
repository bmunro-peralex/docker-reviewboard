FROM ubuntu:18.04
LABEL maintainer="bmunro@peralex.com"

ENV RB_VERSION 3.0.18
RUN apt-get update -y && \
    apt-get install --no-install-recommends -y \
        build-essential python-dev libffi-dev libmysqlclient-dev libssl-dev patch \
        python-pip python-setuptools python-wheel python-virtualenv \
        uwsgi uwsgi-plugin-python \
        postgresql-client mysql-client \
        python-psycopg2 python-mysqldb python-ldap \
        git-core mercurial subversion python-svn libexpat1 \
		apache2 apache2-utils libapache2-mod-wsgi \
		&& \
        rm -rf /var/lib/apt/lists/*

RUN set -ex; \
    if [ "${RB_VERSION}" ]; then RB_VERSION="==${RB_VERSION}"; fi; \
    python -m virtualenv --system-site-packages /opt/venv; \
    . /opt/venv/bin/activate; \
    pip install "ReviewBoard${RB_VERSION}" django-storages==1.1.8 oauthlib==1.0.1 semver django-reset mysqlclient; \
    rm -rf /root/.cache

ENV PATH="/opt/venv/bin:${PATH}"

ADD start.sh /start.sh
ADD uwsgi.ini /uwsgi.ini
ADD shell.sh /shell.sh
ADD upgrade-site.py /upgrade-site.py

RUN chmod +x /start.sh /shell.sh /upgrade-site.py

VOLUME /var/www/

EXPOSE 80

CMD /start.sh
