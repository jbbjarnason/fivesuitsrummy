#!/usr/bin/env bash
#
# Production Secrets Generator for Five Crowns
# This script generates cryptographically secure secrets using OpenSSL.
# Run this once on your production server. Secrets are written to .env files
# and should NEVER be committed to git.
#
set -euo pipefail

echo "================================================"
echo "  Five Crowns - Production Secrets Generator"
echo "================================================"
echo ""

# Check for OpenSSL
if ! command -v openssl &> /dev/null; then
    echo "ERROR: OpenSSL is required but not installed."
    exit 1
fi

# Generate cryptographically secure secrets
echo "Generating cryptographically secure secrets..."
JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | tr -d '/' | tr -d '+')
LIVEKIT_API_KEY=$(openssl rand -hex 12)
LIVEKIT_API_SECRET=$(openssl rand -base64 32 | tr -d '\n')
TURN_SECRET=$(openssl rand -hex 32)

# Prompt for required configuration
echo ""
echo "Please provide your production configuration:"
echo ""

read -p "Production domain (e.g., fcrowns.example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "ERROR: Domain is required"
    exit 1
fi

read -p "SMTP Host (e.g., smtp.sendgrid.net): " SMTP_HOST
read -p "SMTP Port [587]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
read -p "SMTP Username: " SMTP_USERNAME
read -sp "SMTP Password: " SMTP_PASSWORD
echo ""
read -p "SMTP From Address (e.g., no-reply@${DOMAIN}): " SMTP_FROM
SMTP_FROM=${SMTP_FROM:-"no-reply@${DOMAIN}"}

# Create infra/.env for docker-compose
INFRA_ENV_FILE="infra/.env"
echo ""
echo "Writing ${INFRA_ENV_FILE}..."

cat > "${INFRA_ENV_FILE}" << EOF
# Production Environment - Generated $(date -Iseconds)
# DO NOT COMMIT THIS FILE TO GIT

# Environment mode
ENVIRONMENT=production

# Database (used by docker-compose)
POSTGRES_USER=fivecrowns
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=fivecrowns

# Server configuration
DATABASE_URL=postgres://fivecrowns:${POSTGRES_PASSWORD}@postgres:5432/fivecrowns
JWT_SECRET=${JWT_SECRET}
JWT_ACCESS_TTL_DAYS=7

# CORS - your production domain(s), comma-separated
ALLOWED_ORIGINS=https://${DOMAIN}

# Trust proxy headers (X-Forwarded-For) for rate limiting
TRUST_PROXY=true

# SMTP Configuration
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_FROM=${SMTP_FROM}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_SECURE=true

# Base URL (for email links)
BASE_URL=https://${DOMAIN}

# LiveKit
LIVEKIT_URL=wss://livekit.${DOMAIN}
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}

# TURN (reference only - also in config files)
TURN_SECRET=${TURN_SECRET}
EOF

chmod 600 "${INFRA_ENV_FILE}"
echo "Created ${INFRA_ENV_FILE} (permissions: 600)"

# Create livekit.yaml with the generated keys and TURN config
LIVEKIT_CONFIG="infra/livekit.yaml"
echo "Writing ${LIVEKIT_CONFIG}..."

cat > "${LIVEKIT_CONFIG}" << EOF
# LiveKit Server Configuration - Generated $(date -Iseconds)
port: 7880
rtc:
  udp_port: 7882
  tcp_port: 7881
  use_external_ip: true

keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}

# TURN server for reliable connectivity
turn:
  enabled: true
  udp_port: 3478
  tls_port: 5349
  credential: ${TURN_SECRET}
EOF

chmod 600 "${LIVEKIT_CONFIG}"
echo "Created ${LIVEKIT_CONFIG} (permissions: 600)"

# Create turnserver.conf
TURN_CONFIG="infra/turnserver.conf"
echo "Writing ${TURN_CONFIG}..."

cat > "${TURN_CONFIG}" << EOF
# TURN Server Configuration - Generated $(date -Iseconds)
listening-port=3478
tls-listening-port=5349
fingerprint

# Shared secret auth with LiveKit
use-auth-secret
static-auth-secret=${TURN_SECRET}

realm=${DOMAIN}
server-name=turn.${DOMAIN}

# Security hardening
no-loopback-peers
no-multicast-peers

# Prevent relay to private networks
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=::1

# Rate limiting
total-quota=100
user-quota=10
max-bps=1000000

# Logging
no-stdout-log
log-file=/var/log/turnserver.log
EOF

chmod 600 "${TURN_CONFIG}"
echo "Created ${TURN_CONFIG} (permissions: 600)"

# Create Caddyfile
CADDY_CONFIG="infra/Caddyfile"
echo "Writing ${CADDY_CONFIG}..."

cat > "${CADDY_CONFIG}" << EOF
# Caddy Configuration - Generated $(date -Iseconds)

${DOMAIN} {
	@websocket {
		path /ws
		header Connection *Upgrade*
		header Upgrade websocket
	}
	reverse_proxy @websocket server:8080
	reverse_proxy server:8080
}

livekit.${DOMAIN} {
	reverse_proxy livekit:7880
}
EOF

echo "Created ${CADDY_CONFIG}"

# Configure UFW firewall
echo ""
echo "================================================"
echo "  Firewall Configuration"
echo "================================================"
echo ""

if command -v ufw &> /dev/null; then
    read -p "Configure UFW firewall rules? (Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "Setting up UFW rules..."

        # Default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Allow SSH (critical - don't lock yourself out!)
        sudo ufw allow 22/tcp comment 'SSH'

        # Allow Caddy (HTTPS)
        sudo ufw allow 80/tcp comment 'HTTP - LetsEncrypt'
        sudo ufw allow 443/tcp comment 'HTTPS - Caddy'

        # Allow TURN server
        sudo ufw allow 3478/tcp comment 'TURN TCP'
        sudo ufw allow 3478/udp comment 'TURN UDP'
        sudo ufw allow 5349/tcp comment 'TURN TLS TCP'
        sudo ufw allow 5349/udp comment 'TURN TLS UDP'

        # Allow WebRTC
        sudo ufw allow 7881/tcp comment 'LiveKit WebRTC TCP'
        sudo ufw allow 7882/udp comment 'LiveKit WebRTC UDP'

        # Enable UFW
        sudo ufw --force enable

        echo ""
        echo "UFW rules configured:"
        sudo ufw status numbered
    fi
else
    echo "UFW not found. Manually configure your firewall:"
    echo "  ALLOW: 22/tcp (SSH)"
    echo "  ALLOW: 80/tcp, 443/tcp (HTTPS)"
    echo "  ALLOW: 3478/tcp+udp, 5349/tcp+udp (TURN)"
    echo "  ALLOW: 7881/tcp, 7882/udp (WebRTC)"
    echo "  DENY: all other incoming"
fi

# Summary
echo ""
echo "================================================"
echo "  Setup Complete!"
echo "================================================"
echo ""
echo "Files created:"
echo "  - ${INFRA_ENV_FILE}"
echo "  - ${LIVEKIT_CONFIG}"
echo "  - ${TURN_CONFIG}"
echo "  - ${CADDY_CONFIG}"
echo ""
echo "Secrets generated:"
echo "  - JWT_SECRET (64 chars)"
echo "  - POSTGRES_PASSWORD (32 chars)"
echo "  - LIVEKIT_API_KEY (24 chars)"
echo "  - LIVEKIT_API_SECRET (32 chars)"
echo "  - TURN_SECRET (64 chars)"
echo ""
echo "DNS records needed (point to this server):"
echo "  - ${DOMAIN}"
echo "  - livekit.${DOMAIN}"
echo ""
echo "IMPORTANT:"
echo "  1. These files contain secrets - NEVER commit them to git"
echo "  2. Back up .env securely (password manager, vault, etc.)"
echo ""
echo "To deploy:"
echo "  cd infra && docker compose up -d"
echo ""
