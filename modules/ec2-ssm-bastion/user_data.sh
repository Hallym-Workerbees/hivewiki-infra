#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y

apt-get install -y apt-transport-https ca-certificates curl gnupg unzip

# kubectl
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
    >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl

# OpenTofu
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://get.opentofu.org/opentofu.gpg | tee /etc/apt/keyrings/opentofu.gpg >/dev/null
curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | gpg --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg
chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg

cat >/etc/apt/sources.list.d/opentofu.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF

apt-get update
apt-get install -y tofu

ARCH="$(uname -m)"

case "$ARCH" in
x86_64)
    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    ;;
aarch64 | arm64)
    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    ;;
*)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

curl -fsSL "$AWSCLI_URL" -o "awscliv2.zip"
unzip -o awscliv2.zip
./aws/install

# SSM Agent
snap install amazon-ssm-agent --classic || true
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service || true
systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service || true

# Shell
curl -fsSL https://starship.rs/install.sh | sh -s -- -y

cat <<'EOF' >>/home/ubuntu/.bashrc
eval "$(starship init bash)"
alias k='kubectl'
EOF

chown ubuntu:ubuntu /home/ubuntu/.bashrc
