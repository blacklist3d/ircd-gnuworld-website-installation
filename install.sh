#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/home/gnuworld}"
NEFARIOUS_DIR="${NEFARIOUS_DIR:-$INSTALL_DIR/nefarious2}"
GNUWORLD_DIR="${GNUWORLD_DIR:-$INSTALL_DIR/gnuworld}"
WEBSITE_DIR="${WEBSITE_DIR:-$INSTALL_DIR/website}"

GNUWORLD_USER="${GNUWORLD_USER:-gnuworld}"
GNUWORLD_GROUP="${GNUWORLD_GROUP:-gnuworld}"

PGUSER="${PGUSER:-gnuworld}"
PGPASSWORD="${PGPASSWORD:-$(openssl rand -base64 24 | tr -d '\n')}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "Run this script as root: sudo bash install.sh"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
    else
        log_error "Unable to detect OS release"
    fi

    case "${ID:-}" in
        ubuntu|debian) ;;
        *) log_error "Unsupported OS: ${ID:-unknown}. This script supports Ubuntu and Debian." ;;
    esac

    log_ok "Detected OS: ${ID} ${VERSION_ID:-}"
}

install_packages() {
    log_info "Updating apt and installing packages..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential autoconf automake autotools-dev libtool pkg-config git curl wget ca-certificates \
        libssl-dev zlib1g-dev libcurl4-openssl-dev libxml2-dev libboost-all-dev libpq-dev \
        postgresql postgresql-contrib postgresql-client apache2 apache2-utils php php-cli php-fpm \
        php-pgsql php-curl php-xml php-gd php-mbstring php-json php-zip php-intl libapache2-mod-php \
        python3 python3-pip python3-venv supervisor sqlite3 libsqlite3-dev \
        tcl8.6 tcl8.6-dev nano vim htop tmux openssl sudo

    log_ok "Packages installed"
}

create_gnuworld_user() {
    if ! id "$GNUWORLD_USER" >/dev/null 2>&1; then
        log_info "Creating user/group: $GNUWORLD_USER"
        groupadd "$GNUWORLD_GROUP" || true
        useradd -r -m -g "$GNUWORLD_GROUP" -d "$INSTALL_DIR" -s /bin/bash "$GNUWORLD_USER"
    else
        log_warn "User $GNUWORLD_USER already exists"
    fi

    mkdir -p "$INSTALL_DIR"
    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"

    if [[ ! -f /etc/sudoers.d/gnuworld ]]; then
        echo "${GNUWORLD_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/gnuworld
        chmod 0440 /etc/sudoers.d/gnuworld
    fi

    cat >> /etc/security/limits.conf <<EOF

# GNUWorld service limits
${GNUWORLD_USER} soft nofile 65535
${GNUWORLD_USER} hard nofile 65535
${GNUWORLD_USER} soft nproc 32768
${GNUWORLD_USER} hard nproc 32768
EOF

    log_ok "User setup complete"
}

clone_repos() {
    mkdir -p "$INSTALL_DIR"

    if [[ ! -d "$NEFARIOUS_DIR/.git" ]]; then
        log_info "Cloning Nefarious2 from evilnet/nefarious2"
        git clone https://github.com/evilnet/nefarious2.git "$NEFARIOUS_DIR"
    else
        log_warn "Nefarious2 already exists; updating"
        git -C "$NEFARIOUS_DIR" pull --ff-only || true
    fi

    if [[ ! -d "$GNUWORLD_DIR/.git" ]]; then
        log_info "Cloning GNUWorld from UndernetIRC/gnuworld"
        git clone https://github.com/UndernetIRC/gnuworld.git "$GNUWORLD_DIR"
    else
        log_warn "GNUWorld already exists; updating"
        git -C "$GNUWORLD_DIR" pull --ff-only || true
    fi

    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR"
    log_ok "Repositories ready"
}

build_nefarious2() {
    log_info "Configuring and building Nefarious2..."
    cd "$NEFARIOUS_DIR"

    if [[ ! -f configure ]]; then
        autoreconf -fi
    fi

    ./configure --prefix="$NEFARIOUS_DIR/install" --enable-debug
    make -j"$(nproc)"
    make install

    log_ok "Nefarious2 installed under $NEFARIOUS_DIR/install"
}

build_gnuworld() {
    log_info "Configuring and building GNUWorld..."
    cd "$GNUWORLD_DIR"

    if [[ ! -f configure ]]; then
        autoreconf -fi
    fi

    ./configure --prefix="$GNUWORLD_DIR/install" --enable-modules --with-pgsql
    make -j"$(nproc)"
    make install

    log_ok "GNUWorld installed under $GNUWORLD_DIR/install"
}

configure_postgresql() {
    log_info "Preparing PostgreSQL..."
    systemctl enable postgresql || true
    systemctl restart postgresql || true

    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${PGUSER}'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER ${PGUSER} WITH PASSWORD '${PGPASSWORD}';"

    for db in gnuworld_services gnuworld_web gnuworld_logs; do
        sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 || \
            sudo -u postgres createdb -O "$PGUSER" "$db"
    done

    cat > "$INSTALL_DIR/.pgpass" <<EOF
$PGHOST:$PGPORT:gnuworld_services:$PGUSER:$PGPASSWORD
$PGHOST:$PGPORT:gnuworld_web:$PGUSER:$PGPASSWORD
$PGHOST:$PGPORT:gnuworld_logs:$PGUSER:$PGPASSWORD
EOF
    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/.pgpass"
    chmod 600 "$INSTALL_DIR/.pgpass"

    cat > "$INSTALL_DIR/DATABASE_CREDENTIALS.txt" <<EOF
GNUWorld PostgreSQL credentials
=============================
User: $PGUSER
Password: $PGPASSWORD
Host: $PGHOST
Port: $PGPORT

Databases:
  - gnuworld_services
  - gnuworld_web
  - gnuworld_logs
EOF
    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/DATABASE_CREDENTIALS.txt"
    chmod 600 "$INSTALL_DIR/DATABASE_CREDENTIALS.txt"

    log_ok "PostgreSQL configured"
}

prepare_config_dir() {
    mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/logs"
    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/config" "$INSTALL_DIR/logs"

    if [[ ! -f "$INSTALL_DIR/config/ircd.conf" ]]; then
        cat > "$INSTALL_DIR/config/ircd.conf" <<'EOF'
# Example Nefarious2 config
# Replace with your real network settings.

serverinfo {
    name = "irc.example.com";
    description = "Example IRC Network";
    network_name = "ExampleNet";
    hub = yes;
};

admin {
    "Administrator";
    "Example IRC Network";
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
    maxlinks = 50;
};

operator {
    name = "oper";
    password = "change_me";
    class = "clients";
    privileges = "local_kill, global_kill, local_oper, global_oper";
};
EOF
    fi

    if [[ ! -f "$INSTALL_DIR/config/gnuworld.conf" ]]; then
        cat > "$INSTALL_DIR/config/gnuworld.conf" <<EOF
# Example GNUWorld configuration

uplink {
    server = "127.0.0.1";
    port = 6667;
    password = "changeme";
};

database {
    type = "postgres";
    host = "$PGHOST";
    port = $PGPORT;
    dbname = "gnuworld_services";
    user = "$PGUSER";
    password = "$PGPASSWORD";
};

logging {
    path = "$INSTALL_DIR/logs";
    level = "notice";
};
EOF
    fi

    chown "$GNUWORLD_USER:$GNUWORLD_GROUP" "$INSTALL_DIR/config/ircd.conf" "$INSTALL_DIR/config/gnuworld.conf"
    chmod 600 "$INSTALL_DIR/config/ircd.conf" "$INSTALL_DIR/config/gnuworld.conf"
    log_ok "Config files created"
}

setup_supervisor() {
    log_info "Creating supervisor configs..."
    mkdir -p /etc/supervisor/conf.d

    cat > /etc/supervisor/conf.d/nefarious2.conf <<EOF
[program:nefarious2]
command=$NEFARIOUS_DIR/install/bin/ircd -f $INSTALL_DIR/config/ircd.conf
user=$GNUWORLD_USER
group=$GNUWORLD_GROUP
directory=$INSTALL_DIR
autostart=false
autorestart=true
stderr_logfile=$INSTALL_DIR/logs/nefarious2.err
stdout_logfile=$INSTALL_DIR/logs/nefarious2.log
startsecs=5
stopasgroup=true
EOF

    cat > /etc/supervisor/conf.d/gnuworld.conf <<EOF
[program:gnuworld]
command=$GNUWORLD_DIR/install/bin/gnuworld -c $INSTALL_DIR/config/gnuworld.conf
user=$GNUWORLD_USER
group=$GNUWORLD_GROUP
directory=$INSTALL_DIR
autostart=false
autorestart=true
stderr_logfile=$INSTALL_DIR/logs/gnuworld.err
stdout_logfile=$INSTALL_DIR/logs/gnuworld.log
startsecs=5
stopasgroup=true
EOF

    systemctl enable supervisor || true
    systemctl restart supervisor || true
    log_ok "Supervisor configured"
}

setup_apache() {
    log_info "Configuring Apache/PHP..."
    mkdir -p "$WEBSITE_DIR/public" "$WEBSITE_DIR/logs"

    cat > "$WEBSITE_DIR/public/index.php" <<'PHP'
<?php
phpinfo();
PHP

    cat > /etc/apache2/sites-available/gnuworld-website.conf <<EOF
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

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php-fpm.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog $WEBSITE_DIR/logs/apache_error.log
    CustomLog $WEBSITE_DIR/logs/apache_access.log combined
</VirtualHost>
EOF

    chown -R "$GNUWORLD_USER:$GNUWORLD_GROUP" "$WEBSITE_DIR"

    a2enmod rewrite proxy proxy_fcgi ssl headers || true
    a2dissite 000-default.conf || true
    a2ensite gnuworld-website.conf || true

    apache2ctl configtest
    systemctl restart apache2 || true
    systemctl restart php8.2-fpm 2>/dev/null || true
    systemctl restart php8.1-fpm 2>/dev/null || true
    systemctl restart php-fpm 2>/dev/null || true

    log_ok "Apache configured"
}

create_control_script() {
    cat > /usr/local/bin/gnuworld-ctl <<'SCRIPT'
#!/bin/bash

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
        tail -f /home/gnuworld/logs/*.log
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
SCRIPT

    chmod 755 /usr/local/bin/gnuworld-ctl
    log_ok "Control script installed: /usr/local/bin/gnuworld-ctl"
}

print_summary() {
    echo
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}Installation complete${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo
    echo -e "${YELLOW}Installed:${NC}"
    echo "  - Nefarious2: $NEFARIOUS_DIR/install"
    echo "  - GNUWorld:   $GNUWORLD_DIR/install"
    echo "  - Website:    $WEBSITE_DIR"
    echo "  - PostgreSQL: configured"
    echo "  - Apache/PHP: configured"
    echo
    echo -e "${YELLOW}Important files:${NC}"
    echo "  - IRCD config:       $INSTALL_DIR/config/ircd.conf"
    echo "  - GNUWorld config:   $INSTALL_DIR/config/gnuworld.conf"
    echo "  - DB credentials:    $INSTALL_DIR/DATABASE_CREDENTIALS.txt"
    echo "  - .pgpass:           $INSTALL_DIR/.pgpass"
    echo
    echo -e "${YELLOW}Service control:${NC}"
    echo "  - /usr/local/bin/gnuworld-ctl start|stop|restart|status|logs"
    echo "  - supervisorctl status"
    echo
    echo -e "${YELLOW}Before starting services:${NC}"
    echo "  - Edit $INSTALL_DIR/config/ircd.conf"
    echo "  - Edit $INSTALL_DIR/config/gnuworld.conf"
    echo "  - Check PostgreSQL credentials in $INSTALL_DIR/DATABASE_CREDENTIALS.txt"
    echo
}

main() {
    require_root
    detect_os
    install_packages
    create_gnuworld_user
    clone_repos
    build_nefarious2
    build_gnuworld
    configure_postgresql
    prepare_config_dir
    setup_supervisor
    setup_apache
    create_control_script
    print_summary
}

main "$@"
