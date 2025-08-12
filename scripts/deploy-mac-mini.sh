#!/bin/bash

# EduTech ChatBot Mac Mini Deployment Script
# 기존 서비스 영향 없이 새로운 서비스 완전 자동 배포
# Usage: ./deploy-mac-mini.sh [--env production|development] [--domain your-domain.com]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="edutech-chatbot"
PROJECT_PATH="/var/www/${PROJECT_NAME}"
BACKUP_PATH="/var/backups/${PROJECT_NAME}"
LOG_PATH="/var/log/${PROJECT_NAME}"
NGINX_SITES_PATH="/etc/nginx/sites-available"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled"
REQUIRED_NODE_VERSION="18"

# Default values
ENVIRONMENT="production"
DOMAIN=""
SKIP_MIGRATION=false
SKIP_BACKUP=false
FORCE_INSTALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --skip-migration)
      SKIP_MIGRATION=true
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=true
      shift
      ;;
    --force)
      FORCE_INSTALL=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--env production|development] [--domain your-domain.com] [--skip-migration] [--skip-backup] [--force]"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed"
        return 1
    fi
    return 0
}

# Main functions
print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 EduTech ChatBot Deployment                  ║"
    echo "║                      Mac Mini Setup                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Environment: ${ENVIRONMENT}"
    echo "Domain: ${DOMAIN:-"localhost"}"
    echo "Project Path: ${PROJECT_PATH}"
    echo
}

check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check if running on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script is designed for macOS (Mac Mini)"
        exit 1
    fi
    
    # Check Node.js version
    if check_command node; then
        NODE_VERSION=$(node -v | cut -d'.' -f1 | sed 's/v//')
        if [[ $NODE_VERSION -lt $REQUIRED_NODE_VERSION ]]; then
            log_error "Node.js $REQUIRED_NODE_VERSION+ required, found $NODE_VERSION"
            exit 1
        fi
        log_success "Node.js $(node -v) detected"
    else
        log_error "Node.js is not installed"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("npm" "git" "sqlite3")
    for cmd in "${required_commands[@]}"; do
        if ! check_command $cmd; then
            log_error "Please install $cmd first"
            exit 1
        fi
    done
    
    # Check optional commands
    if check_command brew; then
        log_success "Homebrew detected"
    else
        log_warning "Homebrew not found - some features may not work"
    fi
    
    if check_command pm2; then
        log_success "PM2 detected"
    else
        log_info "Installing PM2..."
        npm install -g pm2
    fi
    
    if check_command nginx; then
        log_success "Nginx detected"
    else
        log_info "Installing Nginx..."
        if check_command brew; then
            brew install nginx
        else
            log_error "Please install Nginx manually"
            exit 1
        fi
    fi
    
    log_success "System requirements check passed"
}

setup_directories() {
    log_info "Setting up directories..."
    
    # Create project directory
    if [[ ! -d "$PROJECT_PATH" ]] || [[ "$FORCE_INSTALL" == true ]]; then
        sudo mkdir -p "$PROJECT_PATH"
        sudo chown $(whoami):staff "$PROJECT_PATH"
        log_success "Created project directory: $PROJECT_PATH"
    fi
    
    # Create backup directory
    sudo mkdir -p "$BACKUP_PATH"
    sudo chown $(whoami):staff "$BACKUP_PATH"
    
    # Create log directory
    sudo mkdir -p "$LOG_PATH"
    sudo chown $(whoami):staff "$LOG_PATH"
    
    # Create data directories
    mkdir -p "$PROJECT_PATH/data/files"
    mkdir -p "$PROJECT_PATH/data/backups"
    mkdir -p "$PROJECT_PATH/logs"
    
    log_success "Directory setup completed"
}

clone_or_update_repository() {
    log_info "Setting up repository..."
    
    cd "$PROJECT_PATH"
    
    if [[ -d ".git" ]] && [[ "$FORCE_INSTALL" != true ]]; then
        log_info "Repository exists, pulling latest changes..."
        git fetch origin
        git reset --hard origin/main
    else
        log_info "Cloning repository..."
        if [[ -d ".git" ]]; then
            rm -rf .git
        fi
        
        # Repository URL을 실제 값으로 변경 필요
        git clone https://github.com/your-username/edutech-chatbot.git .
        
        # 또는 현재 작업 중인 파일들을 복사
        log_info "Copying project files from development directory..."
        cp -r /path/to/your/dev/directory/* ./
    fi
    
    log_success "Repository setup completed"
}

install_dependencies() {
    log_info "Installing dependencies..."
    
    cd "$PROJECT_PATH"
    
    # Install root dependencies
    if [[ -f "package.json" ]]; then
        npm install
    fi
    
    # Install backend dependencies
    if [[ -d "apps/api" ]]; then
        cd apps/api && npm install && cd ../..
    elif [[ -d "backend" ]]; then
        cd backend && npm install && cd ..
    fi
    
    # Install frontend dependencies
    if [[ -d "apps/web" ]]; then
        cd apps/web && npm install && cd ../..
    elif [[ -d "frontend" ]]; then
        cd frontend && npm install && cd ..
    fi
    
    log_success "Dependencies installed"
}

setup_environment() {
    log_info "Setting up environment configuration..."
    
    cd "$PROJECT_PATH"
    
    # Create .env files if they don't exist
    if [[ ! -f ".env" ]]; then
        log_info "Creating root .env file..."
        cat > .env << EOF
NODE_ENV=${ENVIRONMENT}
APP_ENV=local
DATABASE_URL=file:./data/edutech.db
PORT=3001
OPENAI_API_KEY=${OPENAI_API_KEY:-"your-openai-key-here"}
OPENAI_CHAT_MODEL=gpt-4o-mini
OPENAI_CONTENT_MODEL=gpt-4o
EOF
    fi
    
    # Backend .env
    if [[ -d "apps/api" ]] && [[ ! -f "apps/api/.env" ]]; then
        log_info "Creating backend .env file..."
        cat > apps/api/.env << EOF
NODE_ENV=${ENVIRONMENT}
APP_ENV=local
DATABASE_URL=file:../../data/edutech.db
PORT=3001
OPENAI_API_KEY=${OPENAI_API_KEY:-"your-openai-key-here"}
FRONTEND_URL=http://localhost:3000
EOF
    fi
    
    # Frontend .env.local
    if [[ -d "apps/web" ]] && [[ ! -f "apps/web/.env.local" ]]; then
        log_info "Creating frontend .env.local file..."
        cat > apps/web/.env.local << EOF
NEXT_PUBLIC_API_URL=http://localhost:3001/api
EOF
    fi
    
    log_success "Environment configuration completed"
}

setup_database() {
    log_info "Setting up database..."
    
    cd "$PROJECT_PATH"
    
    # Initialize SQLite database
    if [[ ! -f "data/edutech.db" ]]; then
        log_info "Creating SQLite database..."
        
        # Run Prisma migrations
        if [[ -f "prisma/schema.prisma" ]]; then
            npx prisma generate
            npx prisma db push
            log_success "Database schema created"
        else
            log_warning "Prisma schema not found, creating empty database"
            sqlite3 data/edutech.db "SELECT 1;"
        fi
    else
        log_info "Database already exists"
    fi
    
    # Run data migration if requested
    if [[ "$SKIP_MIGRATION" != true ]] && [[ -f "scripts/migrate-mongo-to-sqlite.ts" ]]; then
        log_info "Running data migration from MongoDB..."
        if [[ -n "$MONGODB_URI" ]]; then
            npx tsx scripts/migrate-mongo-to-sqlite.ts
            log_success "Data migration completed"
        else
            log_warning "MONGODB_URI not set, skipping migration"
        fi
    fi
    
    log_success "Database setup completed"
}

build_applications() {
    log_info "Building applications..."
    
    cd "$PROJECT_PATH"
    
    # Build backend
    if [[ -d "apps/api" ]] && [[ -f "apps/api/package.json" ]]; then
        cd apps/api
        if [[ $(grep -c "\"build\"" package.json) -gt 0 ]]; then
            npm run build
        fi
        cd ../..
    fi
    
    # Build frontend
    if [[ -d "apps/web" ]] && [[ -f "apps/web/package.json" ]]; then
        cd apps/web
        if [[ $(grep -c "\"build\"" package.json) -gt 0 ]]; then
            npm run build
        fi
        cd ../..
    fi
    
    log_success "Applications built successfully"
}

setup_nginx() {
    log_info "Setting up Nginx configuration..."
    
    if [[ -z "$DOMAIN" ]]; then
        log_warning "No domain specified, using localhost configuration"
        DOMAIN="localhost"
    fi
    
    # Copy and modify nginx config
    local nginx_config="$NGINX_SITES_PATH/${PROJECT_NAME}"
    
    if [[ -f "infrastructure/nginx/edutech.conf" ]]; then
        sudo cp infrastructure/nginx/edutech.conf "$nginx_config"
        
        # Replace domain placeholder
        sudo sed -i.bak "s/your-new-domain.com/$DOMAIN/g" "$nginx_config"
        
        # Replace paths
        sudo sed -i.bak "s|/var/www/edutech-chatbot|$PROJECT_PATH|g" "$nginx_config"
        
        # Enable site
        if [[ ! -L "$NGINX_ENABLED_PATH/${PROJECT_NAME}" ]]; then
            sudo ln -sf "$nginx_config" "$NGINX_ENABLED_PATH/${PROJECT_NAME}"
        fi
        
        # Test nginx configuration
        sudo nginx -t
        
        # Reload nginx
        sudo nginx -s reload || sudo brew services restart nginx
        
        log_success "Nginx configuration updated and reloaded"
    else
        log_warning "Nginx configuration file not found"
    fi
}

setup_pm2() {
    log_info "Setting up PM2 process management..."
    
    cd "$PROJECT_PATH"
    
    # Stop existing processes (if any)
    pm2 delete all 2>/dev/null || true
    
    # Start applications
    if [[ -f "ecosystem.config.js" ]]; then
        pm2 start ecosystem.config.js --env $ENVIRONMENT
        pm2 save
        
        # Setup PM2 startup (맥미니 재부팅 시 자동 실행)
        pm2 startup
        
        log_success "PM2 processes started and configured for auto-startup"
    else
        log_error "PM2 ecosystem file not found"
        return 1
    fi
}

setup_backup_system() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_info "Skipping backup system setup"
        return 0
    fi
    
    log_info "Setting up backup system..."
    
    # Create backup script
    cat > "$PROJECT_PATH/scripts/backup-system.sh" << 'EOF'
#!/bin/bash
# Automated backup script for EduTech ChatBot

BACKUP_DIR="/var/backups/edutech-chatbot"
PROJECT_DIR="/var/www/edutech-chatbot"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup database
sqlite3 "$PROJECT_DIR/data/edutech.db" ".backup $BACKUP_DIR/edutech_db_$TIMESTAMP.db"

# Backup files
tar -czf "$BACKUP_DIR/edutech_files_$TIMESTAMP.tar.gz" -C "$PROJECT_DIR" data/files

# Keep only last 30 backups
find "$BACKUP_DIR" -name "edutech_*" -mtime +30 -delete

echo "Backup completed: $TIMESTAMP"
EOF
    
    chmod +x "$PROJECT_PATH/scripts/backup-system.sh"
    
    # Setup cron job for daily backups
    (crontab -l 2>/dev/null; echo "0 2 * * * $PROJECT_PATH/scripts/backup-system.sh") | crontab -
    
    log_success "Backup system configured (daily at 2 AM)"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check PM2 processes
    if pm2 list | grep -q "edutech"; then
        log_success "PM2 processes are running"
    else
        log_error "PM2 processes not found"
        return 1
    fi
    
    # Check database
    if [[ -f "$PROJECT_PATH/data/edutech.db" ]]; then
        log_success "Database file exists"
    else
        log_error "Database file not found"
        return 1
    fi
    
    # Check HTTP responses
    sleep 5  # Wait for services to start
    
    if curl -s "http://localhost:3000" > /dev/null; then
        log_success "Frontend is responding"
    else
        log_warning "Frontend not responding (this may be normal during initial startup)"
    fi
    
    if curl -s "http://localhost:3001/health" > /dev/null; then
        log_success "Backend is responding"
    else
        log_warning "Backend not responding (this may be normal during initial startup)"
    fi
    
    log_success "Deployment verification completed"
}

cleanup_old_versions() {
    log_info "Cleaning up old versions..."
    
    # Remove old log files
    find "$LOG_PATH" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    find "$PROJECT_PATH/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    # Clean npm cache
    npm cache clean --force 2>/dev/null || true
    
    log_success "Cleanup completed"
}

print_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   Deployment Complete!                      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "🌐 Frontend: http://localhost:3000"
    echo "🔧 Backend API: http://localhost:3001"
    echo "📁 Static Files: http://localhost:8080"
    echo
    if [[ -n "$DOMAIN" && "$DOMAIN" != "localhost" ]]; then
        echo "🔗 Domain: https://$DOMAIN (configure Cloudflare tunnel)"
    fi
    echo
    echo "📊 PM2 Status: pm2 status"
    echo "📋 PM2 Logs: pm2 logs"
    echo "🔄 PM2 Restart: pm2 restart all"
    echo "🗄️  Database: $PROJECT_PATH/data/edutech.db"
    echo "📁 Files: $PROJECT_PATH/data/files"
    echo "📝 Logs: $PROJECT_PATH/logs"
    echo
    echo "Next steps:"
    echo "1. Configure your OpenAI API key in .env files"
    echo "2. Set up Cloudflare tunnel for domain access"
    echo "3. Run data migration if needed"
    echo "4. Test all functionality"
    echo
}

# Main execution flow
main() {
    print_banner
    
    # Preflight checks
    if [[ $EUID -eq 0 ]]; then
        log_error "Don't run this script as root"
        exit 1
    fi
    
    if [[ -z "$OPENAI_API_KEY" ]]; then
        log_warning "OPENAI_API_KEY not set - remember to configure this later"
    fi
    
    # Execute deployment steps
    check_system_requirements
    setup_directories
    clone_or_update_repository
    install_dependencies
    setup_environment
    setup_database
    build_applications
    setup_nginx
    setup_pm2
    setup_backup_system
    verify_deployment
    cleanup_old_versions
    
    print_summary
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Check the logs for details."' ERR

# Run main function
main "$@"