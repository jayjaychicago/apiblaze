#!/bin/bash

# ApiBlaze Deployment Verification Script
# Usage: ./scripts/verify-deployment.sh

set -e

echo "🔍 ApiBlaze Deployment Verification"
echo "=================================="

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

echo ""
print_status "INFO" "Checking Terraform state..."

# 1. Verify Terraform state
TERRAFORM_RESOURCES=$(terraform state list | wc -l)
print_status "SUCCESS" "Found $TERRAFORM_RESOURCES resources in Terraform state"

# 2. Check Lambda functions
echo ""
print_status "INFO" "Checking Lambda functions..."
LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `apiblaze`)].FunctionName' --output text)
LAMBDA_COUNT=$(echo "$LAMBDA_FUNCTIONS" | wc -w)

if [ "$LAMBDA_COUNT" -eq 5 ]; then
    print_status "SUCCESS" "All 5 Lambda functions deployed"
    echo "$LAMBDA_FUNCTIONS" | tr ' ' '\n' | while read func; do
        print_status "SUCCESS" "  - $func"
    done
else
    print_status "ERROR" "Expected 5 Lambda functions, found $LAMBDA_COUNT"
fi

# 3. Check DynamoDB tables
echo ""
print_status "INFO" "Checking DynamoDB tables..."
DYNAMODB_TABLES=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `apiblaze`)]' --output text)
TABLE_COUNT=$(echo "$DYNAMODB_TABLES" | wc -w)

if [ "$TABLE_COUNT" -ge 6 ]; then
    print_status "SUCCESS" "All DynamoDB tables deployed ($TABLE_COUNT tables)"
    echo "$DYNAMODB_TABLES" | tr ' ' '\n' | while read table; do
        print_status "SUCCESS" "  - $table"
    done
else
    print_status "WARNING" "Expected at least 6 DynamoDB tables, found $TABLE_COUNT"
fi

# 4. Check API Gateway endpoints
echo ""
print_status "INFO" "Checking API Gateway endpoints..."

# Get API Gateway URL from terraform output
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
WEBHOOK_URL=$(terraform output -raw github_webhook_url 2>/dev/null || echo "")

if [ -n "$API_GATEWAY_URL" ]; then
    print_status "SUCCESS" "API Gateway URL: $API_GATEWAY_URL"
    
    # Test admin endpoint
    ADMIN_RESPONSE=$(curl -s -w "%{http_code}" "$API_GATEWAY_URL" -o /tmp/admin_response)
    HTTP_CODE=$(tail -c 3 /tmp/admin_response)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        print_status "SUCCESS" "Admin endpoint responding (HTTP $HTTP_CODE)"
    else
        print_status "WARNING" "Admin endpoint returned HTTP $HTTP_CODE"
    fi
    rm -f /tmp/admin_response
else
    print_status "ERROR" "Could not get API Gateway URL from terraform output"
fi

if [ -n "$WEBHOOK_URL" ]; then
    print_status "SUCCESS" "Webhook URL: $WEBHOOK_URL"
    
    # Test webhook endpoint
    WEBHOOK_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d '{"test": "webhook"}' \
        -o /tmp/webhook_response)
    HTTP_CODE=$(tail -c 3 /tmp/webhook_response)
    if [ "$HTTP_CODE" = "400" ]; then
        print_status "SUCCESS" "Webhook endpoint responding (HTTP $HTTP_CODE - expected for invalid signature)"
    else
        print_status "WARNING" "Webhook endpoint returned HTTP $HTTP_CODE"
    fi
    rm -f /tmp/webhook_response
else
    print_status "ERROR" "Could not get webhook URL from terraform output"
fi

# 5. Check Cognito resources
echo ""
print_status "INFO" "Checking Cognito resources..."
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null || echo "")
CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id 2>/dev/null || echo "")
IDENTITY_POOL_ID=$(terraform output -raw cognito_identity_pool_id 2>/dev/null || echo "")

if [ -n "$USER_POOL_ID" ]; then
    print_status "SUCCESS" "Cognito User Pool: $USER_POOL_ID"
else
    print_status "ERROR" "Could not get Cognito User Pool ID"
fi

if [ -n "$CLIENT_ID" ]; then
    print_status "SUCCESS" "Cognito Client ID: $CLIENT_ID"
else
    print_status "ERROR" "Could not get Cognito Client ID"
fi

if [ -n "$IDENTITY_POOL_ID" ]; then
    print_status "SUCCESS" "Cognito Identity Pool: $IDENTITY_POOL_ID"
else
    print_status "ERROR" "Could not get Cognito Identity Pool ID"
fi

# 6. Check S3 buckets
echo ""
print_status "INFO" "Checking S3 buckets..."
S3_BUCKETS=$(aws s3 ls | grep apiblaze || echo "")
if [ -n "$S3_BUCKETS" ]; then
    print_status "SUCCESS" "S3 buckets found:"
    echo "$S3_BUCKETS" | while read bucket; do
        print_status "SUCCESS" "  - $bucket"
    done
else
    print_status "ERROR" "No S3 buckets found"
fi

# 7. Check IAM roles
echo ""
print_status "INFO" "Checking IAM roles..."
IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `apiblaze`)].RoleName' --output text)
ROLE_COUNT=$(echo "$IAM_ROLES" | wc -w)

if [ "$ROLE_COUNT" -ge 2 ]; then
    print_status "SUCCESS" "IAM roles deployed ($ROLE_COUNT roles)"
    echo "$IAM_ROLES" | tr ' ' '\n' | while read role; do
        print_status "SUCCESS" "  - $role"
    done
else
    print_status "WARNING" "Expected at least 2 IAM roles, found $ROLE_COUNT"
fi

# 8. Summary
echo ""
echo "=================================="
print_status "INFO" "Deployment Verification Summary"
echo "=================================="

if [ "$TERRAFORM_RESOURCES" -ge 30 ] && [ "$LAMBDA_COUNT" -eq 5 ] && [ "$TABLE_COUNT" -ge 6 ] && [ "$ROLE_COUNT" -ge 2 ]; then
    print_status "SUCCESS" "🎉 All resources appear to be deployed successfully!"
    print_status "INFO" "Your ApiBlaze infrastructure is ready for Phase 2"
else
    print_status "WARNING" "Some resources may be missing or incomplete"
    print_status "INFO" "Check the output above for specific issues"
fi

echo ""
print_status "INFO" "Next steps:"
print_status "INFO" "1. Deploy Cloudflare Worker for routing"
print_status "INFO" "2. Configure OAuth providers per customer"
print_status "INFO" "3. Test the OAuth flow"
print_status "INFO" "4. Configure DNS records" 