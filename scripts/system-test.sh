#!/bin/bash

# EduTech ChatBot System Integration Test Suite
# 전체 시스템 구성 요소를 테스트하고 검증하는 종합 도구
# Usage: ./system-test.sh [--domain your-domain.com] [--comprehensive] [--fix-issues]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PROJECT_NAME="edutech-chatbot"
PROJECT_PATH="/var/www/${PROJECT_NAME}"
DATABASE_PATH="${PROJECT_PATH}/data/edutech.db"
FILES_PATH="${PROJECT_PATH}/data/files"

# Test parameters
DOMAIN="localhost"
COMPREHENSIVE_TEST=false
FIX_ISSUES=false
TIMEOUT=30

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
ISSUES_FOUND=()
FIXES_APPLIED=()

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${PURPLE}[TEST]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --comprehensive)
            COMPREHENSIVE_TEST=true
            shift
            ;;
        --fix-issues)
            FIX_ISSUES=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "EduTech ChatBot System Test Suite"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --domain DOMAIN       Domain to test (default: localhost)"
            echo "  --comprehensive       Run comprehensive tests including load testing"
            echo "  --fix-issues          Attempt to automatically fix found issues"
            echo "  --timeout SECONDS     HTTP request timeout (default: 30)"
            echo "  --help               Show this help message"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              EduTech ChatBot System Test Suite                ║"
    echo "║                    Comprehensive Validation                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Domain: $DOMAIN"
    echo "Comprehensive: $COMPREHENSIVE_TEST"
    echo "Auto-fix: $FIX_ISSUES"
    echo "Timeout: ${TIMEOUT}s"
    echo
}

# Test result functions
test_start() {
    ((TESTS_RUN++))
    log_test "$1"
}

test_pass() {
    ((TESTS_PASSED++))
    log_success "$1"
}

test_fail() {
    ((TESTS_FAILED++))
    log_error "$1"
    ISSUES_FOUND+=("$1")
}

test_warn() {
    log_warning "$1"
}

# Fix attempt function
attempt_fix() {
    if [[ "$FIX_ISSUES" == "true" ]]; then
        log_info "Attempting to fix: $1"
        if eval "$2"; then
            log_success "Fixed: $1"
            FIXES_APPLIED+=("$1")
            return 0
        else
            log_error "Failed to fix: $1"
            return 1
        fi
    else
        log_info "Issue found (use --fix-issues to auto-fix): $1"
        return 1
    fi
}

# System prerequisites tests
test_system_requirements() {
    echo -e "${CYAN}=== System Requirements Test ===${NC}"
    
    test_start "Checking macOS environment"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        test_pass "Running on macOS"
    else
        test_fail "Not running on macOS"
    fi
    
    test_start "Checking Node.js version"
    if command -v node &> /dev/null; then
        local node_version=$(node -v | sed 's/v//')
        local major_version=$(echo $node_version | cut -d'.' -f1)
        if [[ $major_version -ge 18 ]]; then
            test_pass "Node.js $node_version (>= 18.0.0)"
        else
            test_fail "Node.js $node_version too old (need >= 18.0.0)"
            attempt_fix "Node.js version" "brew install node@18"
        fi
    else
        test_fail "Node.js not installed"
        attempt_fix "Node.js installation" "brew install node"
    fi
    
    test_start "Checking required commands"
    local required_commands=("npm" "sqlite3" "pm2" "nginx" "git" "curl")
    for cmd in "${required_commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            test_pass "$cmd command available"
        else
            test_fail "$cmd command not found"
            case $cmd in
                "pm2") attempt_fix "PM2 installation" "npm install -g pm2" ;;
                "nginx") attempt_fix "Nginx installation" "brew install nginx" ;;
                "sqlite3") attempt_fix "SQLite installation" "brew install sqlite" ;;
            esac
        fi
    done
    
    echo
}

# Project structure tests
test_project_structure() {
    echo -e "${CYAN}=== Project Structure Test ===${NC}"
    
    test_start "Checking project directory"
    if [[ -d "$PROJECT_PATH" ]]; then
        test_pass "Project directory exists: $PROJECT_PATH"
    else
        test_fail "Project directory missing: $PROJECT_PATH"
        return 1
    fi
    
    test_start "Checking essential files"
    local essential_files=(
        "package.json"
        "prisma/schema.prisma" 
        "ecosystem.config.js"
        ".env"
    )
    
    cd "$PROJECT_PATH"
    for file in "${essential_files[@]}"; do
        if [[ -f "$file" ]]; then
            test_pass "Essential file exists: $file"
        else
            test_fail "Essential file missing: $file"
        fi
    done
    
    test_start "Checking data directories"
    local data_dirs=(
        "data"
        "data/files"  
        "logs"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            test_pass "Data directory exists: $dir"
        else
            test_fail "Data directory missing: $dir"
            attempt_fix "Data directory $dir" "mkdir -p $dir"
        fi
    done
    
    echo
}

# Database tests  
test_database() {
    echo -e "${CYAN}=== Database Test ===${NC}"
    
    test_start "Checking database file"
    if [[ -f "$DATABASE_PATH" ]]; then
        test_pass "Database file exists: $DATABASE_PATH"
    else
        test_fail "Database file missing: $DATABASE_PATH"
        return 1
    fi
    
    test_start "Checking database integrity"
    if sqlite3 "$DATABASE_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
        test_pass "Database integrity check passed"
    else
        test_fail "Database integrity check failed"
        return 1
    fi
    
    test_start "Checking database schema"
    local tables=$(sqlite3 "$DATABASE_PATH" ".tables")
    local expected_tables=("textbooks" "passage_sets" "questions" "system_prompts")
    
    for table in "${expected_tables[@]}"; do
        if echo "$tables" | grep -q "$table"; then
            test_pass "Table exists: $table"
        else
            test_fail "Table missing: $table"
        fi
    done
    
    if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
        test_start "Checking database data"
        local textbook_count=$(sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM textbooks;")
        local passage_count=$(sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM passage_sets;")
        local question_count=$(sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM questions;")
        
        test_pass "Database statistics: ${textbook_count} textbooks, ${passage_count} passages, ${question_count} questions"
        
        if [[ $textbook_count -eq 0 ]]; then
            test_warn "No textbooks found in database"
        fi
    fi
    
    echo
}

# PM2 process tests
test_pm2_processes() {
    echo -e "${CYAN}=== PM2 Process Test ===${NC}"
    
    test_start "Checking PM2 processes"
    if pm2 list 2>/dev/null | grep -q "edutech"; then
        test_pass "PM2 processes found"
    else
        test_fail "No PM2 processes found"
        attempt_fix "PM2 processes" "cd $PROJECT_PATH && pm2 start ecosystem.config.js"
        return 1
    fi
    
    local processes=("edutech-api" "edutech-web" "edutech-static")
    for process in "${processes[@]}"; do
        test_start "Checking PM2 process: $process"
        if pm2 list 2>/dev/null | grep -q "$process.*online"; then
            test_pass "Process online: $process"
        else
            test_fail "Process not online: $process"
            attempt_fix "Process $process" "pm2 restart $process"
        fi
    done
    
    # Check process resource usage
    if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
        test_start "Checking process resource usage"
        pm2 monit --format=json 2>/dev/null | head -50 || test_warn "Could not get process stats"
    fi
    
    echo
}

# HTTP service tests
test_http_services() {
    echo -e "${CYAN}=== HTTP Services Test ===${NC}"
    
    # Test frontend
    test_start "Testing frontend service (port 3000)"
    if curl -s --max-time $TIMEOUT "http://localhost:3000" > /dev/null; then
        test_pass "Frontend responding on port 3000"
    else
        test_fail "Frontend not responding on port 3000"
        attempt_fix "Frontend service" "pm2 restart edutech-web"
    fi
    
    # Test backend API
    test_start "Testing backend API (port 3001)"
    if curl -s --max-time $TIMEOUT "http://localhost:3001/health" > /dev/null; then
        test_pass "Backend API responding on port 3001"
    else
        test_fail "Backend API not responding on port 3001"  
        attempt_fix "Backend API" "pm2 restart edutech-api"
    fi
    
    # Test static files
    test_start "Testing static file server (port 8080)"  
    if curl -s --max-time $TIMEOUT "http://localhost:8080" > /dev/null; then
        test_pass "Static file server responding on port 8080"
    else
        test_fail "Static file server not responding on port 8080"
        attempt_fix "Static server" "pm2 restart edutech-static"
    fi
    
    echo
}

# API endpoint tests
test_api_endpoints() {
    echo -e "${CYAN}=== API Endpoints Test ===${NC}"
    
    local base_url="http://localhost:3001/api"
    
    # Health check
    test_start "Testing health endpoint"
    local health_response=$(curl -s --max-time $TIMEOUT "$base_url/health" || echo "")
    if [[ -n "$health_response" ]]; then
        test_pass "Health endpoint responding"
    else
        test_fail "Health endpoint not responding"
    fi
    
    # Admin dashboard stats
    test_start "Testing admin dashboard stats"
    if curl -s --max-time $TIMEOUT "$base_url/admin/dashboard/stats" | grep -q "success"; then
        test_pass "Admin dashboard stats endpoint working"
    else
        test_fail "Admin dashboard stats endpoint failed"
    fi
    
    # Test with sample QR code (if exists)
    if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
        local sample_qr=$(sqlite3 "$DATABASE_PATH" "SELECT qrCode FROM passage_sets LIMIT 1;" 2>/dev/null || echo "")
        if [[ -n "$sample_qr" ]]; then
            test_start "Testing chat endpoint with sample QR: $sample_qr"
            if curl -s --max-time $TIMEOUT "$base_url/chat/$sample_qr/passage" | grep -q "success"; then
                test_pass "Chat passage endpoint working"
            else
                test_fail "Chat passage endpoint failed"
            fi
        else
            test_warn "No sample QR codes found for testing"
        fi
    fi
    
    echo
}

# Nginx configuration tests
test_nginx_configuration() {
    echo -e "${CYAN}=== Nginx Configuration Test ===${NC}"
    
    test_start "Checking Nginx status"
    if pgrep nginx > /dev/null; then
        test_pass "Nginx is running"
    else
        test_fail "Nginx is not running"
        attempt_fix "Nginx startup" "sudo nginx -s start || sudo brew services start nginx"
        return 1
    fi
    
    test_start "Testing Nginx configuration"
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        test_pass "Nginx configuration is valid"
    else
        test_fail "Nginx configuration has errors"
        return 1
    fi
    
    test_start "Checking site configuration"
    local site_config="/etc/nginx/sites-enabled/$PROJECT_NAME"
    if [[ -f "$site_config" ]]; then
        test_pass "Site configuration exists"
    else
        test_fail "Site configuration missing"
    fi
    
    echo
}

# External domain tests (if domain provided)
test_external_domain() {
    if [[ "$DOMAIN" == "localhost" ]]; then
        return 0
    fi
    
    echo -e "${CYAN}=== External Domain Test ===${NC}"
    
    test_start "Testing DNS resolution for $DOMAIN"
    if dig +short "$DOMAIN" > /dev/null; then
        test_pass "DNS resolves for $DOMAIN"
    else
        test_fail "DNS does not resolve for $DOMAIN"
        return 1
    fi
    
    test_start "Testing HTTPS connectivity to $DOMAIN"
    if curl -s --max-time $TIMEOUT "https://$DOMAIN" > /dev/null; then
        test_pass "HTTPS connection successful to $DOMAIN"
    else
        test_fail "HTTPS connection failed to $DOMAIN"
    fi
    
    test_start "Testing API subdomain"
    if curl -s --max-time $TIMEOUT "https://api.$DOMAIN/health" > /dev/null; then
        test_pass "API subdomain working"
    else
        test_fail "API subdomain not working"
    fi
    
    # Cloudflare tunnel tests
    if command -v cloudflared &> /dev/null; then
        test_start "Checking Cloudflare tunnel status"
        if cloudflared tunnel list 2>/dev/null | grep -q "edutech-chatbot.*HEALTHY"; then
            test_pass "Cloudflare tunnel is healthy"
        else
            test_warn "Cloudflare tunnel not healthy or not found"
        fi
    fi
    
    echo
}

# Performance tests (comprehensive mode)
test_performance() {
    if [[ "$COMPREHENSIVE_TEST" != "true" ]]; then
        return 0
    fi
    
    echo -e "${CYAN}=== Performance Test ===${NC}"
    
    test_start "Testing response times"
    
    # Frontend response time
    local frontend_time=$(curl -o /dev/null -s -w '%{time_total}' "http://localhost:3000" || echo "999")
    if [[ $(echo "$frontend_time < 5.0" | bc -l) -eq 1 ]]; then
        test_pass "Frontend response time: ${frontend_time}s"
    else
        test_warn "Frontend slow response time: ${frontend_time}s"
    fi
    
    # API response time
    local api_time=$(curl -o /dev/null -s -w '%{time_total}' "http://localhost:3001/api/health" || echo "999")
    if [[ $(echo "$api_time < 2.0" | bc -l) -eq 1 ]]; then
        test_pass "API response time: ${api_time}s"
    else
        test_warn "API slow response time: ${api_time}s"
    fi
    
    # Database query performance
    test_start "Testing database query performance"
    local query_time=$(time (sqlite3 "$DATABASE_PATH" "SELECT COUNT(*) FROM passage_sets;") 2>&1 | grep real | awk '{print $2}')
    test_pass "Database query time: $query_time"
    
    # Memory usage
    test_start "Checking memory usage"
    local memory_usage=$(ps aux | grep -E "(node|nginx)" | grep -v grep | awk '{sum += $4} END {print sum}')
    test_pass "Total memory usage: ${memory_usage}%"
    
    echo
}

# Security tests
test_security() {
    if [[ "$COMPREHENSIVE_TEST" != "true" ]]; then
        return 0
    fi
    
    echo -e "${CYAN}=== Security Test ===${NC}"
    
    test_start "Checking file permissions"
    if [[ -r "$DATABASE_PATH" ]] && [[ ! -w "$DATABASE_PATH" || $(stat -f%p "$DATABASE_PATH") =~ 6.. ]]; then
        test_pass "Database file permissions are secure"
    else
        test_warn "Database file permissions may be too permissive"
    fi
    
    test_start "Checking for exposed sensitive files"
    local sensitive_files=(".env" "ecosystem.config.js" "prisma/schema.prisma")
    for file in "${sensitive_files[@]}"; do
        if curl -s "http://localhost:3000/$file" | grep -q "404\|403"; then
            test_pass "Sensitive file not exposed: $file"
        else
            test_fail "Sensitive file may be exposed: $file"
        fi
    done
    
    test_start "Testing CORS headers"
    local cors_headers=$(curl -s -D- "http://localhost:3001/api/health" | grep -i "access-control")
    if [[ -n "$cors_headers" ]]; then
        test_pass "CORS headers present"
    else
        test_warn "CORS headers not found"
    fi
    
    echo
}

# Backup system tests
test_backup_system() {
    if [[ "$COMPREHENSIVE_TEST" != "true" ]]; then
        return 0
    fi
    
    echo -e "${CYAN}=== Backup System Test ===${NC}"
    
    test_start "Checking backup directories"
    if [[ -d "/var/backups/$PROJECT_NAME" ]]; then
        test_pass "Backup directory exists"
    else
        test_fail "Backup directory missing"
        attempt_fix "Backup directory" "sudo mkdir -p /var/backups/$PROJECT_NAME && sudo chown $(whoami) /var/backups/$PROJECT_NAME"
    fi
    
    test_start "Testing backup script"
    if [[ -x "$PROJECT_PATH/scripts/backup-restore.sh" ]]; then
        test_pass "Backup script is executable"
        
        # Test backup creation
        if "$PROJECT_PATH/scripts/backup-restore.sh" backup --db-only > /dev/null 2>&1; then
            test_pass "Backup creation test successful"
        else
            test_fail "Backup creation test failed"
        fi
    else
        test_fail "Backup script not found or not executable"
    fi
    
    test_start "Checking scheduled backups"
    if crontab -l 2>/dev/null | grep -q "backup-restore.sh"; then
        test_pass "Automatic backups are scheduled"
    else
        test_warn "No automatic backups scheduled"
    fi
    
    echo
}

# Generate test report
generate_report() {
    echo -e "${CYAN}=== Test Report ===${NC}"
    echo
    echo "📊 Test Summary:"
    echo "   Total Tests: $TESTS_RUN"
    echo "   Passed: $TESTS_PASSED"
    echo "   Failed: $TESTS_FAILED"
    echo "   Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
    echo
    
    if [[ ${#ISSUES_FOUND[@]} -gt 0 ]]; then
        echo "⚠️  Issues Found:"
        for issue in "${ISSUES_FOUND[@]}"; do
            echo "   • $issue"
        done
        echo
    fi
    
    if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
        echo "🔧 Fixes Applied:"
        for fix in "${FIXES_APPLIED[@]}"; do
            echo "   • $fix"
        done
        echo
    fi
    
    # Overall status
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! System is healthy.${NC}"
        return 0
    elif [[ $TESTS_FAILED -lt 5 ]]; then
        echo -e "${YELLOW}⚠️  Minor issues found. System is mostly functional.${NC}"
        return 1
    else
        echo -e "${RED}❌ Significant issues found. System may not be functioning properly.${NC}"
        return 2
    fi
}

# Main test execution
main() {
    print_banner
    
    # Run test suites
    test_system_requirements
    test_project_structure
    test_database  
    test_pm2_processes
    test_http_services
    test_api_endpoints
    test_nginx_configuration
    test_external_domain
    test_performance
    test_security
    test_backup_system
    
    # Generate final report
    echo
    generate_report
    
    # Save detailed report to file
    local report_file="$PROJECT_PATH/logs/system-test-$(date +%Y%m%d_%H%M%S).log"
    {
        echo "EduTech ChatBot System Test Report"
        echo "Generated: $(date)"
        echo "Domain: $DOMAIN"
        echo "Comprehensive: $COMPREHENSIVE_TEST"
        echo ""
        echo "Summary: $TESTS_PASSED/$TESTS_RUN tests passed"
        echo ""
        echo "Issues:"
        printf '%s\n' "${ISSUES_FOUND[@]}"
        echo ""
        echo "Fixes:"
        printf '%s\n' "${FIXES_APPLIED[@]}"
    } > "$report_file"
    
    echo "📄 Detailed report saved to: $report_file"
    echo
}

# Error handling
trap 'log_error "Test execution failed at line $LINENO"' ERR

# Run main function
main "$@"