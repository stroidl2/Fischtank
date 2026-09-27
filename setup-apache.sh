#!/bin/bash
# setup-apache.sh — Baut und startet einen Apache-Webserver in einem Podman-Container

set -euo pipefail

IMAGE_NAME="Fischtank"
CONTAINER_NAME="fischtank-apache-server"
HOST_PORT="8080"
CONTAINER_PORT="8080"
HTML_DIR="./html"
CONTAINERFILE="Containerfile"

# ── 1. HTML-Verzeichnis anlegen (falls nicht vorhanden) ──────────────────────
if [ ! -d "$HTML_DIR" ]; then
  echo "[INFO] Erstelle HTML-Verzeichnis: $HTML_DIR"
  mkdir -p "$HTML_DIR"
  cat > "$HTML_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Apache auf Podman</title>
</head>
<body>
  <h1>Apache läuft auf Podman!</h1>
  <p>Dieser Server wurde mit dem setup-apache.sh Script gestartet.</p>
</body>
</html>
EOF
  echo "[INFO] Beispiel-index.html wurde erstellt."
fi

# ── 2. Containerfile erstellen ───────────────────────────────────────────────
echo "[INFO] Schreibe $CONTAINERFILE ..."
cat > "$CONTAINERFILE" <<'EOF'
FROM registry.redhat.io/ubi9/ubi-minimal:latest

# Apache installieren
RUN microdnf install -y httpd && \
    microdnf clean all

# Nicht-root-Benutzer anlegen
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /var/www/html /run/httpd /var/log/httpd

# Apache auf nicht-privilegierten Port umstellen
RUN sed -i 's/^Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^#ServerName.*/ServerName localhost/' /etc/httpd/conf/httpd.conf

# Web-Inhalte kopieren
COPY --chown=appuser:appuser ./html/ /var/www/html/

USER 1001

EXPOSE 8080

CMD ["httpd", "-D", "FOREGROUND"]
EOF

# ── 3. Alten Container entfernen (falls vorhanden) ───────────────────────────
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
