#!/bin/bash
# One-time setup of a fresh Ubuntu 24.04 server for Premium Cars (stage 3 of the launch plan). Run as the
# provider's user with sudo, from a copy of this file:
#   scp scripts/server-setup.sh ubuntu@<IP>:     then on the server:   sudo bash server-setup.sh
# Safe to run again. What it does:
#   - updates the system and turns on automatic security updates
#   - installs Docker Engine + the compose plugin (Docker's own apt repository), git, fail2ban
#   - creates the user "deploy" (Docker, owns /opt/premium-cars) with the same SSH keys as the login user,
#     plus a key for GitHub Actions if DEPLOY_PUBKEY is set, and a read-only GitHub key to clone premium-cars-infra
#   - SSH: keys only, no passwords, no root login (only once a key is in place, so you cannot lock yourself out)
#   - firewall: only 22, 80 and 443 open
#   - 2 GB swap (headless Chromium during imports needs headroom)
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
LOGIN_USER=${SUDO_USER:-ubuntu}
DEPLOY_USER=deploy
APP_DIR=/opt/premium-cars
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "==> $*"; }

step "System updates"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confold upgrade
apt-get -y -q install ca-certificates curl gnupg git ufw fail2ban unattended-upgrades
timedatectl set-timezone UTC

step "Automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

step "Docker Engine"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
# keep container logs small
if [ ! -f /etc/docker/daemon.json ]; then
  echo '{"log-driver": "local", "log-opts": {"max-size": "20m", "max-file": "5"}}' > /etc/docker/daemon.json
  systemctl restart docker
fi

step "User $DEPLOY_USER"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
usermod -aG docker "$LOGIN_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /home/$DEPLOY_USER/.ssh
keys=/home/$DEPLOY_USER/.ssh/authorized_keys
touch "$keys"
if [ -s "/home/$LOGIN_USER/.ssh/authorized_keys" ]; then
  cat "/home/$LOGIN_USER/.ssh/authorized_keys" >> "$keys"
fi
if [ -n "${DEPLOY_PUBKEY:-}" ]; then
  echo "$DEPLOY_PUBKEY" >> "$keys"
fi
sort -u "$keys" -o "$keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "$keys"
chmod 600 "$keys"

# read-only key for cloning the private premium-cars-infra repo (added as a deploy key on GitHub)
gh_key=/home/$DEPLOY_USER/.ssh/github_infra
if [ ! -f "$gh_key" ]; then
  sudo -u "$DEPLOY_USER" ssh-keygen -q -t ed25519 -N "" -C "premium-cars-server" -f "$gh_key"
  cat > /home/$DEPLOY_USER/.ssh/config <<EOF
Host github.com
  IdentityFile $gh_key
  IdentitiesOnly yes
EOF
  chown "$DEPLOY_USER:$DEPLOY_USER" /home/$DEPLOY_USER/.ssh/config
fi
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"

step "SSH: keys only"
if [ -s "$keys" ]; then
  cat > /etc/ssh/sshd_config.d/10-premium-cars.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
  systemctl reload ssh
else
  echo "!! no SSH key in authorized_keys: password login left on. Add your key and run this again."
fi

step "Firewall"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
ufw --force enable >/dev/null
ufw status

step "fail2ban (SSH)"
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

step "Swap"
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
swapon --show

cat <<EOF

Done. Next (README "Production" -> "First deploy"):
  1. GitHub -> premium-cars-infra -> Settings -> Deploy keys -> Add (read-only), this key:
     $(cat "$gh_key.pub")
  2. log in as $DEPLOY_USER (ssh $DEPLOY_USER@<IP>) and:
     git clone git@github.com:ilutov90/premium-cars-infra.git $APP_DIR/premium-cars-infra
EOF
