#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute com sudo: sudo ./bootstrap.sh"
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl docker.io docker-compose-v2 rsync unattended-upgrades ufw

if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=20' > /etc/sysctl.d/99-erp-qa.conf
sysctl --system >/dev/null

install -d -m 0755 /etc/ssh/sshd_config.d /etc/systemd/journald.conf.d
cat > /etc/ssh/sshd_config.d/99-erp-qa.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
cat > /etc/systemd/journald.conf.d/99-erp-qa.conf <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF

sshd -t
systemctl restart ssh
systemctl restart systemd-journald
systemctl enable --now docker

admin_user="${SUDO_USER:-ubuntu}"
if id "$admin_user" >/dev/null 2>&1; then
  usermod -aG docker "$admin_user"
fi

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

install -d -m 0750 -o "$admin_user" -g "$admin_user" /opt/erp-qa/backups
echo "Bootstrap concluído. Saia e entre novamente no SSH para aplicar o grupo docker."
