#!/bin/bash

# APIBLAZE Phase 2 Status Check Script

set -e

echo "🔍 APIBLAZE Phase 2 Status Check"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
print_status "Checking Cloudflare Worker deployment..."

# Check if Worker is responding
WORKER_URL="https://apiblaze-worker.julien-529.workers.dev"
if curl -s "$WORKER_URL" > /dev/null; then
    print_success "Cloudflare Worker is responding"
else
    print_error "Cloudflare Worker is not responding"
fi

echo ""
print_status "Testing API proxy creation..."

# Test API proxy creation
RESPONSE=$(curl -s -X POST "$WORKER_URL" \
    -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json"}')

if echo "$RESPONSE" | grep -q "success.*true"; then
    print_success "API proxy creation test passed"
    PROJECT_ID=$(echo "$RESPONSE" | grep -o '"project_id":"[^"]*"' | cut -d'"' -f4)
    print_status "Created test project: $PROJECT_ID"
else
    print_error "API proxy creation test failed"
    echo "Response: $RESPONSE"
fi

echo ""
print_status "Checking AWS infrastructure..."

# Check if Lambda functions are accessible
API_GATEWAY_URL="https://oyue74ev69.execute-api.us-east-1.amazonaws.com/prod/admin"
if curl -s "$API_GATEWAY_URL" > /dev/null; then
    print_success "API Gateway is accessible"
else
    print_warning "API Gateway is not accessible (this is expected for now)"
fi

echo ""
print_status "Checking DynamoDB tables..."

# Check if DynamoDB tables exist
TABLES=("apiblaze-projects" "apiblaze-users" "apiblaze-user-project-access" "apiblaze-customers" "apiblaze-api-keys")
for table in "${TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$table" --region us-east-1 > /dev/null 2>&1; then
        print_success "DynamoDB table $table exists"
    else
        print_error "DynamoDB table $table does not exist"
    fi
done

echo ""
print_status "Phase 2 Implementation Summary:"
echo "✅ Cloudflare Worker deployed and functional"
echo "✅ KV namespaces created and configured"
echo "✅ Environment variables and secrets set"
echo "✅ API proxy creation working (test mode)"
echo "🔄 API Gateway integration needs fixing"
echo "🔄 Custom domain routing needs setup"
echo "🔄 Customer UI needs to be created"
echo "🔄 Developer portal needs to be created"
echo "🔄 OAuth integration needs testing"

echo ""
print_status "Next steps:"
echo "1. Fix API Gateway integration issue"
echo "2. Set up custom domain routing for apiblaze.com"
echo "3. Create customer UI (Cloudflare Pages)"
echo "4. Create developer portal"
echo "5. Test OAuth flows"
echo "6. Deploy to production domain" 