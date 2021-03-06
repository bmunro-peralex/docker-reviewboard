#!/bin/bash

if [ "$DB_MYSQL" ]; then
	adapter='mysql'
	host="$DB_MYSQL"
    port="${DB_PORT:-$( echo "${MYSQL_PORT_3306_TCP_PORT:-3306}" )}"
elif [ "$DB_POSTGRES" ]; then
	adapter='postgresql'
	host="$DB_POSTGRES"
    port="${PGPORT:-$( echo "${POSTGRES_PORT_5432_TCP_PORT:-5432}" )}"
else
	echo >&2
	echo >&2 'error: missing DB_MYSQL or DB_POSTGRES environment variables'
	echo >&2
    exit 1
fi

DB_ADAPTER="$adapter"
DB_HOST="$host"
DB_PORT="$port"
DB_USER="${DB_USER:-reviewboard}"
DB_PASSWORD="${DB_PASSWORD:-reviewboard}"
DB_DATABASE="${DB_DATABASE:-reviewboard}"

# Get these variable either from MEMCACHED env var, or from
# linked "memcached" container.
MEMCACHED_LINKED_NOTCP="${MEMCACHED_PORT#tcp://}"
MEMCACHED="${MEMCACHED:-$( echo "${MEMCACHED_LINKED_NOTCP:-127.0.0.1}" )}"

DOMAIN="${DOMAIN:localhost}"

if [[  "${WAIT_FOR_DB}" = "true" ]]; then
    if [ -n "$DB_POSTGRES" ]; then
        echo "Waiting for Postgres readiness..."
        export DB_USER DB_HOST DB_PORT DB_PASSWORD

        until psql "${PGDB}"; do
            echo "Postgres is unavailable - sleeping"
            sleep 1
        done
        echo "Postgres is up!"
    elif [ -n "$DB_MYSQL" ]; then
        echo "Waiting for mysql readiness..."
        export DB_USER DB_HOST DB_PORT DB_PASSWORD

        until echo '\q' | mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" $DB_DATABASE; do
            >&2 echo "MySQL is unavailable - sleeping"
            sleep 1
        done
        echo "mysql is up!"
    fi

fi

if [[ "${SITE_ROOT}" ]]; then
    if [[ "${SITE_ROOT}" != "/" ]]; then
        # Add trailing and leading slashes to SITE_ROOT if it's not there.
        SITE_ROOT="${SITE_ROOT#/}"
        SITE_ROOT="/${SITE_ROOT%/}/"
    fi
else
    SITE_ROOT=/
fi

mkdir -p /var/www/

CONFFILE=/var/www/reviewboard/conf/settings_local.py

if [[ ! -d /var/www/reviewboard ]]; then
    rb-site install --noinput \
        --domain-name="$DOMAIN" \
        --site-root="$SITE_ROOT" \
        --static-url=static/ --media-url=media/ \
        --db-type="${DB_ADAPTER}" \
        --db-name="$DB_DATABASE" \
        --db-host="$DB_HOST" \
        --db-user="$DB_USER" \
        --db-pass="$DB_PASSWORD" \
        --cache-type=memcached --cache-info="$MEMCACHED" \
        --web-server-type=apache --web-server-port=8000 \
        --admin-user=admin --admin-password=admin --admin-email=admin@example.com \
        /var/www/reviewboard/
fi

chown -R www-data:root /var/www/reviewboard/

cp /var/www/reviewboard/conf/apache-wsgi.conf /etc/apache2/sites-available/000-default.conf
sed -i "s/ServerName/#ServerName/g" /etc/apache2/sites-available/000-default.conf
sed -i "s/8000/80/g" /etc/apache2/sites-available/000-default.conf

service apache2 reload

if [ -n "$INTERNAL_FONT_FIX" ]; then
    ### The troublesome issue with italic fonts (comments in code in particular) on ReviewBoard,                                                                               ### 
    ### where lower case l characters look like upper case L characters has been resolved by changing the font for comments to normal (non-italic).                            ###
    ### The particular issue is with the Consolas italic font, which is the default proportional font in Chrome (but apparently not in Firefox, which still uses Courier New). ###
    cp /var/www/reviewboard/htdocs/static/rb/css/syntax.css /var/www/reviewboard/htdocs/static/rb/css/syntax.css.bak
    sed -i '/.cm-s-rb .cm-comment *{/,/}/{s/\(font-style: *\)italic;/\1normal;/}' /var/www/reviewboard/htdocs/static/rb/css/syntax.css
fi

python upgrade-site.py /var/www/reviewboard/rb-version /var/www/reviewboard

if [[ "${DEBUG}" ]]; then
    sed -i 's/DEBUG *= *False/DEBUG=True/' "$CONFFILE"
    cat "${CONFFILE}"
fi

export SITE_ROOT

exec apachectl -D FOREGROUND
