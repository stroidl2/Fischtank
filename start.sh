#!/bin/bash
# php-fpm im Hintergrund starten
php-fpm --nodaemonize &
FPM_PID=$!

# Warten bis Socket bereit ist
for i in $(seq 1 10); do
  [ -S /run/php-fpm/www.sock ] && break
  sleep 0.5
done

# Apache im Vordergrund starten
exec httpd -D FOREGROUND
