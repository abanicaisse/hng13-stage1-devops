#!/bin/bash

###############################################################################
# HNG Stage 1 - Automated Deployment Script
# Description: Automates Docker app deployment with Nginx reverse proxy
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create logs directory
LOGS_DIR="logs"
mkdir -p "$LOGS_DIR"
LOG_FILE="$LOGS_DIR/deploy_$(date +%Y%m%d_%H%M%S).log"

###############################################################################
# LOGGING FUNCTIONS
###############################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log "ERROR" "$@"
}

trap 'log_error "Script failed at line $LINENO"' ERR

###############################################################################
# INPUT VALIDATION FUNCTIONS
###############################################################################

validate_url() {
    local url=$1
    if [[ ! $url =~ ^https?:// ]]; then
        log_error "Invalid URL format: $url"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address: $ip"
        return 1
    fi
    return 0
}

validate_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number: $port"
        return 1
    fi
    return 0
}

validate_file_exists() {
    local file=$1
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    return 0
}

###############################################################################
# COLLECT PARAMETERS FROM USER
###############################################################################

collect_parameters() {
    log_info "=== Stage 1: Collecting Deployment Parameters ==="
    
    read -p "Enter Git Repository URL: " GIT_REPO_URL
    validate_url "$GIT_REPO_URL" || exit 1
    
    read -sp "Enter Personal Access Token (PAT): " GIT_PAT
    echo
    if [ -z "$GIT_PAT" ]; then
        log_error "PAT cannot be empty"
        exit 1
    fi
    
    read -p "Enter branch name [default: main]: " GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
    
    read -p "Enter remote server username: " SSH_USER
    read -p "Enter remote server IP: " SSH_HOST
    validate_ip "$SSH_HOST" || exit 1
    
    read -p "Enter SSH key path [default: ~/.ssh/id_rsa]: " SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    validate_file_exists "$SSH_KEY" || exit 1
    
    read -p "Enter application port (container internal port): " APP_PORT
    validate_port "$APP_PORT" || exit 1
    
    PROJECT_NAME=$(basename "$GIT_REPO_URL" .git)
    
    log_success "Parameters collected successfully"
    log_info "Repository: $GIT_REPO_URL"
    log_info "Branch: $GIT_BRANCH"
    log_info "Server: $SSH_USER@$SSH_HOST"
    log_info "Application Port: $APP_PORT"
    log_info "Project Name: $PROJECT_NAME"
}

###############################################################################
# TEST SSH CONNECTION
###############################################################################

test_ssh_connection() {
    log_info "=== Stage 2: Testing SSH Connection ==="
    
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SSH_USER@$SSH_HOST" "echo 'SSH connection successful'" || {
        log_error "Cannot connect to remote server"
        exit 1
    }
    
    log_success "SSH connection verified"
}

###############################################################################
# PREPARE REMOTE ENVIRONMENT
###############################################################################

prepare_remote_environment() {
    log_info "=== Stage 3: Preparing Remote Environment ==="
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" 'bash -s' << 'ENDSSH'
        set -e
        
        echo "[INFO] Updating system packages..."
        sudo apt-get update -qq
        
        echo "[INFO] Installing prerequisites..."
        sudo apt-get install -y -qq curl wget git nginx
        
        if ! command -v docker &> /dev/null; then
            echo "[INFO] Installing Docker..."
            curl -fsSL https://get.docker.com | sudo sh
            sudo usermod -aG docker $USER
        else
            echo "[INFO] Docker already installed: $(docker --version)"
        fi
        
        if ! command -v docker-compose &> /dev/null; then
            echo "[INFO] Installing Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo "[INFO] Docker Compose already installed: $(docker-compose --version)"
        fi
        
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        echo "[SUCCESS] Remote environment prepared"
ENDSSH
    
    log_success "Remote environment ready"
}

###############################################################################
# CLONE REPOSITORY ON REMOTE SERVER
###############################################################################

clone_repository_remote() {
    log_info "=== Stage 4: Cloning Repository on Remote Server ==="
    
    # Create authenticated URL
    local auth_url=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_PAT}@|")
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
        set -e
        
        cd ~
        
        if [ -d "$PROJECT_NAME" ]; then
            echo "[INFO] Directory exists. Pulling latest changes..."
            cd "$PROJECT_NAME"
            git pull origin $GIT_BRANCH || {
                echo "[ERROR] Failed to pull latest changes"
                exit 1
            }
        else
            echo "[INFO] Cloning repository..."
            git clone -b $GIT_BRANCH "$auth_url" "$PROJECT_NAME" || {
                echo "[ERROR] Failed to clone repository"
                exit 1
            }
            cd "$PROJECT_NAME"
        fi
        
        echo "[SUCCESS] Repository ready at: \$(pwd)"
ENDSSH
    
    log_success "Repository cloned on remote server"
}

###############################################################################
# VERIFY DOCKERFILE EXISTS ON REMOTE
###############################################################################

verify_docker_files() {
    log_info "=== Stage 5: Verifying Docker Configuration ==="
    
    DEPLOYMENT_TYPE=$(ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
        cd ~/$PROJECT_NAME
        
        if [ -f "Dockerfile" ]; then
            echo "dockerfile"
        elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
            echo "compose"
        else
            echo "none"
        fi
ENDSSH
    )
    
    if [ "$DEPLOYMENT_TYPE" = "none" ]; then
        log_error "No Dockerfile or docker-compose.yml found in repository!"
        exit 1
    fi
    
    log_success "Found deployment type: $DEPLOYMENT_TYPE"
}

###############################################################################
# DEPLOY DOCKER APPLICATION
###############################################################################

deploy_application() {
    log_info "=== Stage 6: Deploying Docker Application ==="
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
        set -e
        cd ~/$PROJECT_NAME
        
        echo "[INFO] Stopping existing containers..."
        sudo docker-compose down 2>/dev/null || sudo docker stop $PROJECT_NAME 2>/dev/null || true
        sudo docker rm $PROJECT_NAME 2>/dev/null || true
        
        if [ "$DEPLOYMENT_TYPE" = "compose" ]; then
            echo "[INFO] Deploying with docker-compose..."
            sudo docker-compose up -d --build
        else
            echo "[INFO] Building Docker image..."
            sudo docker build -t $PROJECT_NAME:latest .
            
            echo "[INFO] Running container..."
            sudo docker run -d \
                --name $PROJECT_NAME \
                --restart unless-stopped \
                -p $APP_PORT:$APP_PORT \
                $PROJECT_NAME:latest
        fi
        
        echo "[INFO] Waiting for container to be healthy..."
        sleep 5
        
        if sudo docker ps | grep -q $PROJECT_NAME; then
            echo "[SUCCESS] Container is running"
            sudo docker ps --filter name=$PROJECT_NAME
        else
            echo "[ERROR] Container failed to start"
            sudo docker logs $PROJECT_NAME 2>&1 || true
            exit 1
        fi
ENDSSH
    
    log_success "Application deployed successfully"
}

###############################################################################
# CONFIGURE NGINX REVERSE PROXY
###############################################################################

configure_nginx() {
    log_info "=== Stage 7: Configuring Nginx Reverse Proxy ==="
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
        set -e
        
        sudo tee /etc/nginx/sites-available/$PROJECT_NAME > /dev/null << 'NGINXCONF'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXCONF
        
        sudo ln -sf /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/
        sudo rm -f /etc/nginx/sites-enabled/default
        
        sudo nginx -t
        sudo systemctl reload nginx
        
        echo "[SUCCESS] Nginx configured and reloaded"
ENDSSH
    
    log_success "Nginx reverse proxy configured"
}

###############################################################################
# VALIDATE DEPLOYMENT
###############################################################################

validate_deployment() {
    log_info "=== Stage 8: Validating Deployment ==="
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
        set -e
        
        echo "[INFO] Testing local access..."
        if curl -f -s http://localhost > /dev/null; then
            echo "[SUCCESS] Application responds locally"
        else
            echo "[ERROR] Application not responding locally"
            exit 1
        fi
        
        echo "[INFO] Checking Docker status..."
        sudo docker ps --filter name=$PROJECT_NAME --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        echo "[INFO] Checking Nginx status..."
        sudo systemctl status nginx --no-pager | head -n 5
ENDSSH
    
    log_info "Testing external access..."
    sleep 3
    if curl -f -s "http://$SSH_HOST" > /dev/null; then
        log_success "Application is accessible at http://$SSH_HOST"
    else
        log_warning "External access test failed - may need firewall configuration"
    fi
    
    log_success "Deployment validation complete!"
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    log_info "=========================================="
    log_info "HNG Stage 1 - Automated Deployment Script"
    log_info "=========================================="
    log_info "Log file: $LOG_FILE"
    echo
    
    collect_parameters
    test_ssh_connection
    prepare_remote_environment
    clone_repository_remote
    verify_docker_files
    deploy_application
    configure_nginx
    validate_deployment
    
    echo
    log_success "=========================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "=========================================="
    log_success "Access your application at: http://$SSH_HOST"
    log_success "Logs saved to: $LOG_FILE"
}

# Run main function
main "$@"