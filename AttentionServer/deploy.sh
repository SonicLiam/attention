#!/bin/bash
set -euo pipefail

# Attention Server Deployment Script
# Usage: ./deploy.sh

SSH_KEY="/Users/liam/Workspace/remote-claw/default.pem"
SSH_HOST="root@118.196.142.21"
SSH_PORT="22"
SSH_OPTS="-i $SSH_KEY -p $SSH_PORT -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o StrictHostKeyChecking=no"
REMOTE_DIR="/opt/attention-server"

echo "=== Attention Server Deployment ==="

# Step 1: Install Docker on remote if not present
echo "[1/5] Ensuring Docker is installed on remote..."
ssh $SSH_OPTS $SSH_HOST 'bash -s' << 'INSTALL_DOCKER'
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    echo "Docker installed."
else
    echo "Docker already installed."
fi

# Ensure docker compose plugin is available
if ! docker compose version &> /dev/null; then
    echo "Installing docker-compose-plugin..."
    dnf install -y docker-compose-plugin
fi

docker --version
docker compose version
INSTALL_DOCKER

# Step 2: Create remote directory and copy files
echo "[2/5] Copying files to remote server..."
ssh $SSH_OPTS $SSH_HOST "mkdir -p $REMOTE_DIR/migrations $REMOTE_DIR/src"

# Use rsync if available, otherwise scp
if command -v rsync &> /dev/null; then
    rsync -avz --delete \
        -e "ssh $SSH_OPTS" \
        --exclude node_modules \
        --exclude dist \
        --exclude .git \
        ./ $SSH_HOST:$REMOTE_DIR/
else
    scp $SSH_OPTS -r \
        package.json tsconfig.json Dockerfile docker-compose.yml nginx.conf .env.example \
        $SSH_HOST:$REMOTE_DIR/
    scp $SSH_OPTS -r src/ $SSH_HOST:$REMOTE_DIR/src/
    scp $SSH_OPTS -r migrations/ $SSH_HOST:$REMOTE_DIR/migrations/
fi

# Step 3: Create .env if not exists
echo "[3/5] Setting up environment..."
ssh $SSH_OPTS $SSH_HOST "bash -s" << SETUP_ENV
cd $REMOTE_DIR
if [ ! -f .env ]; then
    JWT_SECRET=\$(openssl rand -base64 32)
    JWT_REFRESH_SECRET=\$(openssl rand -base64 32)
    cat > .env << EOF
JWT_SECRET=\$JWT_SECRET
JWT_REFRESH_SECRET=\$JWT_REFRESH_SECRET
EOF
    echo "Created .env with generated secrets"
else
    echo ".env already exists, keeping existing secrets"
fi
SETUP_ENV

# Step 4: Build and deploy
echo "[4/5] Building and deploying containers..."
ssh $SSH_OPTS $SSH_HOST "bash -s" << DEPLOY
cd $REMOTE_DIR
docker compose down --remove-orphans || true
docker compose build --no-cache
docker compose up -d
echo "Waiting for services to start..."
sleep 10
docker compose ps
DEPLOY

# Step 5: Run migrations
echo "[5/5] Running database migrations..."
ssh $SSH_OPTS $SSH_HOST "bash -s" << MIGRATE
cd $REMOTE_DIR
docker compose exec -T app node dist/migrate.js
MIGRATE

echo ""
echo "=== Deployment complete ==="
echo "API: http://118.196.142.21/health"
echo "WebSocket: ws://118.196.142.21/ws/sync"
