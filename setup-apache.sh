#!/bin/bash
# setup-apache.sh — Baut und startet einen Apache-Webserver in einem Podman-Container

set -euo pipefail

IMAGE_NAME="my-apache"
CONTAINER_NAME="apache-server"
HOST_PORT="8080"
CONTAINER_PORT="8080"
HTML_DIR="./html"
CONTAINERFILE="Containerfile"

# ── 1. HTML-Verzeichnis anlegen (falls nicht vorhanden) ──────────────────────
mkdir -p "$HTML_DIR"
if [ ! -f "$HTML_DIR/index.php" ]; then
  echo "[INFO] Erstelle PHP-Formular: $HTML_DIR/index.php"
  cat > "$HTML_DIR/index.php" <<'PHPEOF'
<?php
$vorname  = '';
$nachname = '';
$anzeige  = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $vorname  = htmlspecialchars(trim($_POST['vorname']  ?? ''), ENT_QUOTES, 'UTF-8');
    $nachname = htmlspecialchars(trim($_POST['nachname'] ?? ''), ENT_QUOTES, 'UTF-8');
    $anzeige  = ($vorname !== '' && $nachname !== '');
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Namenseingabe</title>
  <style>
    body { font-family: sans-serif; max-width: 480px; margin: 60px auto; padding: 0 1rem; }
    h1   { font-size: 1.4rem; margin-bottom: 1.5rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text] {
      width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem;
    }
    button {
      padding: .5rem 1.5rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer;
    }
    button:hover { background: #2563b0; }
    .result {
      margin-top: 1.5rem; padding: 1rem;
      background: #f0f6ff; border: 1px solid #bfdbfe; border-radius: 4px;
    }
  </style>
</head>
<body>
  <h1>Namenseingabe</h1>
  <form method="POST" action="">
    <label for="vorname">Vorname</label>
    <input type="text" id="vorname" name="vorname"
           value="<?= $vorname ?>" placeholder="z. B. Max" required>
    <label for="nachname">Nachname</label>
    <input type="text" id="nachname" name="nachname"
           value="<?= $nachname ?>" placeholder="z. B. Mustermann" required>
    <button type="submit">Absenden</button>
  </form>
  <?php if ($anzeige): ?>
  <div class="result">
    <strong>Eingegebener Name:</strong><br>
    <?= $vorname ?> <?= $nachname ?>
  </div>
  <?php endif; ?>
</body>
</html>
PHPEOF
  echo "[INFO] index.php wurde erstellt."
fi

# ── 2. Containerfile erstellen ───────────────────────────────────────────────
echo "[INFO] Schreibe $CONTAINERFILE ..."
cat > "$CONTAINERFILE" <<'EOF'
FROM quay.io/centos/centos:stream9-minimal

# Apache + PHP installieren
RUN microdnf install -y httpd php php-cli php-common php-fpm && \
    microdnf clean all

# php-fpm Socket-Verzeichnis und Berechtigungen vorbereiten
RUN mkdir -p /run/php-fpm && \
    sed -i 's/^listen = .*/listen = \/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^listen.owner = .*/listen.owner = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^listen.group = .*/listen.group = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^user = apache/user = appuser/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^group = apache/group = appuser/' /etc/php-fpm.d/www.conf

# Nicht-root-Benutzer anlegen
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /var/www/html /run/httpd /var/log/httpd /run/php-fpm /var/log/php-fpm

# Apache auf nicht-privilegierten Port umstellen
RUN sed -i 's/^Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^#ServerName.*/ServerName localhost/' /etc/httpd/conf/httpd.conf

# Web-Inhalte kopieren
COPY --chown=appuser:appuser ./html/ /var/www/html/

# Startscript: php-fpm + httpd
COPY --chown=appuser:appuser start.sh /start.sh
RUN chmod +x /start.sh

USER 1001

EXPOSE 8080

CMD ["/start.sh"]
EOF

# ── 3. start.sh erstellen (startet php-fpm + httpd) ─────────────────────────
echo "[INFO] Schreibe start.sh ..."
cat > "start.sh" <<'EOF'
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
EOF
chmod +x start.sh

# ── 4. Alten Container entfernen (falls vorhanden) ───────────────────────────
if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
  echo "[INFO] Entferne bestehenden Container: $CONTAINER_NAME"
  podman rm -f "$CONTAINER_NAME"
fi

# ── 4. Image bauen ───────────────────────────────────────────────────────────
echo "[INFO] Baue Image: $IMAGE_NAME ..."
podman build -t "$IMAGE_NAME" .

# ── 5. Container starten ─────────────────────────────────────────────────────
echo "[INFO] Starte Container: $CONTAINER_NAME ..."
podman run -d \
  --name "$CONTAINER_NAME" \
  --publish "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
  "$IMAGE_NAME"

# ── 6. Status ausgeben ───────────────────────────────────────────────────────
echo ""
echo "✅ Apache-Webserver läuft!"
echo "   URL:       http://127.0.0.1:${HOST_PORT}"
echo "   Container: $CONTAINER_NAME"
echo "   Image:     $IMAGE_NAME"
echo ""
echo "Nützliche Befehle:"
echo "  Logs anzeigen:   podman logs -f $CONTAINER_NAME"
echo "  Stoppen:         podman stop $CONTAINER_NAME"
echo "  Entfernen:       podman rm -f $CONTAINER_NAME"
