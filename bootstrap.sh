#!/bin/bash
# Run this once on the OCI VM to bootstrap Docker + Kestra systemd service
# Usage: ssh -i ~/.ssh/oracle-kestra opc@<VM_IP> 'bash -s' < bootstrap.sh

set -e

echo "==> Installing Docker..."
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker opc

echo "==> Installing Docker Compose plugin..."
sudo dnf install -y docker-compose-plugin || {
  # Fallback: install standalone compose
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
}

echo "==> Creating kestra directory..."
mkdir -p ~/kestra/certs

echo "==> Installing systemd service..."
sudo tee /etc/systemd/system/kestra.service > /dev/null <<'EOF'
[Unit]
Description=Kestra Workflow Engine
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=opc
WorkingDirectory=/home/opc/kestra
ExecStart=/usr/bin/docker compose -f docker-compose-oracle.yaml up
ExecStop=/usr/bin/docker compose -f docker-compose-oracle.yaml down
Restart=always
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kestra

echo ""
echo "==> Bootstrap complete!"
echo "    Copy your docker-compose-oracle.yaml, .env, and service-account.json to ~/kestra/"
echo "    Then run: sudo systemctl start kestra"
echo "    Check status: sudo systemctl status kestra"
echo "    View logs: sudo journalctl -u kestra -f"