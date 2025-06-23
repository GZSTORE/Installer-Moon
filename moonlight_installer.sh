#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function banner() {
    echo -e "${YELLOW}"
    echo "==============================="
    echo "      Moonlight Installer      "
    echo "==============================="
    echo -e "${NC}"
}

function install_dependencies() {
    echo -e "${GREEN}🔧 Installing dependencies...${NC}"
    apt update && apt upgrade -y
    apt install -y nginx mysql-server php8.1-{fpm,cli,gd,mbstring,xml,curl,bcmath,zip} unzip git curl ufw
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer
}

function install_panel() {
    echo -e "${GREEN}🌐 Setting up Moonlight Panel...${NC}"

    read -p "Domain Panel (e.g. panel.domainmu.com): " SUBDOMAIN
    read -p "Admin Username: " ADMIN_USER
    read -p "Admin Password: " ADMIN_PASS
    read -p "Admin Email: " ADMIN_EMAIL

    install_dependencies

    cd /var/www
    git clone https://github.com/Moonlight-Panel/Moonlight.git moonlight-panel
    cd moonlight-panel

    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    npm install && npm run build
    php artisan key:generate

    mysql -e "CREATE DATABASE IF NOT EXISTS moonlight; GRANT ALL ON moonlight.* TO 'moonlight'@'localhost' IDENTIFIED BY 'moonpass';"
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=moonlight/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=moonlight/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=moonpass/" .env

    php artisan migrate --seed --force
    php artisan moonlight:admin:create "$ADMIN_USER" "$ADMIN_EMAIL" "$ADMIN_PASS"

    chown -R www-data:www-data /var/www/moonlight-panel
    chmod -R 755 /var/www/moonlight-panel/storage /var/www/moonlight-panel/bootstrap/cache

    cat > /etc/nginx/sites-available/moonlight <<EOL
server {
    listen 80;
    server_name $SUBDOMAIN;
    root /var/www/moonlight-panel/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include fastcgi.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    ln -s /etc/nginx/sites-available/moonlight /etc/nginx/sites-enabled/ || true
    nginx -t && systemctl reload nginx

    echo -e "${GREEN}🔒 Setting up SSL...${NC}"
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d $SUBDOMAIN

    echo -e "${GREEN}🌐 Configuring firewall...${NC}"
    ufw allow 80
    ufw allow 443
    ufw allow 2022
    ufw allow 8080:8090/tcp
    ufw --force enable

    echo -e "${GREEN}✅ Moonlight Panel berhasil diinstall!${NC}"
    echo -e "${YELLOW}URL: https://$SUBDOMAIN"
    echo "Username: $ADMIN_USER"
    echo "Password: $ADMIN_PASS"
    echo "Email: $ADMIN_EMAIL${NC}"
}

function install_wings() {
    echo -e "${GREEN}🚀 Installing Wings...${NC}"
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    curl -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod +x /usr/local/bin/wings

    mkdir -p /etc/pterodactyl

    cat > /etc/systemd/system/wings.service <<EOL
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reexec
    systemctl enable --now wings

    echo -e "${YELLOW}⚠️ Wings sudah diinstall. Upload konfigurasi JSON-nya secara manual dari panel.${NC}"
}

function uninstall_panel() {
    echo -e "${RED}🗑️ Menghapus Moonlight Panel...${NC}"
    rm -rf /var/www/moonlight-panel
    rm -f /etc/nginx/sites-available/moonlight /etc/nginx/sites-enabled/moonlight
    systemctl reload nginx
    echo -e "${GREEN}✅ Panel berhasil dihapus.${NC}"
}

function uninstall_wings() {
    echo -e "${RED}🗑️ Menghapus Wings...${NC}"
    systemctl stop wings || true
    rm -f /usr/local/bin/wings
    rm -rf /etc/pterodactyl
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reexec
    echo -e "${GREEN}✅ Wings berhasil dihapus.${NC}"
}

function menu() {
    banner
    echo "1. Install Panel"
    echo "2. Install Wings"
    echo "3. Hapus Panel"
    echo "4. Hapus Wings"
    read -p "Pilih opsi [1-4]: " option
    case $option in
        1) install_panel ;;
        2) install_wings ;;
        3) uninstall_panel ;;
        4) uninstall_wings ;;
        *) echo -e "${RED}❌ Opsi tidak valid!${NC}" ;;
    esac
}

menu
