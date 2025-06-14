#!/bin/bash

# Begrüßung
echo "Willkommen beim Nextcloud Installationsscript"

# Abfrage von Informationen
echo "Für den Start benötigen wir einige Informationen"

read -p "Bitte gib die Domain für deine Nextcloud ein: " DOMAIN
read -p "Bitte gib E-Mail Adresse ein: " MAIL
read -p "Bitte gib das Memory Limit für PHP ein (nur Zahl, z.B. 8196): " MEMLIMIT
MEMLIMIT="${MEMLIMIT}M"

echo "Wir benötigen noch Informationen für die Datenbank"

read -p "Bitte gib den Namen für die Datenbank ein: " DATABASE
read -p "Bitte gib Benutzernamen für die Datenbank ein: " DATABASEUSER
read -s -p "Bitte gib das Passwort für den Datenbankbenutzer ein: " DBUSERPW

# Kurze Zusammenfassung
echo "Zusammenfassung:"
echo "Domain: $DOMAIN"
echo "E-Mail: $MAIL"
echo "PHP Memory Limit: $MEMLIMIT"
echo "Datenbankname: $DATABASE"
echo "Datenbankbenutzer: $DATABASEUSER"

# Bestätigung
read -p "Sind diese Informationen korrekt? Möchtest du fortfahren? (j/n): " CONFIRM
if [[ "$CONFIRM" != "j" ]]; then
  echo "Installation abgebrochen."
  exit 1
fi

# Server updaten
apt update && sudo apt upgrade -y

# Apache und PHP Module installieren
apt install apache2 -y
apt install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt update
apt install php8.4 libapache2-mod-php8.4 php8.4-imagick libmagickcore-6.q16-6-extra php8.4-intl php8.4-bcmath php8.4-gmp php8.4-cli php8.4-mysql php8.4-zip php8.4-gd php8.4-mbstring php8.4-curl php8.4-xml php-pear unzip nano php8.4-apcu redis-server ufw php8.4-redis php8.4-smbclient php8.4-ldap php8.4-bz2 -y

# Pfad zur php.ini anpassen (je nach System: apache2, fpm, cli usw.)
PHPINI="/etc/php/8.4/apache2/php.ini"
BACKUP="${PHPINI}.bak"

# Sicherung erstellen
echo "📦 Erstelle Backup unter: $BACKUP"
cp "$PHPINI" "$BACKUP"

# Funktion zum Setzen oder Hinzufügen eines Werts in php.ini
set_php_value() {
    local key="$1"
    local value="$2"
    local file="$3"

    # Wenn Schlüssel vorhanden ist (auch auskommentiert), ersetze ihn
    if grep -qE "^\s*;?\s*${key}\s*=" "$file"; then
        sed -i -E "s|^\s*;?\s*(${key}\s*=).*|\1 $value|" "$file"
    else
        echo -e "\n${key} = $value" >> "$file"
    fi
}

# Werte setzen
set_php_value "memory_limit" "$MEMLIMIT" "$PHPINI"
set_php_value "upload_max_filesize" "20G" "$PHPINI"
set_php_value "post_max_size" "20G" "$PHPINI"
set_php_value "date.timezone" "\"Europe/Zurich\"" "$PHPINI"
set_php_value "output_buffering" "Off" "$PHPINI"

# OPCache Einstellungen
set_php_value "opcache.enable" "1" "$PHPINI"
set_php_value "opcache.enable_cli" "1" "$PHPINI"
set_php_value "opcache.interned_strings_buffer" "64" "$PHPINI"
set_php_value "opcache.max_accelerated_files" "10000" "$PHPINI"
set_php_value "opcache.memory_consumption" "1024" "$PHPINI"
set_php_value "opcache.save_comments" "1" "$PHPINI"
set_php_value "opcache.revalidate_freq" "1" "$PHPINI"


# Datenbank installerein
apt install mariadb-server -y

#MySQL Secure Defaults
SQL+="
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
"

echo "Führe sicherheitsbezogene SQL-Befehle aus..."
mysql -e "$SQL"

# SQL-Befehle vorbereiten
SQL_COMMANDS="
CREATE DATABASE IF NOT EXISTS \`${DATABASE}\`;
CREATE USER IF NOT EXISTS '${DATABASEUSER}'@'localhost' IDENTIFIED BY '${DBUSERPW}';
GRANT ALL PRIVILEGES ON \`${DATABASE}\`.* TO '${DATABASEUSER}'@'localhost';
FLUSH PRIVILEGES;
"

# Ausführen
echo "Führe SQL-Befehle aus..."
mysql -e "$SQL_COMMANDS"

# Nextcloud herunterladen, entpacken und verschieben
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
mv nextcloud /var/www/

# Apache-Konfig schreiben
cat <<EOF > "/etc/apache2/sites-available/nextcloud.conf"
<VirtualHost *:80>
    ServerAdmin $MAIL
    DocumentRoot /var/www/nextcloud/
    ServerName $DOMAIN
    <Directory /var/www/nextcloud/>
       Options +FollowSymlinks
       AllowOverride All
       Require all granted
          <IfModule mod_dav.c>
             Dav off
         </IfModule>
       SetEnv HOME /var/www/nextcloud
       SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Nextcloud Config aktivieren, Standartconfig deaktivieren
a2ensite nextcloud.conf
a2dissite 000-default.conf

# Apache Module aktivieren
a2enmod rewrite
a2enmod headers
a2enmod env
a2enmod dir
a2enmod mime

# Apache Server neustarten
systemctl restart apache2

# Daten Verzeichnis anlegen und Ordnerrechte setzen
mkdir /home/data/
chown -R www-data:www-data /home/data/
chown -R www-data:www-data /var/www/nextcloud/
chmod -R 755 /var/www/nextcloud/

# UFW Firewallregeln hinzufügen und Firewwall aktivieren
ufw allow 'apache full'
ufw allow ssh
ufw enable --force enable

# Certbot installieren
apt install certbot python3-certbot-apache -y

# Lets Encrypt Zertifikat anfordern
certbot --apache \
  -m "$MAIL" \
  -d "$DOMAIN" \
  --agree-tos \
  --no-eff-email \
  --redirect \
  --non-interactive

#Abschlussmeldung
echo "✅ Deine Nextcloud ist eingerichtet. Bitte verbinde dich nun mit dem Browser auf $DOMAIN und schliesse die Einrichtung ab."
