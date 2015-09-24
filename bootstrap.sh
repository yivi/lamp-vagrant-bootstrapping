#!/usr/bin/env bash

# Use single quotes instead of double quotes to make it work with special-character passwords
PASSWORD='12345678'
PROJECTFOLDER='project'

# ip address last octet of ip address. ipv6, who knew ye?
read IP CN < <(exec ifconfig en0 | awk '/inet / { t = $2; sub(/.*[.]/, "", t); print $2, t }')

# create project folder (only necessary if we are not syncing yet, so maybe not?)
# sudo mkdir "/var/www/${PROJECTFOLDER}"

# update / upgrade
apt-get update && apt-get upgrade

# install apache 2.5 and php 5.5
echo ">>> installing apache"
apt-get install -y apache2

# hoboman runs apache
perl -pi -e 's/(APACHE_RUN_(USER|GROUP))=www-data/\1=vagrant/g' /etc/apache2/envvars

# no servername complaining, svp
perl -pi -e 's/(#ServerRoot "\/etc\/apache2")/\1\nServerName localhost/' /etc/apache2/apache2.conf

echo ">>> installing"
apt-get install -y php5

# install mysql and give password to installer
echo ">> configuring and install mysql"
debconf-set-selections <<< "mysql-server mysql-server/root_password password $PASSWORD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $PASSWORD"
apt-get -y install mysql-server

echo "CREATE DATABASE IF NOT EXISTS ${PROJECTFOLDER}" | mysql -u root -p$PASSWORD

echo ">>> installing php extensions"
apt-get install -y php5-curl php5-mcrypt php5-xdebug php5-gd
echo ">>> and php-mysql"
apt-get install -y php5-mysql

# setup hosts file
VHOST=$(cat <<EOF
<VirtualHost *:80>
    DocumentRoot "/var/www/${PROJECTFOLDER}"
    <Directory "/var/www/${PROJECTFOLDER}">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
)
echo "${VHOST}" > /etc/apache2/sites-available/000-default.conf

# enable mod_rewrite
sudo a2enmod rewrite

# enable php5-mcrypt
sudo php5enmod mcrypt

XDEBUG_INI=$(cat <<EOF
zend_extension=xdebug.so
xdebug.remote_host=33.33.33.1
xdebug.remote_enable=on
html_errors=1
xdebug.extended_info=1
xdebug.remote_port=9$CN
EOF
)

echo "${XDEBUG_INI}" > /etc/php5/mods-available/xdebug.ini

echo ">>> restarting apache"
service apache2 restart

# install git
apt-get -y install git subversion

# install Composer
echo ">>> downloading and installing composer"
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

echo ">>> installing wp-cli"
# install wp-cli
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
chmod 755 /usr/local/bin/wp
echo ">>> WP-CLI installed"

echo ">>> adjusting locales";
# locales
locale-gen es_ES.UTF-8 && dpkg-reconfigure locales

echo "Europe/Madrid" | sudo tee /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

PHPINFO=$(cat <<EOF
<?php
phpinfo();
EOF
)

# nice php info, to have something in place
echo "${PHPINFO}" > "/var/www/$PROJECT_FOLDER/info.php"
chown vagrant: "/var/www/$PROJECT_FOLDER/info.php" 
