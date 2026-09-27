#!/bin/bash
# rebuild-Container.sh — Apache (HA) + MariaDB + HAProxy in Podman-Containern

set -euo pipefail

# ── Konfiguration ────────────────────────────────────────────────────────────
NETWORK_NAME="webnet"
DB_VOLUME="mariadb-data"        # benanntes Volume — überlebt podman rm
DB_IMAGE="docker.io/library/mariadb:11"
DB_CONTAINER="mariadb"
DB_ROOT_PASS="rootsecret"
DB_NAME="namen"
DB_USER="webuser"
DB_PASS="changeme"

# Web-Login (wird in der Datenbank gespeichert)
AUTH_USER="admin"
AUTH_PASS="geheim123"

WEB_IMAGE="my-apache"
WEB_CONTAINER_1="apache-server-1"
WEB_CONTAINER_2="apache-server-2"
HAPROXY_IMAGE="my-haproxy"
HAPROXY_CONTAINER="haproxy"
HOST_PORT="8080"
STATS_PORT="8404"
CONTAINER_PORT="8080"
HTML_DIR="./html"
CONTAINERFILE="Containerfile"

# ── 1. Verzeichnis vorbereiten (.htaccess/.htpasswd nicht mehr benötigt) ─────
mkdir -p "$HTML_DIR"
rm -f "$HTML_DIR/.htaccess" "$HTML_DIR/.htpasswd"

# ── 1. PHP-Formular erstellen (falls nicht vorhanden) ─────────────────────────
if [ ! -f "$HTML_DIR/index.php" ]; then
  echo "[INFO] Erstelle PHP-Formular: $HTML_DIR/index.php"
  cat > "$HTML_DIR/index.php" <<'PHPEOF'
<?php
$dsn    = 'mysql:host=mariadb;port=3306;dbname=namen;charset=utf8mb4';
$dbUser = 'webuser';
$dbPass = getenv('DB_PASSWORD') ?: 'changeme';

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec("CREATE TABLE IF NOT EXISTS personen (
        id       INT AUTO_INCREMENT PRIMARY KEY,
        vorname  VARCHAR(100) NOT NULL,
        nachname VARCHAR(100) NOT NULL,
        erstellt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
} catch (PDOException $e) {
    $dbError = 'Datenbankverbindung fehlgeschlagen.';
}

$vorname = $nachname = $message = '';

if (!isset($dbError) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? 'insert';
    if ($action === 'delete' && isset($_POST['id'])) {
        $id = (int)$_POST['id'];
        $stmt = $pdo->prepare("DELETE FROM personen WHERE id = ?");
        $stmt->execute([$id]);
        $message = '🗑️ Eintrag #' . $id . ' wurde gelöscht.';
    } else {
        $vorname  = trim($_POST['vorname']  ?? '');
        $nachname = trim($_POST['nachname'] ?? '');
        if ($vorname !== '' && $nachname !== '') {
            $stmt = $pdo->prepare("INSERT INTO personen (vorname, nachname) VALUES (?, ?)");
            $stmt->execute([mb_substr($vorname, 0, 100), mb_substr($nachname, 0, 100)]);
            $message  = '✅ ' . htmlspecialchars($vorname,  ENT_QUOTES, 'UTF-8')
                      . ' '  . htmlspecialchars($nachname, ENT_QUOTES, 'UTF-8')
                      . ' wurde gespeichert.';
            $vorname = $nachname = '';
        }
    }
}

$personen = [];
if (!isset($dbError)) {
    $personen = $pdo->query("SELECT * FROM personen ORDER BY erstellt DESC")->fetchAll();
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Namenseingabe</title>
  <style>
    body  { font-family: sans-serif; max-width: 600px; margin: 60px auto; padding: 0 1rem; }
    h1,h2 { font-size: 1.3rem; margin-bottom: 1rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text] { width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; box-sizing: border-box; }
    button { padding: .5rem 1.5rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer; }
    button:hover { background: #2563b0; }
    button.del { padding: .25rem .75rem; background: #fff; color: #c0392b;
      border: 1px solid #fca5a5; font-size: .85rem; }
    button.del:hover { background: #fff0f0; }
    .msg  { margin-top: 1rem; padding: .75rem; background: #f0f6ff;
      border: 1px solid #bfdbfe; border-radius: 4px; }
    .err  { background: #fff0f0; border-color: #fca5a5; }
    table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; font-size: .95rem; }
    th,td { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid #e5e7eb; }
    th    { background: #f7f8fa; font-weight: bold; }
    tr:hover td { background: #f7f8fa; }
  </style>
</head>
<body>
  <h1>Namenseingabe</h1>
  <?php if (isset($dbError)): ?>
    <div class="msg err"><?= htmlspecialchars($dbError, ENT_QUOTES, 'UTF-8') ?></div>
  <?php else: ?>
  <form method="POST" action="">
    <label for="vorname">Vorname</label>
    <input type="text" id="vorname" name="vorname"
           value="<?= htmlspecialchars($vorname,  ENT_QUOTES, 'UTF-8') ?>"
           placeholder="z. B. Max" required maxlength="100">
    <label for="nachname">Nachname</label>
    <input type="text" id="nachname" name="nachname"
           value="<?= htmlspecialchars($nachname, ENT_QUOTES, 'UTF-8') ?>"
           placeholder="z. B. Mustermann" required maxlength="100">
    <button type="submit">Speichern</button>
  </form>
  <?php if ($message): ?>
    <div class="msg"><?= $message ?></div>
  <?php endif; ?>
  <h2>Gespeicherte Einträge</h2>
  <?php if (empty($personen)): ?>
    <p style="color:#57606a">Noch keine Einträge vorhanden.</p>
  <?php else: ?>
  <table>
    <thead><tr><th>#</th><th>Vorname</th><th>Nachname</th><th>Gespeichert</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($personen as $p): ?>
      <tr>
        <td><?= (int)$p['id'] ?></td>
        <td><?= htmlspecialchars($p['vorname'],  ENT_QUOTES, 'UTF-8') ?></td>
        <td><?= htmlspecialchars($p['nachname'], ENT_QUOTES, 'UTF-8') ?></td>
        <td><?= htmlspecialchars($p['erstellt'], ENT_QUOTES, 'UTF-8') ?></td>
        <td>
          <form method="POST" action="" style="margin:0">
            <input type="hidden" name="action" value="delete">
            <input type="hidden" name="id" value="<?= (int)$p['id'] ?>">
            <button type="submit" class="del">Löschen</button>
          </form>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>
  <?php endif; ?>
</body>
</html>
PHPEOF
  echo "[INFO] index.php wurde erstellt."
fi

# ── 2. Containerfile für Apache+PHP erstellen ────────────────────────────────
echo "[INFO] Schreibe $CONTAINERFILE ..."
cat > "$CONTAINERFILE" <<'EOF'
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
EOF

# ── 3. Startscript für php-fpm + httpd erstellen ─────────────────────────────
echo "[INFO] Schreibe start.sh ..."
cat > "start.sh" <<'EOF'
#!/bin/bash
php-fpm --nodaemonize &
for i in $(seq 1 20); do
  [ -S /run/php-fpm/www.sock ] && break
  sleep 0.5
done
exec httpd -D FOREGROUND
EOF
chmod +x start.sh

# ── 4. Benanntes Volume erstellen (falls nicht vorhanden) ────────────────────
if ! podman volume exists "$DB_VOLUME" 2>/dev/null; then
  echo "[INFO] Erstelle persistentes Volume: $DB_VOLUME"
  podman volume create "$DB_VOLUME"
else
  echo "[INFO] Volume '$DB_VOLUME' bereits vorhanden — Daten bleiben erhalten."
fi

# ── 4b. Podman-Netzwerk erstellen (falls nicht vorhanden) ────────────────────
if ! podman network exists "$NETWORK_NAME" 2>/dev/null; then
  echo "[INFO] Erstelle Podman-Netzwerk: $NETWORK_NAME"
  podman network create "$NETWORK_NAME"
else
  echo "[INFO] Netzwerk '$NETWORK_NAME' bereits vorhanden."
fi

# ── 5. Backup der Datenbank (vor Container-Neustart) ─────────────────────────
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"
if podman container exists "$DB_CONTAINER" 2>/dev/null; then
  BACKUP_FILE="${BACKUP_DIR}/namen_$(date +%Y%m%d_%H%M%S).sql"
  echo "[INFO] Erstelle Datenbank-Backup: $BACKUP_FILE"
  if podman exec "$DB_CONTAINER" mariadb-dump \
      -u root -p"$DB_ROOT_PASS" "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
    echo "[INFO] Backup erfolgreich: $BACKUP_FILE"
  else
    echo "[WARN] Backup fehlgeschlagen (DB evtl. nicht erreichbar) — fahre fort."
    rm -f "$BACKUP_FILE"
  fi
fi

# ── 6. MariaDB-Container starten ─────────────────────────────────────────────
if podman container exists "$DB_CONTAINER" 2>/dev/null; then
  echo "[INFO] Entferne bestehenden DB-Container: $DB_CONTAINER"
  podman rm -f "$DB_CONTAINER"
fi

echo "[INFO] Starte MariaDB-Container: $DB_CONTAINER ..."
podman run -d \
  --name "$DB_CONTAINER" \
  --network "$NETWORK_NAME" \
  --volume "${DB_VOLUME}:/var/lib/mysql" \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASS" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASS" \
  "$DB_IMAGE"

# ── 6. Auf MariaDB warten ─────────────────────────────────────────────────────
echo "[INFO] Warte auf MariaDB ..."
for i in $(seq 1 30); do
  if podman exec "$DB_CONTAINER" mariadb-admin ping -u root -p"$DB_ROOT_PASS" --silent 2>/dev/null; then
    echo "[INFO] MariaDB ist bereit."
    break
  fi
  sleep 2
done

# ── 6b. users-Tabelle anlegen ────────────────────────────────────────────────
echo "[INFO] Richte users-Tabelle ein ..."
podman exec "$DB_CONTAINER" mariadb -u root -p"$DB_ROOT_PASS" "$DB_NAME" <<'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    active        TINYINT(1)   NOT NULL DEFAULT 1,
    erstellt      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);
SQLEOF

# ── 6c. Admin-Account via PHP im Web-Container anlegen ───────────────────────
# (PHP wird erst nach dem Build verfügbar — daher nach dem Start)
echo "[INFO] Merke Admin-Zugangsdaten für Post-Start-Setup ..."

# ── 7. Alten Einzel-Container entfernen (Migration) ─────────────────────────
for OLD in "apache-server"; do
  if podman container exists "$OLD" 2>/dev/null; then
    echo "[INFO] Entferne alten Container: $OLD"
    podman rm -f "$OLD"
  fi
done

# ── 8. Apache-Image bauen ────────────────────────────────────────────────────
echo "[INFO] Baue Web-Image: $WEB_IMAGE ..."
podman build -t "$WEB_IMAGE" .

# ── 9. Zwei Apache-Container starten ─────────────────────────────────────────
for WEB_CONTAINER in "$WEB_CONTAINER_1" "$WEB_CONTAINER_2"; do
  if podman container exists "$WEB_CONTAINER" 2>/dev/null; then
    echo "[INFO] Entferne bestehenden Web-Container: $WEB_CONTAINER"
    podman rm -f "$WEB_CONTAINER"
  fi
  echo "[INFO] Starte Web-Container: $WEB_CONTAINER ..."
  podman run -d \
    --name "$WEB_CONTAINER" \
    --network "$NETWORK_NAME" \
    -e DB_PASSWORD="$DB_PASS" \
    "$WEB_IMAGE"
done

# ── 9b. Admin-Account via PHP im ersten Web-Container anlegen ─────────────────
echo "[INFO] Lege Admin-Account '${AUTH_USER}' in der Datenbank an ..."
sleep 3
podman exec "$WEB_CONTAINER_1" php -r "
\$dsn  = 'mysql:host=mariadb;port=3306;dbname=namen;charset=utf8mb4';
\$pdo  = new PDO(\$dsn, 'webuser', getenv('DB_PASSWORD') ?: 'changeme');
\$pdo->exec(\"CREATE TABLE IF NOT EXISTS users (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    active        TINYINT(1)   NOT NULL DEFAULT 1,
    erstellt      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
)\");
\$hash = password_hash('${AUTH_PASS}', PASSWORD_BCRYPT);
\$stmt = \$pdo->prepare(
    'INSERT INTO users (username, password_hash)
     VALUES (?, ?)
     ON DUPLICATE KEY UPDATE password_hash = ?, active = 1'
);
\$stmt->execute(['${AUTH_USER}', \$hash, \$hash]);
echo \"[INFO] Admin-Account gespeichert.\n\";
"

# ── 10. HAProxy-Image bauen ───────────────────────────────────────────────────
if podman container exists "$HAPROXY_CONTAINER" 2>/dev/null; then
  echo "[INFO] Entferne bestehenden HAProxy-Container: $HAPROXY_CONTAINER"
  podman rm -f "$HAPROXY_CONTAINER"
fi

echo "[INFO] Baue HAProxy-Image: $HAPROXY_IMAGE ..."
podman build -t "$HAPROXY_IMAGE" -f Containerfile.haproxy .

# ── 11. HAProxy starten ───────────────────────────────────────────────────────
echo "[INFO] Starte HAProxy-Container: $HAPROXY_CONTAINER ..."
podman run -d \
  --name "$HAPROXY_CONTAINER" \
  --network "$NETWORK_NAME" \
  --publish "127.0.0.1:${HOST_PORT}:8080" \
  --publish "127.0.0.1:${STATS_PORT}:8404" \
  "$HAPROXY_IMAGE"

# ── 12. Status ausgeben ───────────────────────────────────────────────────────
echo ""
echo "✅ HA-Stack läuft!"
echo ""
echo "  🌐 Anwendung:  http://127.0.0.1:${HOST_PORT}  (Login: ${AUTH_USER} / ${AUTH_PASS})"
echo "  📊 HAProxy:    http://127.0.0.1:${STATS_PORT}/stats"
echo "  🗄️  MariaDB:    Container '$DB_CONTAINER' im Netzwerk '$NETWORK_NAME'"
echo ""
echo "  💾 Volume:     '$DB_VOLUME' (Daten persistent auf dem Host)"
echo ""
echo "  Web-Container: $WEB_CONTAINER_1, $WEB_CONTAINER_2 (Round-Robin)"
echo ""
echo "Nützliche Befehle:"
echo "  Web-Logs:   podman logs -f $WEB_CONTAINER_1"
echo "  Proxy-Logs: podman logs -f $HAPROXY_CONTAINER"
echo "  DB-Logs:    podman logs -f $DB_CONTAINER"
echo "  DB-Shell:   podman exec -it $DB_CONTAINER mariadb -u $DB_USER -p$DB_PASS $DB_NAME"
echo "  Stoppen:    podman stop $WEB_CONTAINER_1 $WEB_CONTAINER_2 $HAPROXY_CONTAINER $DB_CONTAINER"
echo "  Entfernen:  podman rm -f $WEB_CONTAINER_1 $WEB_CONTAINER_2 $HAPROXY_CONTAINER $DB_CONTAINER && podman network rm $NETWORK_NAME"
echo "  Ausfall sim: podman stop $WEB_CONTAINER_1   # web2 übernimmt automatisch"
