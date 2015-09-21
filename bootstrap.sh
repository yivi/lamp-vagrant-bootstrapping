#!/usr/bin/env bash

# Use single quotes instead of double quotes to make it work with special-character passwords
PASSWORD='12345678'
PROJECTFOLDER='magento'

# ip address last octet of ip address. ipv6, who knew ye?
read IP CN < <(exec ifconfig en0 | awk '/inet / { t = $2; sub(/.*[.]/, "", t); print $2, t }')

# create project folder (only necessary if we are not syncing yet, so maybe not?)
# sudo mkdir "/var/www/${PROJECTFOLDER}"

# update / upgrade
sudo apt-get update && sudo -y apt-get upgrade

# install apache 2.5 and php 5.5
sudo apt-get install -y apache2
sudo apt-get install -y php5

sudo apt-get install mc php5-curl php5-mcrypt mysql-server php5-xdebug

# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $PASSWORD"
sudo apt-get -y install mysql-server
sudo apt-get install php5-mysql

# install phpmyadmin and give password(s) to installer
# for simplicity I'm using the same password for mysql and phpmyadmin
# sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
# sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $PASSWORD"
# sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $PASSWORD"
# sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $PASSWORD"
# sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
# sudo apt-get -y install phpmyadmin

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
sudo echo "${VHOST}" > /etc/apache2/sites-available/000-default.conf

# enable mod_rewrite
sudo a2enmod rewrite

# hoboman runs apache
sudo perl -pi -e 's/(APACHE_RUN_(USER|GROUP))=www-data/\1=vagrant/g' /etc/apache2/envvars

# no servername complaining
sudo perl -pi -e 's/(#ServerRoot "/etc/apache2")/\1\nServerName local.vagrant' /etc/apache2/apache2.conf

XDEBUG_INI=$(cat <<EOF
zend_extension=xdebug.so
xdebug.remote_host=33.33.33.1
xdebug.remote_enable=on
html_errors=1
xdebug.extended_info=1
xdebug.remote_port=9$CN
EOF
)

sudo echo "${XDEBUG_INI}" > /etc/php5/mods-available/xdebug.ini

# install git
sudo apt-get -y install git subversion

# install Composer
curl -s https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

echo "Installing wp-cli"
# install wp-cli
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
echo "WP-CLI installed"

echo "Adjusting locales";
# locales
sudo locale-gen es_ES.UTF-8 && sudo dpkg-reconfigure locales

echo "<?php\nphpinfo()" > info.php

