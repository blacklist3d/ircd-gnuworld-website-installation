#!/bin/bash

################################################################################
# Nefarious2 + Gnuworld + Website Installation Script
# For Ubuntu and Debian
# This script automates the installation of nefarious2 IRCD, gnuworld services,
# and the gnuworld website management interface
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
INSTALL_DIR="${INSTALL_DIR:-/home/ircd}"
GNUWORLD_DIR="${GNUWORLD_DIR:-$INSTALL_DIR/gnuworld}"
NEFARIOUS_DIR="${NEFARIOUS_DIR:-$INSTALL_DIR/nefarious2}"
WEBSITE_DIR="${WEBSITE_DIR:-$INSTALL_DIR/website}"
IRCD_USER="ircd"
IRCD_GROUP="ircd"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect operating system"
    fi

    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "This script only supports Ubuntu and Debian"
    fi

    log_success "Detected OS: $OS $VERSION"
}

install_dependencies() {
    log_info "Installing required dependencies..."

    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        git \
        wget \
        curl \
        ca-certificates \
        libssl-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libboost-all-dev \
        libmysqlclient-dev \
        mysql-client \
        postgresql \
        postgresql-contrib \
        libpq-dev \
        sqlite3 \
        libsqlite3-dev \
        tcl8.6 \
        tcl8.6-dev \
        python3 \
        python3-dev \
        python3-pip \
        apache2 \
        apache2-dev \
        php-fpm \
        php-mysql \
        php-pgsql \
        php-sqlite3 \
        php-curl \
        php-xml \
        php-gd \
        openssh-client \
        openssh-server \
        sudo \
        supervisor

    log_success "Dependencies installed"
}

create_ircd_user() {
    log_info "Creating ircd user and group..."

    if ! id "$IRCD_USER" &>/dev/null; then
        groupadd "$IRCD_GROUP" || true
        useradd -r -g "$IRCD_GROUP" -d "$INSTALL_DIR" -s /bin/bash "$IRCD_USER"
        log_success "Created user $IRCD_USER"
    else
        log_warning "User $IRCD_USER already exists"
    fi

    mkdir -p "$INSTALL_DIR"
    chown -R "$IRCD_USER:$IRCD_GROUP" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
}

install_nefarious2() {
    log_info "Installing Nefarious2 IRCD..."

    cd "$INSTALL_DIR"

    if [ ! -d "$NEFARIOUS_DIR" ]; then
        git clone https://github.com/evilnet/nefarious2.git "$NEFARIOUS_DIR"
    else
        log_warning "Nefarious2 directory already exists, updating..."
        cd "$NEFARIOUS_DIR"
        git pull origin master
    fi

    cd "$NEFARIOUS_DIR"

    log_info "Configuring Nefarious2..."
    ./configure --prefix="$NEFARIOUS_DIR/install" \
        --enable-debug \
        --with-mode=opm

    log_info "Building Nefarious2..."
    make
    make install

    log_success "Nefarious2 installed"
}

install_gnuworld() {
    log_info "Installing Gnuworld services..."

    cd "$INSTALL_DIR"

    if [ ! -d "$GNUWORLD_DIR" ]; then
        git clone https://github.com/evilnet/gnuworld.git "$GNUWORLD_DIR"
    else
        log_warning "Gnuworld directory already exists, updating..."
        cd "$GNUWORLD_DIR"
        git pull origin master
    fi

    cd "$GNUWORLD_DIR"

    log_info "Configuring Gnuworld..."
    ./configure --prefix="$GNUWORLD_DIR/install" \
        --with-nefarious="$NEFARIOUS_DIR" \
        --enable-modules

    log_info "Building Gnuworld..."
    make
    make install

    log_success "Gnuworld installed"
}

install_website() {
    log_info "Installing Gnuworld Website..."

    cd "$INSTALL_DIR"

    if [ ! -d "$WEBSITE_DIR" ]; then
        git clone https://github.com/evilnet/gnuworld-website.git "$WEBSITE_DIR"
    else
        log_warning "Website directory already exists, updating..."
        cd "$WEBSITE_DIR"
        git pull origin master
    fi

    cd "$WEBSITE_DIR"

    # Install PHP dependencies via composer if composer.json exists
    if [ -f "composer.json" ]; then
        log_info "Installing composer dependencies..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
        composer install
    fi

    # Install Python dependencies if requirements.txt exists
    if [ -f "requirements.txt" ]; then
        log_info "Installing Python dependencies..."
        python3 -m pip install -r requirements.txt
    fi

    log_success "Website installed"
}

setup_database() {
    log_info "Setting up databases..."

    # Create database directory if needed
    mkdir -p "$INSTALL_DIR/databases"
    chown -R "$IRCD_USER:$IRCD_GROUP" "$INSTALL_DIR/databases"

    log_info "Please configure your database settings:"
    log_info "- MySQL/MariaDB for services database"
    log_info "- PostgreSQL for website (optional)"
    log_info "- SQLite for local data (optional)"

    log_success "Database directories created"
}

setup_config_files() {
    log_info "Setting up configuration files..."

    mkdir -p "$INSTALL_DIR/config"

    # Create sample ircd.conf if it doesn't exist
    if [ ! -f "$INSTALL_DIR/config/ircd.conf" ]; then
        cat > "$INSTALL_DIR/config/ircd.conf.sample" << 'EOF'
# Nefarious2 IRCD Configuration
# This is a sample configuration file
# Modify according to your network needs

serverinfo {
    name = "irc.example.com";
    description = "Example IRC Network";
    network_name = "ExampleNet";
    hub = yes;
};

listen {
    port = 6667;
    address = "0.0.0.0";
};

# Add more configuration as needed
EOF
        log_warning "Created sample ircd.conf at $INSTALL_DIR/config/ircd.conf.sample"
    fi

    # Create sample gnuworld.conf
    if [ ! -f "$INSTALL_DIR/config/gnuworld.conf" ]; then
        cat > "$INSTALL_DIR/config/gnuworld.conf.sample" << 'EOF'
# Gnuworld Configuration
# Configure your services here

uplink {
    server = "127.0.0.1";
    port = 7777;
    password = "changeme";
};

modules {
    # Add module configurations here
};
EOF
        log_warning "Created sample gnuworld.conf at $INSTALL_DIR/config/gnuworld.conf.sample"
    fi

    chown -R "$IRCD_USER:$IRCD_GROUP" "$INSTALL_DIR/config"
}

setup_supervisor() {
    log_info "Setting up supervisor configurations..."

    mkdir -p /etc/supervisor/conf.d

    # Create nefarious2 supervisor config
    cat > /etc/supervisor/conf.d/nefarious2.conf << EOF
[program:nefarious2]
command=$NEFARIOUS_DIR/install/bin/ircd -f $INSTALL_DIR/config/ircd.conf
user=$IRCD_USER
group=$IRCD_GROUP
directory=$INSTALL_DIR
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/logs/nefarious2.log
environment=PATH="$NEFARIOUS_DIR/install/bin"
EOF

    # Create gnuworld supervisor config
    cat > /etc/supervisor/conf.d/gnuworld.conf << EOF
[program:gnuworld]
command=$GNUWORLD_DIR/install/bin/gnuworld -c $INSTALL_DIR/config/gnuworld.conf
user=$IRCD_USER
group=$IRCD_GROUP
directory=$INSTALL_DIR
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/logs/gnuworld.log
environment=PATH="$GNUWORLD_DIR/install/bin"
EOF

    mkdir -p "$INSTALL_DIR/logs"
    chown -R "$IRCD_USER:$IRCD_GROUP" "$INSTALL_DIR/logs"

    systemctl restart supervisor
    log_success "Supervisor configurations created"
}

setup_website_apache() {
    log_info "Setting up Apache for website..."

    mkdir -p "$WEBSITE_DIR/public"

    cat > /etc/apache2/sites-available/gnuworld-website.conf << EOF
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    ServerAdmin admin@example.com

    DocumentRoot $WEBSITE_DIR/public

    <Directory $WEBSITE_DIR/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/gnuworld-website-error.log
    CustomLog \${APACHE_LOG_DIR}/gnuworld-website-access.log combined
</VirtualHost>
EOF

    # Enable required Apache modules
    a2enmod proxy_fcgi setenvif rewrite

    # Enable the site
    a2ensite gnuworld-website.conf

    log_success "Apache configuration created"
}

setup_firewall() {
    log_info "Configuring firewall rules..."

    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp    # SSH
        ufw allow 6667/tcp  # IRC
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        log_success "UFW firewall rules configured"
    else
        log_warning "UFW not installed, please manually configure firewall"
    fi
}

create_startup_script() {
    log_info "Creating system startup script..."

    cat > /usr/local/bin/gnuworld-ctl << 'SCRIPT'
#!/bin/bash
# Gnuworld control script

case "$1" in
    start)
        supervisorctl start nefarious2 gnuworld
        ;;
    stop)
        supervisorctl stop nefarious2 gnuworld
        ;;
    restart)
        supervisorctl restart nefarious2 gnuworld
        ;;
    status)
        supervisorctl status nefarious2 gnuworld
        ;;
    logs)
        tail -f /home/ircd/logs/*.log
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
SCRIPT

    chmod +x /usr/local/bin/gnuworld-ctl
    log_success "Startup script created at /usr/local/bin/gnuworld-ctl"
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Edit configuration files:"
    echo "   - $INSTALL_DIR/config/ircd.conf"
    echo "   - $INSTALL_DIR/config/gnuworld.conf"
    echo ""
    echo "2. Set up your database:"
    echo "   - Create MySQL/MariaDB databases"
    echo "   - Import initial schema if provided"
    echo ""
    echo "3. Configure the website:"
    echo "   - Edit website configuration in $WEBSITE_DIR"
    echo "   - Update Apache site configuration"
    echo "   - Update domain name in /etc/apache2/sites-available/gnuworld-website.conf"
    echo ""
    echo "4. Set SSL certificates:"
    echo "   - Install Let's Encrypt: apt-get install certbot python3-certbot-apache"
    echo "   - Generate certificate: certbot --apache -d yourdomain.com"
    echo ""
    echo "5. Start services:"
    echo "   - systemctl restart supervisor"
    echo "   - systemctl restart apache2"
    echo "   - gnuworld-ctl status"
    echo ""
    echo -e "${YELLOW}Service Control:${NC}"
    echo "   gnuworld-ctl start|stop|restart|status|logs"
    echo ""
    echo -e "${YELLOW}Log Files:${NC}"
    echo "   $INSTALL_DIR/logs/nefarious2.log"
    echo "   $INSTALL_DIR/logs/gnuworld.log"
    echo "   /var/log/apache2/gnuworld-website-*.log"
    echo ""
    echo -e "${YELLOW}Installation Directories:${NC}"
    echo "   Nefarious2: $NEFARIOUS_DIR"
    echo "   Gnuworld: $GNUWORLD_DIR"
    echo "   Website: $WEBSITE_DIR"
    echo "   Config: $INSTALL_DIR/config"
    echo ""
}

# Main installation flow
main() {
    log_info "Starting Nefarious2 + Gnuworld + Website Installation"
    log_info "Installation directory: $INSTALL_DIR"
    echo ""

    check_root
    detect_os
    install_dependencies
    create_ircd_user
    install_nefarious2
    install_gnuworld
    install_website
    setup_database
    setup_config_files
    setup_supervisor
    setup_website_apache
    setup_firewall
    create_startup_script
    print_next_steps

    log_success "Installation process completed successfully!"
}

# Run main function
main "$@"
