  #!/bin/bash

# Exit on error
set -e

# Output a horizontal line
divider() {
  CHAR=`printf '_%.0s' {1..100}`
  DIV="${DGREY}${CHAR}${NOCOLOR}"

  printf "\n"
  printf "${DIV}\n"
  printf "${DIV}\n"
  printf "${DIV}\n"
  printf "\n"
}

# Output a notice / section title
notice() {
  divider
  printf "\n${RED}$@${NOCOLOR}\n"
}

main() {

  # Vars
  readonly ARGS="$@"
  readonly URL="https://raw.githubusercontent.com/mikeprince13/ubuntu-build/master/config"

  readonly DGREY="\033[0;30m"
  readonly RED="\033[0;31m"
  readonly NOCOLOR="\033[0m"

  # Prompt user for var data
  notice USER
  read -p 'Username: ' uname
  read -s -p 'Password: ' pword

  notice MYSQL ROOT
  read -s -p 'MySQL root password: ' dbpword

  notice MYSQL ADMIN
  read -p 'MySQL admin username: ' dbuser
  read -s -p 'MySQL admin password: ' dbuserpword
  divider

  # Secure SSH
  notice SECURING SSH
  sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

  # Enable UFW, allow SSH
  notice ENABLING UFW
  ufw allow 22/tcp
  ufw --force enable

  # Set locale
  notice SETTING LOCALE
  locale-gen en_GB.UTF-8
  printf 'LANG="en_GB.UTF-8"' > /etc/default/locale
  . /etc/default/locale

  # Full upgrade
  notice UPGRADING
  apt update
  apt full-upgrade -y --force-yes -qq
  apt autoremove -y
  apt-get autoclean

  # Enable Swap, size = 1Gb, swappiness = 10
  notice CREATING SWAP
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
  echo "vm.swappiness=10" >> /etc/sysctl.conf

  # Create user account
  notice CREATING USER ACCOUNT
  adduser --disabled-password --gecos "" $uname
  echo "${uname}:${pword}" | sudo chpasswd
  usermod -aG sudo $uname
  usermod -aG www-data $uname
  mkdir /home/$uname/.ssh
  chmod 700 /home/$uname/.ssh
  mv /root/.ssh/authorized_keys /home/$uname/.ssh
  chown -R $uname:$uname /home/$uname/.ssh

  # Install Fail2Ban
  notice INSTALLING FAIL2BAN
  apt install -y fail2ban
  curl ${URL}/fail2ban.conf -o /etc/fail2ban/jail.local

  # Install MariaDB
  notice INSTALLING MARIADB
  apt install -y mariadb-server
  # Replicate mysql_secure_installation
  echo "Securing MySQL"
  mysql -e "UPDATE mysql.user SET Password=PASSWORD('${dbpword}') WHERE User='root';"
  mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -e "DELETE FROM mysql.user WHERE User='';"
  mysql -e "DROP DATABASE IF EXISTS test;"
  mysql -e "FLUSH PRIVILEGES;"
  mysql -e "CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbuserpword}';"
  mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${dbuser}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  # Install Nginx
  notice INSTALLING NGINX
  apt install -y nginx
  ufw allow 80/tcp
  ufw allow 443/tcp
  sed -i 's/# server_tokens off/server_tokens off/' /etc/nginx/nginx.conf
  echo 'fastcgi_param HTTP_PROXY "";' >> /etc/nginx/fastcgi.conf;
  curl ${URL}/nginx-sites.conf -o /etc/nginx/sites-available/default-ssl.conf
  curl ${URL}/default-index.html -o /var/www/html/index.html
  mkdir /srv/www

  # Get real IP from CloudFlare
  notice CONFIGURING NGINX FOR CLOUDFLARE
  touch /etc/nginx/snippets/cloudflare.conf
  bash -c "echo '# CloudFlare IPs' > /etc/nginx/snippets/cloudflare.conf"
  bash -c "curl https://www.cloudflare.com/ips-v4 >> /etc/nginx/snippets/cloudflare.conf"
  bash -c "echo '' >> /etc/nginx/snippets/cloudflare.conf"
  bash -c "curl https://www.cloudflare.com/ips-v6 >> /etc/nginx/snippets/cloudflare.conf"
  sed -i '/^[0-9]/s/^/set_real_ip_from /g' /etc/nginx/snippets/cloudflare.conf
  sed -i '/[0-9]$/ s/$/;/g' /etc/nginx/snippets/cloudflare.conf
  bash -c "echo 'real_ip_header CF-Connecting-IP;' >> /etc/nginx/snippets/cloudflare.conf"

  # Install PHP
  notice INSTALLING PHP
  add-apt-repository -y ppa:ondrej/php
  apt update
  apt install -y php7.1-fpm php7.1-curl php7.1-gd php7.1-json php7.1-mbstring php7.1-mcrypt php7.1-mysql php7.1-xml php7.1-zip

  # Install Sendmail
  notice INSTALLING SENDMAIL
  apt install -y sendmail

  # Git
  notice INSTALLING GIT
  apt install -y git git-core
  mkdir /srv/git
  chown $uname:$uname /srv/git

  # Install certbot
  notice INSTALLING CERTBOT
  add-apt-repository ppa:certbot/certbot
  apt update
  apt install -y python-certbot-nginx
  curl ${URL}/certbot-renew.cron -o /etc/cron.daily/cerbot-renew
  chmod +x /etc/cron.daily/cerbot-renew

  # Setup SSL
  notice CONFIGURING SSL CERTS
  openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
  curl ${URL}/ssl-params.conf -o /etc/nginx/snippets/ssl-params.conf

  # Install image optimizers
  apt install -y jpegoptim
  apt install -y optipng

  # Final upgrade
  apt upgrade -y

  # Truncate logs
  find /var/log -type f -exec truncate -c -s0 {} \;

  notice SETUP COMPLETE
}

main
