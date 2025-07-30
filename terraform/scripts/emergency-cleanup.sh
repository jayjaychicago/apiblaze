#!/bin/bash

# ApiBlaze Emergency Cleanup Script
# Usage: ./scripts/emergency-cleanup.sh
# This script manually removes AWS resources when Terraform fails
# WARNING: This will permanently delete all ApiBlaze resources!

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
    echo -e "${RED}$message${NC}"
    read -p "Type 'EMERGENCY' to confirm: " confirmation
    if [ "$confirmation" != "EMERGENCY" ]; then
        print_status "INFO" "Emergency cleanup cancelled"
        exit 0
    fi
}

echo "🚨 ApiBlaze Emergency Cleanup Script"
echo "===================================="
print_status "WARNING" "This script will manually delete ALL ApiBlaze AWS resources!"
print_status "WARNING" "Use this only when Terraform rollback fails!"
confirm_action "This action cannot be undone. All data will be permanently lost."

# Check AWS CLI is available
if ! command -v aws &> /dev/null; then
    print_status "ERROR" "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_status "ERROR" "AWS credentials not configured or invalid"
    exit 1
fi

print_status "INFO" "Starting emergency cleanup..."

# 1. Remove Lambda functions
echo ""
print_status "INFO" "Removing Lambda functions..."
LAMBDA_FUNCTIONS=(
    "apiblaze-admin-api"
    "apiblaze-oauth-handler"
    "apiblaze-oauth-callback"
    "apiblaze-github-webhook"
    "apiblaze-config-change-handler"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$func" &> /dev/null; then
        print_status "INFO" "Removing Lambda function: $func"
        aws lambda delete-function --function-name "$func"
        print_status "SUCCESS" "Removed: $func"
    else
        print_status "INFO" "Lambda function not found: $func"
    fi
done

# 2. Remove DynamoDB tables
echo ""
print_status "INFO" "Removing DynamoDB tables..."
DYNAMODB_TABLES=(
    "apiblaze-users"
    "apiblaze-customers"
    "apiblaze-api-keys"
    "apiblaze-user-project-access"
    "apiblaze-customer-oauth-configs"
    "apiblaze-oauth-tokens"
)

for table in "${DYNAMODB_TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$table" &> /dev/null; then
        print_status "INFO" "Removing DynamoDB table: $table"
        aws dynamodb delete-table --table-name "$table"
        print_status "SUCCESS" "Removed: $table"
    else
        print_status "INFO" "DynamoDB table not found: $table"
    fi
done

# 3. Remove API Gateway
echo ""
print_status "INFO" "Removing API Gateway..."
API_GATEWAY_ID=$(aws apigateway get-rest-apis --query 'items[?contains(name, `apiblaze`)].id' --output text 2>/dev/null || echo "")

if [ -n "$API_GATEWAY_ID" ]; then
    print_status "INFO" "Removing API Gateway: $API_GATEWAY_ID"
    aws apigateway delete-rest-api --rest-api-id "$API_GATEWAY_ID"
    print_status "SUCCESS" "Removed API Gateway: $API_GATEWAY_ID"
else
    print_status "INFO" "API Gateway not found"
fi

# 4. Remove Cognito resources
echo ""
print_status "INFO" "Removing Cognito resources..."

# Get User Pool ID
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-items 20 --query 'UserPools[?contains(Name, `apiblaze`)].Id' --output text 2>/dev/null || echo "")

if [ -n "$USER_POOL_ID" ]; then
    print_status "INFO" "Removing Cognito User Pool: $USER_POOL_ID"
    
    # Remove user pool clients first
    CLIENT_IDS=$(aws cognito-idp list-user-pool-clients --user-pool-id "$USER_POOL_ID" --query 'UserPoolClients[].ClientId' --output text 2>/dev/null || echo "")
    for client_id in $CLIENT_IDS; do
        print_status "INFO" "Removing User Pool Client: $client_id"
        aws cognito-idp delete-user-pool-client --user-pool-id "$USER_POOL_ID" --client-id "$client_id"
    done
    
    # Remove user pool
    aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID"
    print_status "SUCCESS" "Removed Cognito User Pool: $USER_POOL_ID"
else
    print_status "INFO" "Cognito User Pool not found"
fi

# Get Identity Pool ID
IDENTITY_POOL_ID=$(aws cognito-identity list-identity-pools --max-results 20 --query 'IdentityPools[?contains(IdentityPoolName, `apiblaze`)].IdentityPoolId' --output text 2>/dev/null || echo "")

if [ -n "$IDENTITY_POOL_ID" ]; then
    print_status "INFO" "Removing Cognito Identity Pool: $IDENTITY_POOL_ID"
    aws cognito-identity delete-identity-pool --identity-pool-id "$IDENTITY_POOL_ID"
    print_status "SUCCESS" "Removed Cognito Identity Pool: $IDENTITY_POOL_ID"
else
    print_status "INFO" "Cognito Identity Pool not found"
fi

# 5. Remove S3 buckets
echo ""
print_status "INFO" "Removing S3 buckets..."
S3_BUCKETS=(
    "apiblaze-deployment-artifacts"
    "apiblaze-terraform-state-240232487139"
)

for bucket in "${S3_BUCKETS[@]}"; do
    if aws s3 ls "s3://$bucket" &> /dev/null; then
        print_status "INFO" "Removing S3 bucket: $bucket"
        
        # Remove all objects and versions
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        
        # Remove delete markers
        aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json | \
        jq -r '.[] | "\(.Key) \(.VersionId)"' | \
        while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Remove bucket
        aws s3 rb "s3://$bucket" --force
        print_status "SUCCESS" "Removed S3 bucket: $bucket"
    else
        print_status "INFO" "S3 bucket not found: $bucket"
    fi
done

# 6. Remove IAM roles
echo ""
print_status "INFO" "Removing IAM roles..."
IAM_ROLES=(
    "apiblaze_lambda_role"
    "apiblaze_cognito_authenticated"
)

for role in "${IAM_ROLES[@]}"; do
    if aws iam get-role --role-name "$role" &> /dev/null; then
        print_status "INFO" "Removing IAM role: $role"
        
        # Detach policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        for policy in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Remove inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null || echo "")
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
        done
        
        # Remove role
        aws iam delete-role --role-name "$role"
        print_status "SUCCESS" "Removed IAM role: $role"
    else
        print_status "INFO" "IAM role not found: $role"
    fi
done

# 7. Remove CloudWatch log groups
echo ""
print_status "INFO" "Removing CloudWatch log groups..."
LOG_GROUPS=(
    "/aws/lambda/apiblaze-admin-api"
    "/aws/lambda/apiblaze-oauth-handler"
    "/aws/lambda/apiblaze-oauth-callback"
    "/aws/lambda/apiblaze-github-webhook"
    "/aws/lambda/apiblaze-config-change-handler"
)

for log_group in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[].logGroupName' --output text | grep -q "$log_group"; then
        print_status "INFO" "Removing CloudWatch log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group"
        print_status "SUCCESS" "Removed log group: $log_group"
    else
        print_status "INFO" "CloudWatch log group not found: $log_group"
    fi
done

echo ""
print_status "SUCCESS" "🎉 Emergency cleanup completed!"
print_status "INFO" "All ApiBlaze AWS resources have been removed"
print_status "WARNING" "You may need to manually clean up any remaining resources"
print_status "INFO" "Run 'terraform init' and 'terraform apply' to redeploy" 