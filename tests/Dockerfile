FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages (minimally to allow the installer to run its checks and commands)
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates gnupg sudo openssl build-essential autoconf automake autotools-dev libtool pkg-config \
    libssl-dev zlib1g-dev libcurl4-openssl-dev libxml2-dev libboost-all-dev libpq-dev postgresql-client apache2 php php-cli php-fpm php-pgsql php-curl php-xml php-gd php-mbstring php-json php-zip php-intl libapache2-mod-php python3 python3-pip sqlite3 tcl8.6 nano vim htop tmux \
  && rm -rf /var/lib/apt/lists/*

# Add a mock systemctl to avoid failures inside the container (no-op)
RUN printf '#!/bin/bash\n echo "[mock] systemctl $@"\n exit 0\n' > /usr/bin/systemctl \
  && chmod +x /usr/bin/systemctl

WORKDIR /opt/gnuworld

# Copy repository content into the image
COPY . /opt/gnuworld

# Ensure installer is executable
RUN chmod +x /opt/gnuworld/install.sh || true

ENTRYPOINT ["/bin/bash"]