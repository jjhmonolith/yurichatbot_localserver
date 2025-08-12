#!/bin/bash

# EduTech ChatBot Backup & Restore System
# SQLite 특성을 활용한 효율적인 백업/복구 솔루션
# Usage: ./backup-restore.sh [backup|restore|cleanup|status] [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_NAME="edutech-chatbot"
PROJECT_PATH="/var/www/${PROJECT_NAME}"
BACKUP_BASE_PATH="/var/backups/${PROJECT_NAME}"
CLOUD_BACKUP_PATH="s3://your-backup-bucket/edutech-backups"
DATABASE_PATH="${PROJECT_PATH}/data/edutech.db"
FILES_PATH="${PROJECT_PATH}/data/files"
MAX_LOCAL_BACKUPS=30
MAX_CLOUD_BACKUPS=90

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_usage() {
    echo "EduTech ChatBot Backup & Restore System"
    echo ""
    echo "Usage:"
    echo "  $0 backup [--full|--db-only|--files-only] [--cloud]"
    echo "  $0 restore <backup-name> [--db-only|--files-only]"
    echo "  $0 list [--local|--cloud]"
    echo "  $0 cleanup [--dry-run]"
    echo "  $0 status"
    echo "  $0 schedule [--enable|--disable]"
    echo ""
    echo "Examples:"
    echo "  $0 backup --full --cloud          # Full backup to local and cloud"
    echo "  $0 backup --db-only               # Database only backup"
    echo "  $0 restore backup_20241201_143022 # Restore specific backup"
    echo "  $0 list --cloud                   # List cloud backups"
    echo "  $0 cleanup --dry-run               # Preview cleanup actions"
    echo ""
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v sqlite3 &> /dev/null; then
        missing_deps+=("sqlite3")
    fi
    
    if [[ "$1" == *"--cloud"* ]] && ! command -v aws &> /dev/null; then
        missing_deps+=("aws-cli")
    fi
    
    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: brew install ${missing_deps[*]}"
        exit 1
    fi
}

# Create backup directories
ensure_backup_dirs() {
    mkdir -p "${BACKUP_BASE_PATH}/database"
    mkdir -p "${BACKUP_BASE_PATH}/files"
    mkdir -p "${BACKUP_BASE_PATH}/full"
    mkdir -p "${BACKUP_BASE_PATH}/logs"
}

# Generate backup name with timestamp
generate_backup_name() {
    local prefix=$1
    echo "${prefix}_$(date +%Y%m%d_%H%M%S)"
}

# Database backup with SQLite-specific optimizations
backup_database() {
    local backup_name=$1
    local backup_path="${BACKUP_BASE_PATH}/database/${backup_name}.db"
    
    log_info "Creating database backup: ${backup_name}"
    
    # Ensure database is in a consistent state
    sqlite3 "$DATABASE_PATH" "PRAGMA wal_checkpoint(FULL);"
    
    # Create backup using SQLite's backup API (atomic and safe)
    sqlite3 "$DATABASE_PATH" ".backup '${backup_path}'"
    
    # Verify backup integrity
    if sqlite3 "$backup_path" "PRAGMA integrity_check;" | grep -q "ok"; then
        log_success "Database backup verified: ${backup_name}.db"
        echo "$backup_path"
    else
        log_error "Database backup integrity check failed"
        rm -f "$backup_path"
        exit 1
    fi
}

# Files backup with compression
backup_files() {
    local backup_name=$1
    local backup_path="${BACKUP_BASE_PATH}/files/${backup_name}.tar.gz"
    
    log_info "Creating files backup: ${backup_name}"
    
    if [[ -d "$FILES_PATH" ]]; then
        tar -czf "$backup_path" -C "$(dirname $FILES_PATH)" "$(basename $FILES_PATH)"
        log_success "Files backup created: ${backup_name}.tar.gz"
        echo "$backup_path"
    else
        log_warning "Files directory not found: $FILES_PATH"
        return 1
    fi
}

# Full backup (database + files + metadata)
backup_full() {
    local backup_name=$1
    local backup_dir="${BACKUP_BASE_PATH}/full/${backup_name}"
    
    log_info "Creating full backup: ${backup_name}"
    mkdir -p "$backup_dir"
    
    # Backup database
    local db_backup=$(backup_database "${backup_name}")
    cp "$db_backup" "$backup_dir/"
    
    # Backup files
    if backup_files "${backup_name}" > /dev/null 2>&1; then
        local files_backup="${BACKUP_BASE_PATH}/files/${backup_name}.tar.gz"
        cp "$files_backup" "$backup_dir/"
    fi
    
    # Create metadata
    cat > "$backup_dir/metadata.json" << EOF
{
  "backup_name": "${backup_name}",
  "created_at": "$(date -Iseconds)",
  "type": "full",
  "database_size": $(stat -f%z "$db_backup" 2>/dev/null || echo 0),
  "files_size": $(stat -f%z "$files_backup" 2>/dev/null || echo 0),
  "hostname": "$(hostname)",
  "project_version": "$(git -C $PROJECT_PATH rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    # Create archive
    local full_backup_path="${BACKUP_BASE_PATH}/full/${backup_name}.tar.gz"
    tar -czf "$full_backup_path" -C "${BACKUP_BASE_PATH}/full" "$backup_name"
    rm -rf "$backup_dir"
    
    log_success "Full backup created: ${backup_name}.tar.gz"
    echo "$full_backup_path"
}

# Upload to cloud storage
upload_to_cloud() {
    local backup_path=$1
    local backup_name=$(basename "$backup_path")
    
    log_info "Uploading to cloud: $backup_name"
    
    if aws s3 cp "$backup_path" "${CLOUD_BACKUP_PATH}/" --quiet; then
        log_success "Cloud upload completed: $backup_name"
    else
        log_error "Cloud upload failed: $backup_name"
        return 1
    fi
}

# Restore database
restore_database() {
    local backup_name=$1
    local backup_path="${BACKUP_BASE_PATH}/database/${backup_name}.db"
    
    if [[ ! -f "$backup_path" ]]; then
        log_error "Database backup not found: $backup_path"
        return 1
    fi
    
    log_info "Restoring database from: $backup_name"
    
    # Stop services
    pm2 stop edutech-api 2>/dev/null || true
    
    # Backup current database
    local current_backup="${DATABASE_PATH}.pre-restore-$(date +%Y%m%d_%H%M%S)"
    cp "$DATABASE_PATH" "$current_backup"
    log_info "Current database backed up to: $current_backup"
    
    # Restore database
    cp "$backup_path" "$DATABASE_PATH"
    
    # Verify restored database
    if sqlite3 "$DATABASE_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
        log_success "Database restored successfully"
        
        # Restart services
        pm2 start edutech-api 2>/dev/null || true
        
        # Run any necessary migrations
        if [[ -f "${PROJECT_PATH}/prisma/schema.prisma" ]]; then
            cd "$PROJECT_PATH"
            npx prisma db push --accept-data-loss || log_warning "Schema update failed"
        fi
    else
        log_error "Restored database integrity check failed, rolling back..."
        cp "$current_backup" "$DATABASE_PATH"
        pm2 start edutech-api 2>/dev/null || true
        return 1
    fi
}

# Restore files
restore_files() {
    local backup_name=$1
    local backup_path="${BACKUP_BASE_PATH}/files/${backup_name}.tar.gz"
    
    if [[ ! -f "$backup_path" ]]; then
        log_error "Files backup not found: $backup_path"
        return 1
    fi
    
    log_info "Restoring files from: $backup_name"
    
    # Backup current files
    if [[ -d "$FILES_PATH" ]]; then
        local current_backup="${FILES_PATH}.pre-restore-$(date +%Y%m%d_%H%M%S)"
        mv "$FILES_PATH" "$current_backup"
        log_info "Current files backed up to: $current_backup"
    fi
    
    # Restore files
    mkdir -p "$(dirname $FILES_PATH)"
    tar -xzf "$backup_path" -C "$(dirname $FILES_PATH)"
    
    log_success "Files restored successfully"
}

# List backups
list_backups() {
    local location=$1
    
    case $location in
        "local")
            echo "Local Backups:"
            echo "=============="
            echo ""
            echo "Database Backups:"
            ls -lah "${BACKUP_BASE_PATH}/database/" 2>/dev/null || echo "No database backups found"
            echo ""
            echo "Files Backups:"
            ls -lah "${BACKUP_BASE_PATH}/files/" 2>/dev/null || echo "No file backups found"
            echo ""
            echo "Full Backups:"
            ls -lah "${BACKUP_BASE_PATH}/full/" 2>/dev/null || echo "No full backups found"
            ;;
        "cloud")
            echo "Cloud Backups:"
            echo "=============="
            aws s3 ls "${CLOUD_BACKUP_PATH}/" --human-readable || echo "No cloud backups found"
            ;;
        *)
            list_backups "local"
            echo ""
            list_backups "cloud"
            ;;
    esac
}

# Cleanup old backups
cleanup_backups() {
    local dry_run=$1
    
    log_info "Cleaning up old backups (keeping $MAX_LOCAL_BACKUPS local, $MAX_CLOUD_BACKUPS cloud)..."
    
    # Local cleanup
    for backup_type in "database" "files" "full"; do
        local backup_dir="${BACKUP_BASE_PATH}/${backup_type}"
        if [[ -d "$backup_dir" ]]; then
            local old_backups=$(ls -t "$backup_dir" | tail -n +$((MAX_LOCAL_BACKUPS + 1)))
            for backup in $old_backups; do
                if [[ "$dry_run" == "true" ]]; then
                    echo "Would delete: $backup_dir/$backup"
                else
                    rm -f "$backup_dir/$backup"
                    log_info "Deleted old backup: $backup"
                fi
            done
        fi
    done
    
    # Cloud cleanup (if configured)
    if command -v aws &> /dev/null && aws s3 ls "$CLOUD_BACKUP_PATH" &>/dev/null; then
        local old_cloud_backups=$(aws s3 ls "$CLOUD_BACKUP_PATH/" --recursive | sort -k1,2 | head -n -$MAX_CLOUD_BACKUPS | awk '{print $4}')
        for backup in $old_cloud_backups; do
            if [[ "$dry_run" == "true" ]]; then
                echo "Would delete from cloud: $backup"
            else
                aws s3 rm "s3://$(echo $CLOUD_BACKUP_PATH | cut -d'/' -f3-)/$backup"
                log_info "Deleted old cloud backup: $backup"
            fi
        done
    fi
    
    if [[ "$dry_run" != "true" ]]; then
        log_success "Cleanup completed"
    fi
}

# Show backup status and statistics
show_status() {
    echo "EduTech ChatBot Backup Status"
    echo "============================="
    echo ""
    
    # Database info
    if [[ -f "$DATABASE_PATH" ]]; then
        local db_size=$(stat -f%z "$DATABASE_PATH" 2>/dev/null || stat -c%s "$DATABASE_PATH" 2>/dev/null || echo 0)
        local db_modified=$(stat -f%m "$DATABASE_PATH" 2>/dev/null || stat -c%Y "$DATABASE_PATH" 2>/dev/null)
        echo "Database: $(( db_size / 1024 / 1024 )) MB (modified: $(date -r $db_modified))"
    else
        echo "Database: Not found"
    fi
    
    # Files info
    if [[ -d "$FILES_PATH" ]]; then
        local files_count=$(find "$FILES_PATH" -type f | wc -l)
        local files_size=$(du -sk "$FILES_PATH" | cut -f1)
        echo "Files: $files_count files, $(( files_size / 1024 )) MB"
    else
        echo "Files: Directory not found"
    fi
    
    echo ""
    echo "Local Backups:"
    for backup_type in "database" "files" "full"; do
        local backup_dir="${BACKUP_BASE_PATH}/${backup_type}"
        local count=$(ls "$backup_dir" 2>/dev/null | wc -l)
        local size=$(du -sk "$backup_dir" 2>/dev/null | cut -f1 || echo 0)
        echo "  $backup_type: $count backups, $(( size / 1024 )) MB"
    done
    
    echo ""
    echo "Scheduled Backups:"
    if crontab -l 2>/dev/null | grep -q "backup-restore.sh"; then
        echo "  ✅ Enabled"
        crontab -l | grep "backup-restore.sh"
    else
        echo "  ❌ Not scheduled"
    fi
}

# Schedule automatic backups
manage_schedule() {
    local action=$1
    
    case $action in
        "enable")
            # Add cron job for daily backups
            (crontab -l 2>/dev/null; echo "0 2 * * * $PWD/backup-restore.sh backup --full --cloud") | crontab -
            # Add cron job for cleanup
            (crontab -l 2>/dev/null; echo "0 3 * * 0 $PWD/backup-restore.sh cleanup") | crontab -
            log_success "Automatic backups scheduled (daily at 2 AM, cleanup weekly)"
            ;;
        "disable")
            crontab -l 2>/dev/null | grep -v "backup-restore.sh" | crontab -
            log_success "Automatic backups disabled"
            ;;
        *)
            log_error "Use --enable or --disable"
            ;;
    esac
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi
    
    local command=$1
    shift
    
    case $command in
        "backup")
            check_dependencies "$@"
            ensure_backup_dirs
            
            local backup_type="full"
            local use_cloud=false
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --full) backup_type="full"; shift ;;
                    --db-only) backup_type="database"; shift ;;
                    --files-only) backup_type="files"; shift ;;
                    --cloud) use_cloud=true; shift ;;
                    *) shift ;;
                esac
            done
            
            local backup_name=$(generate_backup_name "backup")
            local backup_path=""
            
            case $backup_type in
                "database")
                    backup_path=$(backup_database "$backup_name")
                    ;;
                "files")
                    backup_path=$(backup_files "$backup_name")
                    ;;
                "full")
                    backup_path=$(backup_full "$backup_name")
                    ;;
            esac
            
            if [[ "$use_cloud" == true ]] && [[ -n "$backup_path" ]]; then
                upload_to_cloud "$backup_path"
            fi
            ;;
            
        "restore")
            if [[ $# -eq 0 ]]; then
                log_error "Please specify backup name"
                exit 1
            fi
            
            local backup_name=$1
            local restore_type="full"
            shift
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --db-only) restore_type="database"; shift ;;
                    --files-only) restore_type="files"; shift ;;
                    *) shift ;;
                esac
            done
            
            case $restore_type in
                "database") restore_database "$backup_name" ;;
                "files") restore_files "$backup_name" ;;
                "full")
                    restore_database "$backup_name"
                    restore_files "$backup_name"
                    ;;
            esac
            ;;
            
        "list")
            local location="all"
            if [[ $# -gt 0 ]]; then
                case $1 in
                    --local) location="local" ;;
                    --cloud) location="cloud" ;;
                esac
            fi
            list_backups "$location"
            ;;
            
        "cleanup")
            local dry_run=false
            if [[ "$1" == "--dry-run" ]]; then
                dry_run=true
            fi
            cleanup_backups "$dry_run"
            ;;
            
        "status")
            show_status
            ;;
            
        "schedule")
            if [[ $# -eq 0 ]]; then
                log_error "Use --enable or --disable"
                exit 1
            fi
            manage_schedule "$1"
            ;;
            
        *)
            log_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"