  #!/bin/bash

# Exit on error
set -e

main() {

  # Vars
  readonly ARGS="$@"
  readonly SCRIPTDIR=`dirname -- "$0"`

  # Prompt user for var data
  echo "**********************************************************************"
  echo "New user:"
  read -p 'Username: ' uname
  read -s -p 'Password: ' pword
  echo "\n"
  echo "MySQL Root user:"
  read -p 'MySQL root password: ' dbpword
  echo "\n"
  echo "MySQL Admin user:"
  read -p 'MySQL admin username: ' dbuser
  read -p 'MySQL admin password: ' dbuserpword
  echo "**********************************************************************"


  # Secure SSH
  sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
  sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

  # Enable UFW, allow SSH
  ufw allow 22/tcp
  ufw --force enable

  # Full upgrade
  apt update
  apt full-upgrade -y
  apt autoremove -y
  apt-get autoclean

  # Enable Swap, size = 1Gb, swappiness = 10
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
  echo "vm.swappiness=10" >> /etc/sysctl.conf

  # Set locale
  update-locale LANG=en_GB.UTF-8

  # Create user account
  adduser --disabled-password --gecos "" $uname
  echo "${uname}:${pword}" | sudo chpasswd
  usermod -aG sudo $uname
  usermod -aG www-data $uname
  mkdir /home/$uname/.ssh
  chmod 700 /home/$uname/.ssh
  mv /root/.ssh/authorized_keys /home/$uname/.ssh
  chown -R $uname:$uname /home/$uname/.ssh

  # Install Fail2Ban
  apt install -y fail2ban
  cp $SCRIPTDIR/config/fail2ban.conf /etc/fail2ban/jail.local

  # Install MariaDB
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
  apt install -y nginx
  ufw allow 80/tcp
  ufw allow 443/tcp
  sed -i 's/# server_tokens off/server_tokens off/' /etc/nginx/nginx.conf
  echo 'fastcgi_param HTTP_PROXY "";' >> /etc/nginx/fastcgi.conf;
  cp $SCRIPTDIR/config/nginx-sites.conf /etc/nginx/sites-available/default-ssl.conf
  cp $SCRIPTDIR/config/default-index.html /var/www/html/index.html
  mkdir /srv/www

  # Get real IP from CloudFlare
  touch /etc/nginx/snippets/cloudflare.conf
  bash -c "echo '# CloudFlare IPs' > /etc/nginx/snippets/cloudflare.conf"
  bash -c "curl https://www.cloudflare.com/ips-v4 >> /etc/nginx/snippets/cloudflare.conf"
  bash -c "echo '' >> /etc/nginx/snippets/cloudflare.conf"
  bash -c "curl https://www.cloudflare.com/ips-v6 >> /etc/nginx/snippets/cloudflare.conf"
  sed -i '/^[0-9]/s/^/set_real_ip_from /g' /etc/nginx/snippets/cloudflare.conf
  sed -i '/[0-9]$/ s/$/;/g' /etc/nginx/snippets/cloudflare.conf
  bash -c "echo 'real_ip_header CF-Connecting-IP;' >> /etc/nginx/snippets/cloudflare.conf"

  # Install PHP
  add-apt-repository -y ppa:ondrej/php
  apt update
  apt install -y php7.1-fpm php7.1-curl php7.1-gd php7.1-json php7.1-mbstring php7.1-mcrypt php7.1-mysql php7.1-xml php7.1-zip

  # Install Sendmail
  apt install -y sendmail

  # Git
  apt install -y git git-core
  mkdir /srv/git
  chown $uname:$uname /srv/git

  # Install certbot
  add-apt-repository ppa:certbot/certbot
  apt update
  apt install -y python-certbot-nginx
  cp $SCRIPTDIR/config/certbot-renew.cron /etc/cron.daily/cerbot-renew
  chmod +x /etc/cron.daily/cerbot-renew

  # Setup SSL
  openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
  cp $SCRIPTDIR/config/ssl-params.conf /etc/nginx/snippets/ssl-params.conf

  # Install image optimizers
  apt install -y jpegoptim
  apt install -y optipng

  # Final upgrade
  apt upgrade -y

  # Truncate logs
  find /var/log -type f -exec truncate -c -s0 {} \;
}

main
