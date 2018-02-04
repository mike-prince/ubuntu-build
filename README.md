# Ubuntu Build

A shell scripts to quickly setup Ubuntu Server.  Intended to be used with Digital Ocean Droplets so omits some things such as setting the hostname, which their system takes care of.  I use this as is for test servers using the $5 Droplet and build upon it for anything more demanding, so don't forget to adjust swap for anything bigger.

## Features

- Secure SSH
- Enable UFW (allowing 22/tcp, 80/tcp, 443/tcp)
- Upgrade system
- Create swap (size = 1Gb, swappiness = 10)
- Create user
- Fail2Ban
- MariaDB
- Nginx (with get-real-ip for CloudFlare and ssl params)
- PHP-FPM
- Git
- Cerbot
- JpegOptim & OptiPng

## Installation

### Remote Install

Run the following to run the install scripts directly from Github

```
bash <(curl -s https://raw.githubusercontent.com/mikeprince13/ubuntu-build/master/ubuntu-setup.sh)
```

### Local Install

- Download this repo
- Uncomment the following in ubuntu-setup.sh

```
#URL=`dirname -- "$0/config"`
```
