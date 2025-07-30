#!/bin/bash

# ApiBlaze Rollback Script
# Usage: ./scripts/rollback.sh [option]
# Options:
#   complete    - Destroy all resources (default)
#   selective   - Interactive selective rollback
#   lambda      - Remove only Lambda functions
#   database    - Remove only DynamoDB tables
#   api         - Remove only API Gateway
#   cognito     - Remove only Cognito resources
#   s3          - Remove only S3 buckets

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
        print_status "INFO" "Rollback cancelled"
        exit 0
    fi
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_status "ERROR" "Please run this script from the terraform directory"
    exit 1
fi

# Get rollback option
ROLLBACK_OPTION=${1:-complete}

echo "🔄 ApiBlaze Rollback Script"
echo "==========================="
print_status "INFO" "Rollback option: $ROLLBACK_OPTION"

# Create backup before any rollback
BACKUP_FILE="backup-$(date +%Y%m%d-%H%M%S).tfstate"
print_status "INFO" "Creating backup: $BACKUP_FILE"
terraform state pull > "$BACKUP_FILE"
print_status "SUCCESS" "Backup created: $BACKUP_FILE"

case $ROLLBACK_OPTION in
    "complete")
        print_status "WARNING" "This will destroy ALL ApiBlaze resources!"
        confirm_action "This action cannot be undone. All data will be lost."
        
        print_status "INFO" "Starting complete rollback..."
        terraform destroy -auto-approve
        print_status "SUCCESS" "Complete rollback finished"
        ;;
        
    "selective")
        echo ""
        print_status "INFO" "Selective rollback options:"
        echo "1. Lambda functions only"
        echo "2. DynamoDB tables only"
        echo "3. API Gateway only"
        echo "4. Cognito resources only"
        echo "5. S3 buckets only"
        echo "6. Custom selection"
        read -p "Choose option (1-6): " choice
        
        case $choice in
            1) ./scripts/rollback.sh lambda ;;
            2) ./scripts/rollback.sh database ;;
            3) ./scripts/rollback.sh api ;;
            4) ./scripts/rollback.sh cognito ;;
            5) ./scripts/rollback.sh s3 ;;
            6) ./scripts/rollback.sh custom ;;
            *) print_status "ERROR" "Invalid choice"; exit 1 ;;
        esac
        ;;
        
    "lambda")
        print_status "INFO" "Removing Lambda functions..."
        confirm_action "This will remove all Lambda functions."
        
        terraform destroy -target=aws_lambda_function.admin_api \
                         -target=aws_lambda_function.oauth_handler \
                         -target=aws_lambda_function.oauth_callback \
                         -target=aws_lambda_function.github_webhook \
                         -target=aws_lambda_function.config_change_handler \
                         -auto-approve
        print_status "SUCCESS" "Lambda functions removed"
        ;;
        
    "database")
        print_status "WARNING" "This will remove ALL DynamoDB tables and data!"
        confirm_action "All data will be permanently lost."
        
        print_status "INFO" "Removing DynamoDB tables..."
        terraform destroy -target=aws_dynamodb_table.users \
                         -target=aws_dynamodb_table.customers \
                         -target=aws_dynamodb_table.api_keys \
                         -target=aws_dynamodb_table.user_project_access \
                         -target=aws_dynamodb_table.customer_oauth_configs \
                         -auto-approve
        print_status "SUCCESS" "DynamoDB tables removed"
        ;;
        
    "api")
        print_status "INFO" "Removing API Gateway resources..."
        confirm_action "This will remove API Gateway and all endpoints."
        
        terraform destroy -target=aws_api_gateway_deployment.main \
                         -target=aws_api_gateway_integration.admin \
                         -target=aws_api_gateway_integration.webhook \
                         -target=aws_api_gateway_method.admin \
                         -target=aws_api_gateway_method.webhook \
                         -target=aws_api_gateway_resource.admin \
                         -target=aws_api_gateway_resource.webhook \
                         -target=aws_api_gateway_rest_api.main \
                         -auto-approve
        print_status "SUCCESS" "API Gateway resources removed"
        ;;
        
    "cognito")
        print_status "WARNING" "This will remove ALL Cognito resources and user data!"
        confirm_action "All user accounts and authentication data will be lost."
        
        print_status "INFO" "Removing Cognito resources..."
        terraform destroy -target=aws_cognito_identity_pool_roles_attachment.main \
                         -target=aws_cognito_identity_pool.main \
                         -target=aws_cognito_user_pool_client.main \
                         -target=aws_cognito_user_pool.main \
                         -auto-approve
        print_status "SUCCESS" "Cognito resources removed"
        ;;
        
    "s3")
        print_status "WARNING" "This will remove ALL S3 buckets and data!"
        confirm_action "All stored files and deployment artifacts will be lost."
        
        print_status "INFO" "Removing S3 buckets..."
        terraform destroy -target=aws_s3_bucket.deployment_artifacts \
                         -target=aws_s3_bucket.terraform_state \
                         -auto-approve
        print_status "SUCCESS" "S3 buckets removed"
        ;;
        
    "custom")
        print_status "INFO" "Available resources for custom rollback:"
        terraform state list | grep aws_ | sed 's/^/  - /'
        echo ""
        read -p "Enter resource names to destroy (space-separated): " resources
        if [ -n "$resources" ]; then
            confirm_action "This will remove the specified resources."
            for resource in $resources; do
                terraform destroy -target="$resource" -auto-approve
            done
            print_status "SUCCESS" "Custom rollback completed"
        else
            print_status "INFO" "No resources specified, rollback cancelled"
        fi
        ;;
        
    *)
        print_status "ERROR" "Invalid rollback option: $ROLLBACK_OPTION"
        echo "Usage: $0 [complete|selective|lambda|database|api|cognito|s3|custom]"
        exit 1
        ;;
esac

echo ""
print_status "INFO" "Rollback completed successfully!"
print_status "INFO" "Backup saved as: $BACKUP_FILE"
print_status "INFO" "To restore from backup: terraform apply -state=$BACKUP_FILE" 