# Fishtank — Apache HA + MariaDB auf Podman

Dieses Projekt startet einen **hochverfügbaren Web-Stack** bestehend aus zwei Apache/PHP-Webservern hinter einem HAProxy-Loadbalancer und einer MariaDB-Datenbank, alle als Podman-Container in einem gemeinsamen Netzwerk.

---

## Architektur

```
Browser
   │
   ▼ http://127.0.0.1:8080
┌──────────────────────┐
│  HAProxy             │  Sticky Sessions (PHPSESSID)
│  Health-Check: 2s    │  Stats: http://127.0.0.1:8404/stats
└──────┬──────────┬────┘
       │          │  Round-Robin (neue Verbindungen)
┌──────▼──┐  ┌───▼─────┐
│ web-1   │  │ web-2   │  beide im internen Netzwerk "webnet"
│ Apache  │  │ Apache  │  kein direkter Port am Host
│ PHP 8   │  │ PHP 8   │
└────┬────┘  └────┬────┘
     └──────┬─────┘
        ┌───▼────────┐
        │  mariadb   │  Volume: mariadb-data (persistent)
        └────────────┘
```

---

## Voraussetzungen

| Software | Version | Hinweis |
|---|---|---|
| [Podman](https://podman.io) | ≥ 4.x | `brew install podman` (macOS) |
| macOS / Linux | — | Auf macOS: Podman-VM erforderlich |

### Podman-VM starten (nur macOS, einmalig)

```bash
podman machine init
podman machine start
```

---

## Schnellstart

```bash
chmod +x rebuild-Container.sh
./rebuild-Container.sh
```

| URL | Beschreibung |
|---|---|
| http://127.0.0.1:8080 | Webanwendung (Login erforderlich) |
| http://127.0.0.1:8404/stats | HAProxy Status-Dashboard |

Standard-Login: **admin** / **geheim123**

---

## Projektstruktur

```
fishtank/
├── rebuild-Container.sh     # Haupt-Script: baut und startet den gesamten Stack
├── Containerfile            # Image für Apache + PHP (wird generiert)
├── Containerfile.haproxy    # Image für HAProxy-Loadbalancer
├── haproxy.cfg              # HAProxy-Konfiguration (Loadbalancing + Health-Checks)
├── start.sh                 # Startscript im Web-Container: php-fpm + httpd (generiert)
├── html/
│   ├── index.php            # Hauptanwendung: Namenseingabe mit Datenbank
│   ├── login.php            # Login-Seite (Session-basiert)
│   └── admin.php            # Benutzerverwaltung
└── backups/
    └── namen_YYYYMMDD_HHMMSS.sql   # Automatische DB-Backups
```

---

## Was das Script macht

[`rebuild-Container.sh`](rebuild-Container.sh) führt beim Aufruf folgende Schritte aus:

| Schritt | Aktion |
|---|---|
| 1 | `html/` vorbereiten, `index.php` anlegen falls nicht vorhanden |
| 2 | `Containerfile` für Apache+PHP schreiben |
| 3 | `start.sh` (php-fpm + httpd) schreiben |
| 4 | Persistentes Volume `mariadb-data` anlegen (falls nicht vorhanden) |
| 4b | Podman-Netzwerk `webnet` anlegen (falls nicht vorhanden) |
| 5 | **Datenbank-Backup** nach `./backups/` erstellen (falls DB läuft) |
| 6 | MariaDB-Container starten |
| 7 | Migration: alten Einzel-Container `apache-server` entfernen |
| 8 | Apache-Image bauen |
| 9 | **Zwei** Apache-Container starten (`apache-server-1`, `apache-server-2`) |
| 9b | Admin-Account in der Datenbank anlegen / aktualisieren |
| 10 | HAProxy-Image bauen |
| 11 | HAProxy-Container starten (Port 8080 + 8404) |
| 12 | Status ausgeben |

---

## Webanwendung

### Seiten

| Seite | URL | Beschreibung |
|---|---|---|
| Login | `/login.php` | Anmeldung mit Benutzername + Passwort |
| Hauptseite | `/index.php` | Namenseingabe, Anzeige aller Einträge, Löschen |
| Benutzerverwaltung | `/admin.php` | Benutzer anlegen, aktivieren/deaktivieren, löschen |

### Datenbankschema

```sql
-- Gespeicherte Personen
CREATE TABLE personen (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    vorname  VARCHAR(100) NOT NULL,
    nachname VARCHAR(100) NOT NULL,
    erstellt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Web-Benutzer (Login)
CREATE TABLE users (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,   -- bcrypt
    active        TINYINT(1)   NOT NULL DEFAULT 1,
    erstellt      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);
```

---

## Ausfallsicherheit

### Verhalten bei Ausfall eines Web-Servers

HAProxy überwacht beide Web-Container alle **2 Sekunden**. Fällt einer aus:

1. Nach 2 fehlgeschlagenen Checks (≈ 4s) wird der Server als `DOWN` markiert
2. Alle neuen Anfragen gehen automatisch an den verbleibenden Server
3. Sobald der Server wieder verfügbar ist (2 erfolgreiche Checks), nimmt er Traffic auf

### Sticky Sessions

Durch `cookie PHPSESSID prefix` in der HAProxy-Konfiguration wird ein eingeloggter Benutzer immer zum selben Backend-Server geleitet. Fällt dieser aus, wird der Benutzer auf den anderen Server umgeleitet (neuer Login erforderlich).

### Ausfall simulieren

```bash
# web1 stoppen → web2 übernimmt automatisch
podman stop apache-server-1

# Status im HAProxy-Dashboard prüfen
open http://127.0.0.1:8404/stats

# web1 wiederherstellen
podman start apache-server-1
```

---

## Persistenz & Backups

### Datenpersistenz

| Volume | Pfad im Container | Überlebt `podman rm`? |
|---|---|---|
| `mariadb-data` | `/var/lib/mysql` | ✅ Ja |

### Automatische Backups

Bei jedem Aufruf von `./rebuild-Container.sh` wird automatisch ein SQL-Dump erstellt:

```
./backups/namen_YYYYMMDD_HHMMSS.sql
```

### Backup manuell erstellen

```bash
podman exec mariadb mariadb-dump -u root -prootsecret namen > ./backups/mein_backup.sql
```

### Backup einspielen

```bash
podman exec -i mariadb mariadb -u root -prootsecret namen < ./backups/namen_YYYYMMDD_HHMMSS.sql
```

---

## Nützliche Befehle

```bash
# Logs anzeigen
podman logs -f apache-server-1
podman logs -f apache-server-2
podman logs -f haproxy
podman logs -f mariadb

# Direkt in die Datenbank
podman exec -it mariadb mariadb -u webuser -pchangeme namen

# Stack stoppen (Daten bleiben erhalten)
podman stop apache-server-1 apache-server-2 haproxy mariadb

# Stack neu starten
podman start mariadb apache-server-1 apache-server-2 haproxy

# Alles entfernen (Volume und Daten BLEIBEN erhalten)
podman rm -f apache-server-1 apache-server-2 haproxy mariadb
podman network rm webnet

# Alles inkl. Daten löschen
podman rm -f apache-server-1 apache-server-2 haproxy mariadb
podman network rm webnet
podman volume rm mariadb-data
```

---

## Konfiguration

Alle Einstellungen befinden sich am Anfang von [`rebuild-Container.sh`](rebuild-Container.sh):

| Variable | Standard | Beschreibung |
|---|---|---|
| `NETWORK_NAME` | `webnet` | Name des Podman-Netzwerks |
| `DB_VOLUME` | `mariadb-data` | Name des persistenten Volumes |
| `DB_CONTAINER` | `mariadb` | Container-Name der Datenbank |
| `DB_NAME` | `namen` | Datenbankname |
| `DB_USER` | `webuser` | Datenbankbenutzer für die App |
| `DB_PASS` | `changeme` | Passwort des Datenbankbenutzers |
| `DB_ROOT_PASS` | `rootsecret` | Root-Passwort der Datenbank |
| `WEB_CONTAINER_1` | `apache-server-1` | Erster Web-Container |
| `WEB_CONTAINER_2` | `apache-server-2` | Zweiter Web-Container |
| `HAPROXY_CONTAINER` | `haproxy` | HAProxy-Container-Name |
| `HOST_PORT` | `8080` | Externer Port (Anwendung) |
| `STATS_PORT` | `8404` | Externer Port (HAProxy-Stats) |
| `AUTH_USER` | `admin` | Standard-Admin-Benutzername |
| `AUTH_PASS` | `geheim123` | Standard-Admin-Passwort |

> **Hinweis:** Passe `DB_PASS`, `DB_ROOT_PASS` und `AUTH_PASS` für Produktivumgebungen an.

---

## Sicherheitshinweise

- Webserver laufen als **nicht-root Benutzer** (UID 1001)
- Datenbankport ist **nicht nach außen** exponiert (nur intern über `webnet`)
- Web-Container sind **nicht direkt** am Host erreichbar — nur über HAProxy
- Webserver nur über `127.0.0.1` erreichbar (kein `0.0.0.0`)
- Passwörter werden mit **bcrypt** gehasht (`password_hash()` / `password_verify()`)
- Datenbankzugriff über **Prepared Statements** (SQL-Injection-sicher)
- Alle Ausgaben mit `htmlspecialchars()` kodiert (XSS-sicher)
- Eigener Account kann nicht gelöscht oder als letzter aktiver Account deaktiviert werden
