#!/usr/bin/env bash

# Use single quotes instead of double quotes to make it work with special-character passwords
PASSWORD='12345678'
PROJECTFOLDER='project'
HTTPD='APACHE' # OR 'NGINX'
DB='MYSQL' # OR 'PXC'

# ip address last octet of ip address. ipv6, who knew ye?
read IP CN < <(exec ifconfig eth1 | awk '/inet / { t = $2; sub(/.*[.]/, "", t); print $2, t }')

# boostrapping apt-get with  update / upgrade
apt-get update && apt-get upgrade

# better hostname
echo $PROJECTFOLDER | tee /etc/hostname

export DEBIAN_FRONTEND=noninteractive

echo ">>> adjusting locales";
# locales
locale-gen es_ES.UTF-8
export LANGUAGE=es_ES.UTF-8
export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8
dpkg-reconfigure locales

echo "Europe/Madrid" | tee /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

echo ">>> downloading adminer"
mkdir -p /var/www/adminer && chown vagrant: /var/www/adminer
wget --quiet http://www.adminer.org/latest.php -O /var/www/adminer/index.php

mkdir -p /var/www/$PROJECTFOLDER

if [ $HTTPD = 'APACHE' ]; then
	# install apache 2.4
	echo ">>> installing apache"
	apt-get install -y apache2

	# hoboman runs apache
	perl -pi -e 's/(APACHE_RUN_(USER|GROUP))=www-data/\1=vagrant/g' /etc/apache2/envvars

	# no servername complaining, svp
	perl -pi -e 's/(#ServerRoot "\/etc\/apache2")/\1\nServerName localhost/' /etc/apache2/apache2.conf

	# setup hosts file(s)
	VHOST=$(cat <<EOF
	<VirtualHost *:80>
	    DocumentRoot "/var/www/${PROJECTFOLDER}"
	    ServerName local.${PROJECTFOLDER}
	    <Directory "/var/www/${PROJECTFOLDER}">
	        AllowOverride All
	        Require all granted
	    </Directory>

        ErrorLog ${APACHE_LOG_DIR}/error-local.{PROJECTFOLDER}.log
        LogLevel info

        # Let's NOT log some things
        SetEnvIf Request_URI "^/status.html$" dontlog
        SetEnvIf Request_URI "^/status.php$" dontlog
        SetEnvIf Request_URI "^/server-status$" dontlog

        CustomLog ${APACHE_LOG_DIR}/access-www.{PROJECTFOLDER}.log vhost_combined env=!dontlog
	</VirtualHost>
EOF
	)
	echo "${VHOST}" > /etc/apache2/sites-available/000-default.conf


    # vhost for adminer. for greater victory.
	VHOST=$(cat <<EOF
	<VirtualHost *:80>
	    DocumentRoot "/var/www/adminer"
	    ServerName vagrant.${PROJECTFOLDER}
	    <Directory "/var/www/adminer">
	        AllowOverride All
	        Require all granted
	    </Directory>

        ErrorLog ${APACHE_LOG_DIR}/error-local.adminer.log
        LogLevel info

        # Let's NOT log some things
        SetEnvIf Request_URI "^/status.html$" dontlog
        SetEnvIf Request_URI "^/status.php$" dontlog
        SetEnvIf Request_URI "^/server-status$" dontlog

        CustomLog ${APACHE_LOG_DIR}/access-adminer.net.log vhost_combined env=!dontlog
	</VirtualHost>
EOF
	)
	echo "${VHOST}" > /etc/apache2/sites-available/001-adminer.conf


    # a2ensite /etc/apache2/sites-available/001-adminer.conf ¿error wtf?
    ln -s /etc/apache2/sites-available/001-adminer.conf /etc/apache2/sites-enabled/001-adminer.conf

	# enable mod_rewrite, mod_expires, mod_headers
	a2enmod rewrite expires headers

elif [ $HTTPD = 'NGINX' ]; then
	#statements
	echo ">>> installing nginx"
	apt-get install -y nginx

	# hoboman runs nginx
	perl -pi -e 's/(user) www-data/\1 vagrant/' /etc/nginx/nginx.conf

	VHOST=$(cat <<EOF
server {
        listen  80 default_server;
        listen [::]:80 default_server ipv6only=on;
        server_name local.${PROJECTFOLDER}

        root /var/www/${PROJECTFOLDER};
        index index.php index.html index.htm;

        location / {
                try_files $uri $uri/ /index.php$is_args$args;
        }

        error_page 404 /404.html;

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
              root /usr/share/nginx/www;
        }

        # pass the PHP scripts to FastCGI server listening on the php-fpm socket
        location ~ \.php$ {
                try_files \$uri =404;
                fastcgi_pass unix:/var/run/php5-fpm.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                include fastcgi_params;
        }
}
EOF
	)
    echo "${VHOST}" > /etc/nginx/sites-available/default

    VHOST=$(cat <<EOF
server {
        listen  80;
        listen [::]:80 ipv6only=on;
        server_name vagrant.${PROJECTFOLDER}

        root /var/www/vagrant;
        index index.php;

        location / {
                try_files $uri $uri/ /index.php$is_args$args;
        }

        error_page 404 /404.html;

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
              root /usr/share/nginx/www;
        }

        # pass the PHP scripts to FastCGI server listening on the php-fpm socket
        location ~ \.php$ {
                try_files \$uri =404;
                fastcgi_pass unix:/var/run/php5-fpm.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                include fastcgi_params;
        }
}
EOF
	)
    echo "${VHOST}" > /etc/nginx/sites-available/adminer.conf

    ln -s /etc/nginx/sites-available/adminer.conf /etc/nginx/sites-enabled/adminer.conf

fi

if [ $DB = 'MYSQL' ]; then
    # install mysql and give password to installer
    echo ">> configuring and install mysql"
    debconf-set-selections <<< "mysql-server mysql-server/root_password password $PASSWORD"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $PASSWORD"
    apt-get -y install mysql-server-5.6
fi

if [ $DB = 'PXC' ]; then
    # install percona xtradb cluster and give password to installer
    echo ">> configuring and install percona xtradb cluster"
    apt-key adv --keyserver keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A
    echo "deb http://repo.percona.com/apt "$(lsb_release -sc)" main" | tee /etc/apt/sources.list.d/percona.list
    apt-get update

    debconf-set-selections <<< "percona-xtradb-cluster-server-5.6 percona-xtradb-cluster-server/root_password password $PASSWORD"
    debconf-set-selections <<< "percona-xtradb-cluster-server-5.6 percona-xtradb-cluster-server/root_password_again password $PASSWORD"

    apt-get -y install percona-xtradb-cluster-56
fi

echo "CREATE DATABASE IF NOT EXISTS ${PROJECTFOLDER}" | mysql -u root -p$PASSWORD

if [ $HTTPD = 'APACHE' ]; then
    echo ">>> installing PHP5 (apache)"
    apt-get install -y php5

fi

if [ $HTTPD = 'NGINX' ]; then
	echo ">>> installing php-fpm for nginx"
	apt-get install -y  php5-fpm php5-cli

	# fix cgi-fix so it stays fixed.
	perl -pi -e 's/;?(cgi.fix_pathinfo)=(1|0)/\1=0/' /etc/php5/fpm/php.ini

	# hoboman runs php as well
	perl -pi -e 's/((listen\.)?user|group|owner) = www-data/\1 = vagrant/g' /etc/php5/fpm/pool.d/www.conf

fi

echo ">>> installing php extensions"
apt-get install -y php5-curl php5-mcrypt php5-xdebug php5-gd
echo ">>> and php-mysql"
apt-get install -y php5-mysql

# enable php5-mcrypt
php5enmod mcrypt

XDEBUG_INI=$(cat <<EOF
zend_extension=xdebug.so
xdebug.remote_host=192.168.33.1
xdebug.remote_enable=on
xdebug.remote_autostart=1
html_errors=1
xdebug.extended_info=1
xdebug.remote_port=9$CN
EOF
)

echo "${XDEBUG_INI}" > /etc/php5/mods-available/xdebug.ini

if [ $HTTPD = 'NGINX' ]; then
    echo ">>> restarting FPM"
	service php5-fpm restart
fi

if [ $HTTPD = 'APACHE' ]; then
    echo ">>> restarting APACHE";
    service apache2 restart
fi

# install git
echo ">>> installing git && svn"
apt-get -y install git subversion


# install Composer
echo ">>> downloading and installing composer"
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

echo ">>> installing wp-cli"
# install wp-cli
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar --quiet
mv wp-cli.phar /usr/local/bin/wp
chmod 755 /usr/local/bin/wp
echo ">>> WP-CLI installed"

PHPINFO=$(cat <<EOF
<?php
phpinfo();
EOF
)

# nice php info, to have something in place
echo "${PHPINFO}" > "/var/www/${PROJECT_FOLDER}/info.php"
chown vagrant: "/var/www/${PROJECT_FOLDER}/info.php"
