
#!/bin/bash

function install_panel() {
    echo "🔧 Installing Moonlight Panel..."

    apt update && apt upgrade -y
    apt install -y nginx mysql-server php8.1-{fpm,cli,gd,mbstring,xml,curl,bcmath,zip} unzip git curl
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer

    cd /var/www
    git clone https://github.com/Moonlight-Panel/Moonlight.git moonlight-panel
    cd moonlight-panel

    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    npm install
    npm run build
    php artisan key:generate

    mysql -e "CREATE DATABASE IF NOT EXISTS moonlight; GRANT ALL ON moonlight.* TO 'moonlight'@'localhost' IDENTIFIED BY 'moonpass';"
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=moonlight/;s/DB_USERNAME=.*/DB_USERNAME=moonlight/;s/DB_PASSWORD=.*/DB_PASSWORD=moonpass/" .env

    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/moonlight-panel
    chmod -R 755 /var/www/moonlight-panel/storage /var/www/moonlight-panel/bootstrap/cache

    cat > /etc/nginx/sites-available/moonlight <<'EOL'
server {
    listen 80;
    server_name _;
    root /var/www/moonlight-panel/public;
    index index.php;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ { include fastcgi.conf; fastcgi_pass unix:/run/php/php8.1-fpm.sock; }
    location ~ /\.ht { deny all; }
}
EOL

    ln -s /etc/nginx/sites-available/moonlight /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    echo "✅ Moonlight Panel Installed at http://<Your-IP>"
}

function install_wings() {
    echo "🚀 Installing Wings (Daemon)..."

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    curl -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod +x /usr/local/bin/wings

    mkdir -p /etc/pterodactyl
    echo -e "\n📝 Wings installed! You need to upload config from the panel manually."
}

function uninstall_panel() {
    echo "⚠️ Uninstalling Moonlight Panel..."
    rm -rf /var/www/moonlight-panel
    rm -f /etc/nginx/sites-available/moonlight /etc/nginx/sites-enabled/moonlight
    systemctl reload nginx
    echo "✅ Moonlight Panel deleted."
}

clear
echo "=========================="
echo "  Moonlight Panel Setup"
echo "=========================="
echo "1. Install Panel"
echo "2. Install Wings"
echo "3. Delete Panel"
read -p "Choose an option [1-3]: " choice

case $choice in
    1) install_panel ;;
    2) install_wings ;;
    3) uninstall_panel ;;
    *) echo "❌ Invalid option!" ;;
esac
