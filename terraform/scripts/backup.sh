#!/bin/bash

# ApiBlaze Backup Script
# Usage: ./scripts/backup.sh [backup_name]
# Creates a backup of the current Terraform state

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

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_status "ERROR" "Please run this script from the terraform directory"
    exit 1
fi

# Get backup name
BACKUP_NAME=${1:-"backup-$(date +%Y%m%d-%H%M%S)"}
BACKUP_DIR="backups"
BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME.tfstate"

echo "💾 ApiBlaze Backup Script"
echo "========================"
print_status "INFO" "Creating backup: $BACKUP_NAME"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create backup
print_status "INFO" "Pulling current Terraform state..."
terraform state pull > "$BACKUP_FILE"

if [ -s "$BACKUP_FILE" ]; then
    print_status "SUCCESS" "Backup created: $BACKUP_FILE"
    
    # Get file size
    FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    print_status "INFO" "Backup size: $FILE_SIZE"
    
    # Get resource count
    RESOURCE_COUNT=$(terraform state list | wc -l)
    print_status "INFO" "Resources in backup: $RESOURCE_COUNT"
    
    # Create metadata file
    METADATA_FILE="$BACKUP_DIR/$BACKUP_NAME.metadata"
    cat > "$METADATA_FILE" << EOF
Backup Name: $BACKUP_NAME
Created: $(date)
Resources: $RESOURCE_COUNT
File Size: $FILE_SIZE
Terraform Version: $(terraform version | head -n1)
AWS Region: $(aws configure get region)
EOF
    
    print_status "SUCCESS" "Metadata saved: $METADATA_FILE"
    
    # List existing backups
    echo ""
    print_status "INFO" "Existing backups:"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        ls -la "$BACKUP_DIR"/*.tfstate | while read line; do
            print_status "INFO" "  $line"
        done
    else
        print_status "INFO" "  No previous backups found"
    fi
    
    echo ""
    print_status "SUCCESS" "Backup completed successfully!"
    print_status "INFO" "To restore: ./scripts/restore.sh $BACKUP_NAME"
    
else
    print_status "ERROR" "Failed to create backup - file is empty"
    rm -f "$BACKUP_FILE"
    exit 1
fi 