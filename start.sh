#!/bin/bash
php-fpm --nodaemonize &
for i in $(seq 1 20); do
  [ -S /run/php-fpm/www.sock ] && break
  sleep 0.5
done
exec httpd -D FOREGROUND
