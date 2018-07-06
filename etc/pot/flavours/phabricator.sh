#!/bin/sh

env ASSUME_ALWAYS_YES=yes pkg bootstrap
pkg install -y apache24
pkg install -y mysql57-server
pkg install -y mod_php56 php56-mysql php56-mysqli
pkg install -y php56-gd
pkg install -y php-phabricator
pkg install -y git
pkg clean -ayq

# Configuring MySQL server
sysrc mysql_enable="YES"
mysql_secure_installation

# Configuring apache to start
sysrc apache24_enable="YES"
cat > /usr/local/etc/apache24/Includes/php.conf <<-APACHE
ServerName	phabricator.my.domain

<IfModule dir_module>
        DirectoryIndex index.php index.html
        <FilesMatch "\\.php$">
                SetHandler application/x-httpd-php
        </FilesMatch>
        <FilesMatch "\\.phps$">
                SetHandler application/x-httpd-php-source
        </FilesMatch>
</IfModule>
APACHE

# Configuring phabricator to start
sysrc phd_enable="YES"
cat > /usr/local/etc/apache24/Includes/phd.conf <<-PHD
LoadModule rewrite_module libexec/apache24/mod_rewrite.so

<VirtualHost *>
  # Change this to the domain which points to your host.
  ServerName phabricator.my.domain

  # Change this to the path where you put 'phabricator' when you checked it
  # out from GitHub when following the Installation Guide.
  #
  # Make sure you include "/webroot" at the end!
  DocumentRoot /path/to/phabricator/webroot

  RewriteEngine on
  RewriteRule ^(.*)$          /index.php?__path__=\$1  [B,L,QSA]
</VirtualHost>

<Directory "/usr/local/lib/php/phabricator/webroot">
  Require all granted
</Directory>
PHD

echo 'Please add this line also on the host'
echo '127.0.0.1		phabricator	phabricator.my.domain'
echo '127.0.0.1		phabricator	phabricator.my.domain' >> /etc/hosts

mkdir -p /var/tmp/phd/log /var/tmp/phd/pid
chown -R www:www /var/tmp/phd

echo 'extension=php_gd2.dll' > /usr/local/lib/php/php.ini
