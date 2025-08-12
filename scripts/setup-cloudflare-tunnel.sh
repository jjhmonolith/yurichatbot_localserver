#!/bin/bash

# Cloudflare Tunnel Setup Script for Mac Mini
# 맥미니의 EduTech ChatBot을 Cloudflare를 통해 안전하게 외부 노출
# Usage: ./setup-cloudflare-tunnel.sh --domain your-domain.com [--email your@email.com] [--api-token your-token]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLOUDFLARED_PATH="/usr/local/bin/cloudflared"
TUNNEL_CONFIG_PATH="$HOME/.cloudflared"
TUNNEL_NAME="edutech-chatbot"
PROJECT_PATH="/var/www/edutech-chatbot"

# Parameters
DOMAIN=""
EMAIL=""
API_TOKEN=""
FORCE_RECREATE=false
DRY_RUN=false

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_usage() {
    echo "Cloudflare Tunnel Setup for EduTech ChatBot"
    echo ""
    echo "Usage:"
    echo "  $0 --domain DOMAIN [options]"
    echo ""
    echo "Required:"
    echo "  --domain DOMAIN        Your domain name (e.g., edutech.example.com)"
    echo ""
    echo "Optional:"
    echo "  --email EMAIL          Cloudflare account email"
    echo "  --api-token TOKEN      Cloudflare API token (Global API Key or Zone token)"
    echo "  --force                Force recreate tunnel if exists"
    echo "  --dry-run              Show what would be done without executing"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --domain edutech.example.com --email user@example.com"
    echo "  $0 --domain edutech.example.com --api-token your-token --force"
    echo ""
    echo "Prerequisites:"
    echo "1. Domain must be added to Cloudflare and active"
    echo "2. Cloudflare account with API access"
    echo "3. EduTech ChatBot running on Mac Mini"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --api-token)
            API_TOKEN="$2"
            shift 2
            ;;
        --force)
            FORCE_RECREATE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" ]]; then
    log_error "Domain is required"
    print_usage
    exit 1
fi

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Cloudflare Tunnel Setup for EduTech              ║"
    echo "║                     Mac Mini Edition                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Domain: $DOMAIN"
    echo "Email: ${EMAIL:-"(not provided, will use interactive login)"}"
    echo "API Token: ${API_TOKEN:+*****}"
    echo "Force Recreate: $FORCE_RECREATE"
    echo "Dry Run: $DRY_RUN"
    echo
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if domain is valid
    if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $DOMAIN"
        exit 1
    fi
    
    # Check if Mac Mini services are running
    if ! curl -s http://localhost:3000 > /dev/null; then
        log_warning "Frontend service (port 3000) not responding"
    fi
    
    if ! curl -s http://localhost:3001/health > /dev/null; then
        log_warning "Backend service (port 3001) not responding"
    fi
    
    # Check DNS resolution
    if ! dig +short "$DOMAIN" > /dev/null; then
        log_warning "Domain $DOMAIN does not resolve - ensure it's added to Cloudflare"
    else
        local nameservers=$(dig +short NS "$DOMAIN" | head -2)
        if [[ "$nameservers" != *"cloudflare"* ]]; then
            log_warning "Domain may not be using Cloudflare nameservers"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

install_cloudflared() {
    log_info "Installing/updating cloudflared..."
    
    if command -v brew &> /dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "Would run: brew install cloudflared"
        else
            brew install cloudflared
        fi
    else
        log_info "Homebrew not found, installing cloudflared manually..."
        
        local arch=$(uname -m)
        local os="darwin"
        local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-${os}-${arch}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "Would download: $download_url"
            echo "Would install to: $CLOUDFLARED_PATH"
        else
            curl -L "$download_url" -o /tmp/cloudflared
            chmod +x /tmp/cloudflared
            sudo mv /tmp/cloudflared "$CLOUDFLARED_PATH"
        fi
    fi
    
    # Verify installation
    if [[ "$DRY_RUN" != "true" ]]; then
        if "$CLOUDFLARED_PATH" version &> /dev/null; then
            log_success "cloudflared installed: $(cloudflared version)"
        else
            log_error "cloudflared installation failed"
            exit 1
        fi
    fi
}

authenticate_cloudflare() {
    log_info "Authenticating with Cloudflare..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would authenticate with Cloudflare"
        return 0
    fi
    
    # Create config directory
    mkdir -p "$TUNNEL_CONFIG_PATH"
    
    # Check if already authenticated
    if [[ -f "$TUNNEL_CONFIG_PATH/cert.pem" ]]; then
        log_info "Already authenticated with Cloudflare"
        return 0
    fi
    
    # Authenticate based on provided credentials
    if [[ -n "$API_TOKEN" ]]; then
        # Use API token
        export TUNNEL_TOKEN="$API_TOKEN"
        if ! cloudflared tunnel login --token "$API_TOKEN"; then
            log_error "Failed to authenticate with API token"
            exit 1
        fi
    elif [[ -n "$EMAIL" ]]; then
        # Use email (will require Global API Key)
        if ! cloudflared tunnel login --email "$EMAIL"; then
            log_error "Failed to authenticate with email"
            exit 1
        fi
    else
        # Interactive login
        log_info "Opening browser for interactive authentication..."
        if ! cloudflared tunnel login; then
            log_error "Failed to authenticate interactively"
            exit 1
        fi
    fi
    
    log_success "Cloudflare authentication completed"
}

create_tunnel() {
    log_info "Creating Cloudflare tunnel..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would create tunnel: $TUNNEL_NAME"
        return 0
    fi
    
    # Check if tunnel already exists
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        if [[ "$FORCE_RECREATE" == "true" ]]; then
            log_info "Tunnel exists, deleting and recreating..."
            cloudflared tunnel delete "$TUNNEL_NAME" || true
        else
            log_info "Tunnel already exists, using existing tunnel"
            return 0
        fi
    fi
    
    # Create new tunnel
    if cloudflared tunnel create "$TUNNEL_NAME"; then
        log_success "Tunnel created: $TUNNEL_NAME"
    else
        log_error "Failed to create tunnel"
        exit 1
    fi
}

configure_tunnel() {
    log_info "Configuring tunnel routing..."
    
    local config_file="$TUNNEL_CONFIG_PATH/config.yml"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would create config file: $config_file"
        return 0
    fi
    
    # Get tunnel UUID
    local tunnel_uuid=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    if [[ -z "$tunnel_uuid" ]]; then
        log_error "Could not find tunnel UUID"
        exit 1
    fi
    
    # Create tunnel configuration
    cat > "$config_file" << EOF
# Cloudflare Tunnel Configuration for EduTech ChatBot
# Generated on $(date)

tunnel: $tunnel_uuid
credentials-file: $TUNNEL_CONFIG_PATH/$tunnel_uuid.json

# Global settings
origincert: $TUNNEL_CONFIG_PATH/cert.pem
no-autoupdate: false
retries: 3
grace-period: 30s

# Logging
loglevel: info
logfile: $PROJECT_PATH/logs/cloudflare-tunnel.log

# Ingress rules (order matters!)
ingress:
  # Main domain - frontend
  - hostname: $DOMAIN
    service: http://localhost:3000
    originRequest:
      httpHostHeader: $DOMAIN
      connectTimeout: 30s
      tlsTimeout: 10s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveTimeout: 90s
      
  # API subdomain
  - hostname: api.$DOMAIN
    service: http://localhost:3001
    originRequest:
      httpHostHeader: api.$DOMAIN
      connectTimeout: 30s
      tlsTimeout: 10s
      
  # Static files subdomain  
  - hostname: cdn.$DOMAIN
    service: http://localhost:8080
    originRequest:
      httpHostHeader: cdn.$DOMAIN
      
  # Admin subdomain (optional)
  - hostname: admin.$DOMAIN
    service: http://localhost:3000/admin
    originRequest:
      httpHostHeader: admin.$DOMAIN
      
  # Health check endpoint
  - hostname: $DOMAIN
    path: /health
    service: http_status:200
    
  # Catch-all rule (must be last)
  - service: http_status:404
EOF
    
    log_success "Tunnel configuration created: $config_file"
    
    # Validate configuration
    if ! cloudflared tunnel ingress validate "$config_file"; then
        log_error "Tunnel configuration validation failed"
        exit 1
    fi
    
    log_success "Tunnel configuration validated"
}

setup_dns_records() {
    log_info "Setting up DNS records..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would create DNS records for:"
        echo "  - $DOMAIN"
        echo "  - api.$DOMAIN"
        echo "  - cdn.$DOMAIN"
        echo "  - admin.$DOMAIN"
        return 0
    fi
    
    # Get tunnel UUID
    local tunnel_uuid=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    # Create DNS records
    local subdomains=("" "api" "cdn" "admin")
    
    for subdomain in "${subdomains[@]}"; do
        local hostname="$DOMAIN"
        if [[ -n "$subdomain" ]]; then
            hostname="$subdomain.$DOMAIN"
        fi
        
        log_info "Creating DNS record for $hostname..."
        
        if cloudflared tunnel route dns "$tunnel_uuid" "$hostname"; then
            log_success "DNS record created for $hostname"
        else
            log_warning "Failed to create DNS record for $hostname (may already exist)"
        fi
    done
}

install_service() {
    log_info "Installing tunnel as system service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would install tunnel service"
        return 0
    fi
    
    # Install service
    if cloudflared service install; then
        log_success "Tunnel service installed"
    else
        log_warning "Service installation failed (may already be installed)"
    fi
    
    # Start service
    if sudo launchctl load /Library/LaunchDaemons/com.cloudflare.cloudflared.plist; then
        log_success "Tunnel service started"
    else
        log_warning "Service start failed (may already be running)"
    fi
}

test_tunnel() {
    log_info "Testing tunnel connectivity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would test tunnel connectivity"
        return 0
    fi
    
    # Wait for tunnel to be ready
    sleep 10
    
    # Test main domain
    if curl -s --max-time 30 "https://$DOMAIN/health" > /dev/null; then
        log_success "Main domain is accessible: https://$DOMAIN"
    else
        log_warning "Main domain test failed (may need time to propagate)"
    fi
    
    # Test API subdomain
    if curl -s --max-time 30 "https://api.$DOMAIN/health" > /dev/null; then
        log_success "API subdomain is accessible: https://api.$DOMAIN"
    else
        log_warning "API subdomain test failed"
    fi
    
    # Show tunnel status
    cloudflared tunnel info "$TUNNEL_NAME" || true
}

print_completion_info() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                Cloudflare Tunnel Setup Complete             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "🌐 Your EduTech ChatBot is now accessible at:"
    echo "   Main Site:    https://$DOMAIN"
    echo "   API:          https://api.$DOMAIN"
    echo "   Static Files: https://cdn.$DOMAIN"  
    echo "   Admin:        https://admin.$DOMAIN"
    echo
    echo "📊 Tunnel Management:"
    echo "   Status:       cloudflared tunnel info $TUNNEL_NAME"
    echo "   Logs:         tail -f $PROJECT_PATH/logs/cloudflare-tunnel.log"
    echo "   Restart:      sudo launchctl unload /Library/LaunchDaemons/com.cloudflare.cloudflared.plist"
    echo "                sudo launchctl load /Library/LaunchDaemons/com.cloudflare.cloudflared.plist"
    echo "   Stop:         sudo launchctl unload /Library/LaunchDaemons/com.cloudflare.cloudflared.plist"
    echo
    echo "🔧 Configuration Files:"
    echo "   Config:       $TUNNEL_CONFIG_PATH/config.yml"
    echo "   Credentials:  $TUNNEL_CONFIG_PATH/*.json"
    echo
    echo "⚡ Next Steps:"
    echo "1. Test all endpoints to ensure they're working"
    echo "2. Configure Cloudflare security settings (WAF, Rate Limiting)"
    echo "3. Set up SSL/TLS settings (recommend Full or Full Strict)"
    echo "4. Configure caching rules for static content"
    echo "5. Set up analytics and monitoring"
    echo
    echo "🔍 Troubleshooting:"
    echo "- If sites aren't accessible, wait 5-10 minutes for DNS propagation"
    echo "- Check tunnel status: cloudflared tunnel info $TUNNEL_NAME"
    echo "- View logs: tail -f $PROJECT_PATH/logs/cloudflare-tunnel.log"
    echo "- Restart services: pm2 restart all"
    echo
}

# Main execution
main() {
    print_banner
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    check_prerequisites
    install_cloudflared
    authenticate_cloudflare
    create_tunnel
    configure_tunnel
    setup_dns_records
    install_service
    test_tunnel
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_completion_info
    else
        echo
        log_info "DRY RUN COMPLETED - Re-run without --dry-run to execute"
    fi
}

# Error handling
trap 'log_error "Setup failed at line $LINENO. Check the logs for details."' ERR

# Run main function
main "$@"