FROM quay.io/centos/centos:stream9-minimal

# Apache + PHP + MySQL-Treiber + httpd-tools (für .htpasswd) installieren
RUN microdnf install -y httpd httpd-tools php php-cli php-common php-fpm php-pdo php-mysqlnd && \
    microdnf clean all

# php-fpm auf appuser umstellen und Unix-Socket konfigurieren
RUN mkdir -p /run/php-fpm && \
    sed -i 's/^listen = .*/listen = \/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^listen.owner = .*/listen.owner = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^listen.group = .*/listen.group = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^user = apache/user = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^group = apache/group = appuser/' /etc/php-fpm.d/www.conf

# Nicht-root-Benutzer anlegen + Session-Verzeichnis freigeben
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /var/www/html /run/httpd /var/log/httpd /run/php-fpm /var/log/php-fpm && \
    chown -R appuser:appuser /var/lib/php/session /var/lib/php/wsdlcache /var/lib/php/opcache

# Apache auf Port 8080 umstellen + AllowOverride für .htaccess aktivieren
RUN sed -i 's/^Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^#ServerName.*/ServerName localhost/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/AllowOverride None/AllowOverride AuthConfig/' /etc/httpd/conf/httpd.conf

# Web-Inhalte kopieren
COPY --chown=appuser:appuser ./html/ /var/www/html/

# Startscript kopieren
COPY --chown=appuser:appuser start.sh /start.sh
RUN chmod +x /start.sh

USER 1001

EXPOSE 8080

CMD ["/start.sh"]
