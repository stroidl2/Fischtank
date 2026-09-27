# Fischtank

# DB direkt abfragen
podman exec -it mariadb mariadb -u webuser -pchangeme namen -e "SELECT * FROM personen;"

# Stoppen
podman stop apache-server mariadb

# Komplett entfernen
podman rm -f apache-server mariadb && podman network rm webnet