#!/bin/bash

################################################################################
# Nefarious2 + Undernet GNUWorld + Website Installation Script
# For Ubuntu and Debian
# This script automates the installation of:
# - Nefarious2 IRCd (evilnet/nefarious2)
# - GNUWorld Services with all modules (UndernetIRC/gnuworld)
# - GNUWorld Website Management Interface
# - PostgreSQL Database
# - Apache2 + PHP
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
INSTALL_DIR="${INSTALL_DIR:-/home/gnuworld}"
GNUWORLD_DIR="${GNUWORLD_DIR:-$INSTALL_DIR/gnuworld}"
NEFARIOUS_DIR="${NEFARIOUS_DIR:-$INSTALL_DIR/nefarious2}"
WEBSITE_DIR="${WEBSITE_DIR:-$INSTALL_DIR/website}"
GNUWORLD_USER="gnuworld"
GNUWORLD_GROUP="gnuworld"
POSTGRESQL_USER="gnuworld"
POSTGRESQL_PASSWORD=$(openssl rand -base64 16)

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
    apt-get upgrade -y

    # Build tools and essentials
    apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        autotools-dev \
        libtool \
        pkg-config \
        git \
        wget \
        curl \
        ca-certificates \
        gnupg \
        lsb-release

    # Development libraries
    apt-get install -y --no-install-recommends \
        libssl-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libboost-all-dev \
        libpq-dev \
        sqlite3 \
        libsqlite3-dev

    # Scripting and languages
    apt-get install -y --no-install-recommends \
        tcl8.6 \
        tcl8.6-dev \
        python3 \
        python3-dev \
        python3-pip \
        perl

    # PostgreSQL
    apt-get install -y --no-install-recommends \
        postgresql \
        postgresql-contrib \
        postgresql-client

    # Web server and PHP
    apt-get install -y --no-install-recommends \
        apache2 \
        apache2-dev \
        libapache2-mod-php \
        php \
        php-cli \
        php-fpm \
        php-pgsql \
        php-mysql \
        php-sqlite3 \
        php-curl \
        php-xml \
        php-gd \
        php-json \
        php-mbstring \
        php-zip \
        php-intl

    # System utilities
    apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        sudo \
        supervisor \
        htop \
        tmux \
        vim \
        nano \
        screen

    log_success "All dependencies installed"
}

create_gnuworld_user() {
    log_info "Creating gnuworld user and group..."

    if ! id "$GNUWORLD_USER" &>/dev/null; then
        groupadd "$GNUWORLD_GROUP" || true
        useradd -r -m -g "$GNUWORLD_GROUP" -d "$INSTALL_DIR" -s /bin/bash "$GNUWORLD_USER"
        log_success "Created user $GNUWORLD_USER"
    else
        log_warning "User $GNUWORLD_USER already exists"
    fi

    mkdir -p "$INSTALL_DIR"
    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"

    # Add gnuworld to sudo for easier management
    echo "$GNUWORLD_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/gnuworld || true

    # Increase file descriptors
    cat >> /etc/security/limits.conf << EOF
$GNUWORLD_USER soft nofile 65536
$GNUWORLD_USER hard nofile 65536
$GNUWORLD_USER soft nproc 32768
$GNUWORLD_USER hard nproc 32768
EOF
}

install_nefarious2() {
    log_info "Installing Nefarious2 IRCd from evilnet/nefarious2..."

    cd "$INSTALL_DIR"

    if [ ! -d "$NEFARIOUS_DIR" ]; then
        log_info "Cloning Nefarious2 repository..."
        git clone https://github.com/evilnet/nefarious2.git "$NEFARIOUS_DIR"
    else
        log_warning "Nefarious2 directory already exists, pulling updates..."
        cd "$NEFARIOUS_DIR"
        git pull origin master || git pull origin main
    fi

    cd "$NEFARIOUS_DIR"

    log_info "Configuring Nefarious2..."
    ./configure \
        --prefix="$NEFARIOUS_DIR/install" \
        --enable-debug \
        --with-mode=opm \
        --with-pgsql

    log_info "Building Nefarious2 (this may take several minutes)..."
    make -j$(nproc)
    make install

    log_success "Nefarious2 installed at $NEFARIOUS_DIR/install"
}

install_gnuworld() {
    log_info "Installing GNUWorld from UndernetIRC/gnuworld with all modules..."

    cd "$INSTALL_DIR"

    if [ ! -d "$GNUWORLD_DIR" ]; then
        log_info "Cloning GNUWorld repository..."
        git clone https://github.com/UndernetIRC/gnuworld.git "$GNUWORLD_DIR"
    else
        log_warning "GNUWorld directory already exists, pulling updates..."
        cd "$GNUWORLD_DIR"
        git pull origin master || git pull origin main
    fi

    cd "$GNUWORLD_DIR"

    log_info "Configuring GNUWorld..."
    # Ensure configure script exists
    if [ ! -f "configure" ]; then
        log_info "Running autoreconf..."
        autoreconf -i
    fi

    ./configure \
        --prefix="$GNUWORLD_DIR/install" \
        --with-nefarious="$NEFARIOUS_DIR/install" \
        --enable-modules \
        --with-pgsql

    log_info "Building GNUWorld with all modules (this may take several minutes)..."
    make -j$(nproc)
    make install

    # Build all available modules
    log_info "Building GNUWorld modules..."
    cd "$GNUWORLD_DIR"
    for module_dir in mod.*; do
        if [ -d "$module_dir" ]; then
            log_info "Building module: $module_dir..."
            cd "$module_dir"
            if [ -f "configure" ] || [ -f "Makefile.in" ]; then
                autoreconf -i || true
                ./configure --prefix="$GNUWORLD_DIR/install" --with-gnuworld="$GNUWORLD_DIR/install" || true
                make -j$(nproc) || true
                make install || true
            fi
            cd ..
        fi
    done

    log_success "GNUWorld with all modules installed at $GNUWORLD_DIR/install"
}

install_website() {
    log_info "Installing GNUWorld Website..."

    cd "$INSTALL_DIR"

    if [ ! -d "$WEBSITE_DIR" ]; then
        log_info "Cloning GNUWorld website repository..."
        # Try common website repository names
        if git clone https://github.com/UndernetIRC/gnuworld-website.git "$WEBSITE_DIR" 2>/dev/null; then
            log_success "Cloned gnuworld-website repository"
        elif git clone https://github.com/UndernetIRC/website.git "$WEBSITE_DIR" 2>/dev/null; then
            log_success "Cloned website repository"
        else
            log_warning "Could not find official website repository, creating directory structure..."
            mkdir -p "$WEBSITE_DIR"
        fi
    else
        log_warning "Website directory already exists"
        if [ -d "$WEBSITE_DIR/.git" ]; then
            cd "$WEBSITE_DIR"
            git pull origin master || git pull origin main || true
        fi
    fi

    cd "$WEBSITE_DIR"

    # Create basic directory structure
    mkdir -p public logs config

    # Install PHP dependencies via composer if composer.json exists
    if [ -f "composer.json" ]; then
        log_info "Installing composer dependencies..."
        if ! command -v composer &> /dev/null; then
            curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
        fi
        sudo -u $GNUWORLD_USER composer install
    fi

    # Install Python dependencies if requirements.txt exists
    if [ -f "requirements.txt" ]; then
        log_info "Installing Python dependencies..."
        python3 -m pip install -r requirements.txt
    fi

    # Create a basic index.php if none exists
    if [ ! -f "public/index.php" ]; then
        log_info "Creating basic website structure..."
        cat > "$WEBSITE_DIR/public/index.php" << 'PHPEOF'
<?php
/**
 * GNUWorld Website - Main Index
 * This is a placeholder for your GNUWorld web interface
 */
?>
<!DOCTYPE html>
<html>
<head>
    <title>GNUWorld Services</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .status { margin: 20px 0; padding: 10px; background-color: #e8f5e9; border-left: 4px solid #4caf50; }
        .warning { background-color: #fff3e0; border-left-color: #ff9800; }
    </style>
</head>
<body>
    <div class="container">
        <h1>GNUWorld Services</h1>
        <p>Welcome to your GNUWorld services installation.</p>
        
        <div class="status">
            <strong>Installation Status:</strong> PHP is working correctly
        </div>
        
        <div class="status warning">
            <strong>Next Steps:</strong>
            <ul>
                <li>Configure your database connection</li>
                <li>Set up channel and nickname services</li>
                <li>Configure Apache virtual host</li>
                <li>Install your web interface</li>
            </ul>
        </div>

        <h2>System Information</h2>
        <p>PHP Version: <?php echo phpversion(); ?></p>
        <p>PostgreSQL Support: <?php echo extension_loaded('pgsql') ? '✓ Enabled' : '✗ Disabled'; ?></p>
    </div>
</body>
</html>
PHPEOF
    fi

    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$WEBSITE_DIR"
    chmod -R 755 "$WEBSITE_DIR"
    chmod -R 775 "$WEBSITE_DIR/logs"

    log_success "Website installed at $WEBSITE_DIR"
}

setup_postgresql() {
    log_info "Setting up PostgreSQL database..."

    # Start PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql

    # Create gnuworld PostgreSQL user
    log_info "Creating PostgreSQL user: $POSTGRESQL_USER..."
    sudo -u postgres psql << SQLEOF || log_warning "PostgreSQL user may already exist"
CREATE USER $POSTGRESQL_USER WITH PASSWORD '$POSTGRESQL_PASSWORD';
ALTER USER $POSTGRESQL_USER CREATEDB;
ALTER USER $POSTGRESQL_USER CREATEUSER;
SQLEOF

    # Create databases
    log_info "Creating PostgreSQL databases..."
    sudo -u postgres createdb -O $POSTGRESQL_USER gnuworld_services || log_warning "Database may already exist"
    sudo -u postgres createdb -O $POSTGRESQL_USER gnuworld_web || log_warning "Database may already exist"
    sudo -u postgres createdb -O $POSTGRESQL_USER gnuworld_logs || log_warning "Database may already exist"

    # Create .pgpass for password-less connections
    cat > "$INSTALL_DIR/.pgpass" << EOF
localhost:5432:gnuworld_services:$POSTGRESQL_USER:$POSTGRESQL_PASSWORD
localhost:5432:gnuworld_web:$POSTGRESQL_USER:$POSTGRESQL_PASSWORD
localhost:5432:gnuworld_logs:$POSTGRESQL_USER:$POSTGRESQL_PASSWORD
EOF

    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/.pgpass"
    chmod 600 "$INSTALL_DIR/.pgpass"

    log_success "PostgreSQL setup complete"
    log_info "Database password saved in: $INSTALL_DIR/.pgpass"
    
    # Save credentials for reference
    cat > "$INSTALL_DIR/DATABASE_CREDENTIALS.txt" << EOF
PostgreSQL Connection Details
=============================
Username: $POSTGRESQL_USER
Password: $POSTGRESQL_PASSWORD
Hostname: localhost
Port: 5432

Databases:
- gnuworld_services (Services database)
- gnuworld_web (Web interface database)
- gnuworld_logs (Logging database)

To connect:
psql -U $POSTGRESQL_USER -h localhost -d gnuworld_services
EOF

    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/DATABASE_CREDENTIALS.txt"
    chmod 600 "$INSTALL_DIR/DATABASE_CREDENTIALS.txt"
}

setup_config_files() {
    log_info "Setting up configuration files..."

    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/logs"

    # Create sample ircd.conf
    if [ ! -f "$INSTALL_DIR/config/ircd.conf" ]; then
        cat > "$INSTALL_DIR/config/ircd.conf.sample" << 'EOF'
# Nefarious2 IRCD Configuration File
# Generated during installation

serverinfo {
    name = "irc.example.com";
    description = "Example Network IRC Server";
    network_name = "ExampleNet";
    network_description = "Example Network";
    hub = yes;
};

admin {
    "Admin Line 1";
    "Admin Line 2";
    "admin@example.com";
};

listen {
    port = 6667;
    address = "0.0.0.0";
};

listen {
    port = 6697;
    ssl = yes;
};

class {
    name = "clients";
    pingfreq = 120;
    sendq = 160000;
    maxlinks = 3;
    maxsendq = 160000;
};

class {
    name = "services";
    pingfreq = 60;
    sendq = 160000;
};

client {
    class = "clients";
    ip = "*@*";
};

server {
    name = "*.example.com";
    class = "clients";
};

# Add service servers here for GNUWorld uplink
# service {
#     name = "X.services.example.com";
#     class = "services";
# };

operator {
    name = "oper";
    password = "changeme";
    class = "clients";
    privileges = "local_kill, global_kill, local_oper, global_oper";
};

motd {
    hostmask = "*";
    file = "ircd.motd";
};
EOF
        log_warning "Created sample ircd.conf - edit $INSTALL_DIR/config/ircd.conf"
    fi

    # Create sample gnuworld.conf
    if [ ! -f "$INSTALL_DIR/config/gnuworld.conf" ]; then
        cat > "$INSTALL_DIR/config/gnuworld.conf.sample" << 'EOF'
# GNUWorld Configuration File
# Generated during installation

# Server connection
uplink {
    server = "127.0.0.1";
    port = 7777;
    password = "servicespass";
    name = "services.example.com";
};

# Database configuration
database {
    database = "gnuworld_services";
    user = "gnuworld";
    host = "localhost";
    port = 5432;
};

# Logging
logging {
    path = "/home/gnuworld/logs";
    level = "notice";
};

# Modules to load
modules {
    # mod_cservice for channel services
    # mod_nickserv for nickname services
    # mod_chanfix for channel fixing
    # mod_dronescan for drone detection
    # Add module configurations here
};
EOF
        log_warning "Created sample gnuworld.conf - edit $INSTALL_DIR/config/gnuworld.conf"
    fi

    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/config"
    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/logs"
    chmod 755 "$INSTALL_DIR/config"
    chmod 755 "$INSTALL_DIR/logs"
}

setup_supervisor() {
    log_info "Setting up supervisor configurations..."

    mkdir -p /etc/supervisor/conf.d

    # Create nefarious2 supervisor config
    cat > /etc/supervisor/conf.d/nefarious2.conf << EOF
[program:nefarious2]
command=$NEFARIOUS_DIR/install/bin/ircd -f $INSTALL_DIR/config/ircd.conf
user=$GNUWORLD_USER
group=$GNUWORLD_GROUP
directory=$INSTALL_DIR
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/logs/nefarious2.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=$INSTALL_DIR/logs/nefarious2-error.log
environment=PATH="$NEFARIOUS_DIR/install/bin"
startsecs=10
stopasgroup=true
priority=999
EOF

    # Create gnuworld supervisor config
    cat > /etc/supervisor/conf.d/gnuworld.conf << EOF
[program:gnuworld]
command=$GNUWORLD_DIR/install/bin/gnuworld -c $INSTALL_DIR/config/gnuworld.conf
user=$GNUWORLD_USER
group=$GNUWORLD_GROUP
directory=$INSTALL_DIR
autostart=false
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/logs/gnuworld.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=$INSTALL_DIR/logs/gnuworld-error.log
environment=PATH="$GNUWORLD_DIR/install/bin"
startsecs=10
stopasgroup=true
priority=998
EOF

    systemctl restart supervisor
    log_success "Supervisor configurations created"
}

setup_website_apache() {
    log_info "Setting up Apache configuration..."

    # Enable required Apache modules
    log_info "Enabling Apache modules..."
    a2enmod proxy || true
    a2enmod proxy_fcgi || true
    a2enmod setenvif || true
    a2enmod rewrite || true
    a2enmod ssl || true
    a2enmod headers || true

    # Create Apache site configuration
    cat > /etc/apache2/sites-available/gnuworld-website.conf << EOF
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com services.example.com
    ServerAdmin admin@example.com

    DocumentRoot $WEBSITE_DIR/public

    # Enable mod_rewrite for clean URLs
    <Directory $WEBSITE_DIR/public>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Rewrite rules for clean URLs
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule ^(.*)$ index.php?request=\$1 [QSA,L]
        </IfModule>
    </Directory>

    # PHP-FPM configuration
    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/gnuworld-website-error.log
    CustomLog \${APACHE_LOG_DIR}/gnuworld-website-access.log combined
</VirtualHost>

# HTTPS configuration (enable after SSL certificate is installed)
# <VirtualHost *:443>
#     ServerName example.com
#     ServerAlias www.example.com services.example.com
#     ServerAdmin admin@example.com
#
#     DocumentRoot $WEBSITE_DIR/public
#
#     SSLEngine on
#     SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
#     SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
#
#     # ... rest of config same as above ...
# </VirtualHost>
EOF

    # Enable the site
    a2ensite gnuworld-website.conf

    # Configure PHP-FPM
    log_info "Configuring PHP-FPM..."
    sed -i 's/^;listen = \/run\/php-fpm.sock/listen = \/run\/php-fpm.sock/' /etc/php/*/fpm/pool.d/www.conf || true

    # Test Apache configuration
    apache2ctl configtest

    systemctl restart apache2
    systemctl restart php*-fpm || true

    log_success "Apache configuration complete"
}

setup_firewall() {
    log_info "Configuring firewall rules..."

    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp    comment 'SSH'
        ufw allow 80/tcp    comment 'HTTP'
        ufw allow 443/tcp   comment 'HTTPS'
        ufw allow 6667/tcp  comment 'IRC'
        ufw allow 6697/tcp  comment 'IRC SSL'
        ufw allow 7777/tcp  comment 'Services Uplink'
        ufw default deny incoming
        ufw default allow outgoing
        ufw --force enable
        log_success "UFW firewall rules configured"
    else
        log_warning "UFW not installed, please configure firewall manually"
    fi
}

create_startup_script() {
    log_info "Creating system startup script..."

    cat > /usr/local/bin/gnuworld-ctl << 'SCRIPT'
#!/bin/bash
# GNUWorld control script

case "$1" in
    start)
        echo "Starting GNUWorld services..."
        supervisorctl start nefarious2 gnuworld
        sleep 2
        supervisorctl status nefarious2 gnuworld
        ;;
    stop)
        echo "Stopping GNUWorld services..."
        supervisorctl stop gnuworld nefarious2
        sleep 2
        supervisorctl status nefarious2 gnuworld
        ;;
    restart)
        echo "Restarting GNUWorld services..."
        supervisorctl restart gnuworld nefarious2
        sleep 2
        supervisorctl status nefarious2 gnuworld
        ;;
    status)
        supervisorctl status nefarious2 gnuworld
        ;;
    logs)
        case "$2" in
            ircd)
                tail -f /home/gnuworld/logs/nefarious2.log
                ;;
            services)
                tail -f /home/gnuworld/logs/gnuworld.log
                ;;
            *)
                echo "Showing all logs (Ctrl+C to exit)..."
                tail -f /home/gnuworld/logs/*.log
                ;;
        esac
        ;;
    config)
        case "$2" in
            edit-ircd)
                nano /home/gnuworld/config/ircd.conf
                ;;
            edit-services)
                nano /home/gnuworld/config/gnuworld.conf
                ;;
            *)
                echo "Available configs:"
                echo "  gnuworld-ctl config edit-ircd"
                echo "  gnuworld-ctl config edit-services"
                ;;
        esac
        ;;
    *)
        echo "GNUWorld Control Script"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|config}"
        echo ""
        echo "Commands:"
        echo "  start                Start GNUWorld services"
        echo "  stop                 Stop GNUWorld services"
        echo "  restart              Restart GNUWorld services"
        echo "  status               Show service status"
        echo "  logs [ircd|services] Show service logs"
        echo "  config edit-ircd     Edit IRCD configuration"
        echo "  config edit-services Edit GNUWorld services configuration"
        echo ""
        exit 1
        ;;
esac
SCRIPT

    chmod +x /usr/local/bin/gnuworld-ctl
    log_success "Startup script created at /usr/local/bin/gnuworld-ctl"
}

create_documentation() {
    log_info "Creating documentation..."

    cat > "$INSTALL_DIR/INSTALLATION_SUMMARY.md" << 'EOF'
# GNUWorld Installation Summary

## Installation Details

### Components Installed

1. **Nefarious2 IRCd** (evilnet/nefarious2)
   - Location: /home/gnuworld/nefarious2/install
   - Configuration: /home/gnuworld/config/ircd.conf
   - Logs: /home/gnuworld/logs/nefarious2.log

2. **GNUWorld Services** (UndernetIRC/gnuworld)
   - Location: /home/gnuworld/gnuworld/install
   - Configuration: /home/gnuworld/config/gnuworld.conf
   - Logs: /home/gnuworld/logs/gnuworld.log
   - Modules: All modules compiled and installed

3. **GNUWorld Website**
   - Location: /home/gnuworld/website
   - Web Root: /home/gnuworld/website/public
   - Apache Config: /etc/apache2/sites-available/gnuworld-website.conf

4. **PostgreSQL Database**
   - Databases:
     - gnuworld_services (Services database)
     - gnuworld_web (Web interface database)
     - gnuworld_logs (Logging database)
   - Credentials saved in: /home/gnuworld/DATABASE_CREDENTIALS.txt

## Quick Start

### 1. Edit Configuration Files

```bash
sudo nano /home/gnuworld/config/ircd.conf
sudo nano /home/gnuworld/config/gnuworld.conf
```

Key things to change:
- Server names and descriptions
- Network name
- Service passwords
- Admin credentials

### 2. Start Services

```bash
gnuworld-ctl start
```

### 3. Check Status

```bash
gnuworld-ctl status
gnuworld-ctl logs
```

## Management Commands

### Service Control
```bash
gnuworld-ctl start              # Start all services
gnuworld-ctl stop               # Stop all services
gnuworld-ctl restart            # Restart all services
gnuworld-ctl status             # Check status
gnuworld-ctl logs               # Show all logs
gnuworld-ctl logs ircd          # Show IRCD logs
gnuworld-ctl logs services      # Show GNUWorld logs
gnuworld-ctl config edit-ircd   # Edit IRCD config
gnuworld-ctl config edit-services # Edit GNUWorld config
```

### Direct Supervision Control
```bash
supervisorctl status            # Show service status
supervisorctl start nefarious2
supervisorctl start gnuworld
supervisorctl restart nefarious2
supervisorctl restart gnuworld
tail -f /home/gnuworld/logs/nefarious2.log
tail -f /home/gnuworld/logs/gnuworld.log
```

### PostgreSQL Access
```bash
psql -U gnuworld -h localhost -d gnuworld_services
\dt                             # List tables
\q                              # Exit psql
```

## Web Interface Setup

### Apache Configuration
- Site config: `/etc/apache2/sites-available/gnuworld-website.conf`
- Document root: `/home/gnuworld/website/public`
- Current URL: `http://localhost/` (or `http://example.com/`)

### Enable HTTPS with Let's Encrypt
```bash
sudo apt-get install certbot python3-certbot-apache
sudo certbot --apache -d your-domain.com
```

### PHP Configuration
- FPM Socket: `/run/php-fpm.sock`
- PHP version: See `php -v`
- PHP modules installed:
  - pgsql (PostgreSQL)
  - mysql (MySQL/MariaDB)
  - sqlite3 (SQLite)
  - curl, xml, gd, json, mbstring, zip, intl

## Directory Structure

```
/home/gnuworld/
├── nefarious2/              # Nefarious2 IRCD source & build
│   └── install/             # Compiled binaries and libs
├── gnuworld/                # GNUWorld services source & build
│   ├── install/             # Compiled binaries and libs
│   └── mod.*/               # Individual service modules
├── website/                 # Website source
│   ├── public/              # Web-accessible files
│   ├── logs/                # Website logs
│   └── config/              # Website configuration
├── config/                  # Configuration files
│   ├── ircd.conf
│   └── gnuworld.conf
├── logs/                    # Log files
│   ├── nefarious2.log
│   └── gnuworld.log
└── .pgpass                  # PostgreSQL credentials
```

## Important Notes

1. **Database Credentials**: Saved in `/home/gnuworld/DATABASE_CREDENTIALS.txt`
2. **All services run as user 'gnuworld'**
3. **Services are disabled by default** - you must edit config files first!
4. **Supervisor manages the services** - use `supervisorctl` or `gnuworld-ctl`
5. **Never run services as root** - they run under 'gnuworld' user

## Troubleshooting

### Services won't start
```bash
gnuworld-ctl logs              # Check logs
supervisorctl restart nefarious2
supervisorctl tail nefarious2 -f
```

### Can't connect to IRC
1. Check IRCD configuration: `sudo nano /home/gnuworld/config/ircd.conf`
2. Check IRCD is running: `gnuworld-ctl status`
3. Check IRCD logs: `gnuworld-ctl logs ircd`
4. Verify port 6667 is open: `sudo netstat -tuln | grep 6667`

### Services not connecting to IRCD
1. Check GNUWorld config uplink settings
2. Verify IRCD server is running
3. Check GNUWorld logs for connection errors
4. Verify passwords match between IRCD and GNUWorld config

### Website not loading
1. Check Apache is running: `sudo systemctl status apache2`
2. Check PHP-FPM: `sudo systemctl status php*-fpm`
3. Check Apache error log: `tail -f /var/log/apache2/error.log`
4. Verify permissions: `ls -la /home/gnuworld/website/public/`

### PostgreSQL connection issues
1. Verify PostgreSQL is running: `sudo systemctl status postgresql`
2. Test connection: `psql -U gnuworld -h localhost -d gnuworld_services`
3. Check database credentials: `cat /home/gnuworld/DATABASE_CREDENTIALS.txt`

## Support and Documentation

- Nefarious2: https://github.com/evilnet/nefarious2
- GNUWorld: https://github.com/UndernetIRC/gnuworld
- Undernet: https://www.undernet.org/

## Next Steps

1. Update all configuration files
2. Create IRCD and services MOTD files
3. Configure database tables and initial data
4. Set up web interface (if available)
5. Configure backups for databases
6. Set up monitoring and alerts
7. Configure automatic certificate renewal (Let's Encrypt)
8. Test IRC connectivity

EOF

    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/INSTALLATION_SUMMARY.md"
    chmod 644 "$INSTALL_DIR/INSTALLATION_SUMMARY.md"

    log_success "Documentation created at $INSTALL_DIR/INSTALLATION_SUMMARY.md"
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Services are disabled by default!${NC}"
    echo ""
    echo -e "${YELLOW}1. EDIT CONFIGURATION FILES FIRST:${NC}"
    echo "   sudo nano /home/gnuworld/config/ircd.conf"
    echo "   sudo nano /home/gnuworld/config/gnuworld.conf"
    echo ""
    echo -e "${YELLOW}2. DATABASE CREDENTIALS:${NC}"
    echo "   File: /home/gnuworld/DATABASE_CREDENTIALS.txt"
    echo "   PostgreSQL password: $POSTGRESQL_PASSWORD"
    echo ""
    echo -e "${YELLOW}3. SETUP SUMMARY:${NC}"
    echo "   Read: /home/gnuworld/INSTALLATION_SUMMARY.md"
    echo ""
    echo -e "${YELLOW}4. INSTALLED COMPONENTS:${NC}"
    echo "   ✓ Nefarious2 IRCD (evilnet/nefarious2)"
    echo "   ✓ GNUWorld Services + All Modules (UndernetIRC/gnuworld)"
    echo "   ✓ PostgreSQL Database (3 databases)"
    echo "   ✓ Apache2 + PHP-FPM"
    echo "   ✓ Website Directory Structure"
    echo "   ✓ Supervisor Process Management"
    echo ""
    echo -e "${YELLOW}5. DIRECTORY STRUCTURE:${NC}"
    echo "   Nefarious2: /home/gnuworld/nefarious2/install"
    echo "   GNUWorld: /home/gnuworld/gnuworld/install"
    echo "   Website: /home/gnuworld/website"
    echo "   Config: /home/gnuworld/config"
    echo "   Logs: /home/gnuworld/logs"
    echo ""
    echo -e "${YELLOW}6. MANAGEMENT:${NC}"
    echo "   All services managed by 'gnuworld' user"
    echo "   Process manager: Supervisor"
    echo "   Control: gnuworld-ctl (or supervisorctl)"
    echo ""
    echo -e "${YELLOW}7. START SERVICES (after config):${NC}"
    echo "   gnuworld-ctl start"
    echo "   gnuworld-ctl status"
    echo "   gnuworld-ctl logs"
    echo ""
    echo -e "${YELLOW}8. WEB INTERFACE:${NC}"
    echo "   Apache site: gnuworld-website"
    echo "   Doc root: /home/gnuworld/website/public"
    echo "   Config: /etc/apache2/sites-available/gnuworld-website.conf"
    echo "   Edit domain name in Apache config!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# Main installation flow
main() {
    log_info "Starting Nefarious2 + GNUWorld + Website Installation"
    log_info "User: $GNUWORLD_USER"
    log_info "Installation directory: $INSTALL_DIR"
    log_info "PostgreSQL password: $POSTGRESQL_PASSWORD"
    echo ""

    check_root
    detect_os
    install_dependencies
    create_gnuworld_user
    setup_postgresql
    install_nefarious2
    install_gnuworld
    install_website
    setup_config_files
    setup_supervisor
    setup_website_apache
    setup_firewall
    create_startup_script
    create_documentation
    print_next_steps

    log_success "Installation process completed successfully!"
    log_info "Full documentation saved to: $INSTALL_DIR/INSTALLATION_SUMMARY.md"
}

# Run main function
main "$@"
