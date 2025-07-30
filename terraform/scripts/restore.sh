#!/bin/bash

# ApiBlaze Restore Script
# Usage: ./scripts/restore.sh [backup_name]
# Restores Terraform state from a backup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Function to confirm action
confirm_action() {
    local message=$1
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "INFO" "Restore cancelled"
        exit 0
    fi
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_status "ERROR" "Please run this script from the terraform directory"
    exit 1
fi

# Get backup name
BACKUP_NAME=${1:-""}
BACKUP_DIR="backups"

if [ -z "$BACKUP_NAME" ]; then
    print_status "INFO" "Available backups:"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        ls -la "$BACKUP_DIR"/*.tfstate | while read line; do
            print_status "INFO" "  $line"
        done
        echo ""
        read -p "Enter backup name to restore: " BACKUP_NAME
    else
        print_status "ERROR" "No backups found in $BACKUP_DIR"
        exit 1
    fi
fi

BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME.tfstate"
METADATA_FILE="$BACKUP_DIR/$BACKUP_NAME.metadata"

echo "🔄 ApiBlaze Restore Script"
echo "========================="
print_status "INFO" "Restoring from backup: $BACKUP_NAME"

# Check if backup exists
if [ ! -f "$BACKUP_FILE" ]; then
    print_status "ERROR" "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Show backup metadata if available
if [ -f "$METADATA_FILE" ]; then
    print_status "INFO" "Backup metadata:"
    cat "$METADATA_FILE" | sed 's/^/  /'
    echo ""
fi

# Create current state backup before restore
CURRENT_BACKUP="backup-before-restore-$(date +%Y%m%d-%H%M%S).tfstate"
print_status "INFO" "Creating backup of current state: $CURRENT_BACKUP"
terraform state pull > "$CURRENT_BACKUP"

# Confirm restore
confirm_action "This will overwrite the current Terraform state with the backup."

# Restore from backup
print_status "INFO" "Restoring Terraform state..."
terraform state push "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    print_status "SUCCESS" "State restored successfully!"
    
    # Verify restore
    echo ""
    print_status "INFO" "Verifying restored state..."
    RESOURCE_COUNT=$(terraform state list | wc -l)
    print_status "SUCCESS" "Restored $RESOURCE_COUNT resources"
    
    # Show plan
    echo ""
    print_status "INFO" "Running terraform plan to check for drift..."
    terraform plan -detailed-exitcode || true
    
    echo ""
    print_status "SUCCESS" "Restore completed successfully!"
    print_status "INFO" "Current state backup saved as: $CURRENT_BACKUP"
    print_status "INFO" "Run 'terraform apply' to sync resources if needed"
    
else
    print_status "ERROR" "Failed to restore state"
    print_status "INFO" "Current state backup saved as: $CURRENT_BACKUP"
    exit 1
fi 