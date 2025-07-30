#!/bin/bash

# APIBLAZE Integration Test Script
# Tests the complete flow from Cloudflare Worker to API Gateway to DynamoDB

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKER_URL="https://apiblaze.com"
API_GATEWAY_URL="https://334n5q3ww8.execute-api.us-east-1.amazonaws.com/prod/admin"

echo -e "${BLUE}🧪 APIBLAZE Integration Test Suite${NC}"
echo "=========================================="

# Test 1: End-to-End Project Creation and Retrieval
echo -e "\n${YELLOW}Test 1: End-to-End Project Creation and Retrieval${NC}"

# Step 1: Create project via Cloudflare Worker
echo "   Step 1: Creating project via Cloudflare Worker..."
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json", "auth_type": "api_key"}')

if echo "$response" | grep -q '"success":true'; then
    echo -e "   ${GREEN}✅ Project created via Worker${NC}"
    PROJECT_ID=$(echo "$response" | jq -r '.project_id')
    API_KEY=$(echo "$response" | jq -r '.api_key')
    echo "   Project ID: $PROJECT_ID"
    echo "   API Key: $API_KEY"
else
    echo -e "   ${RED}❌ Project creation via Worker failed${NC}"
    echo "   Response: $response"
    exit 1
fi

# Step 2: Verify project exists in API Gateway list
echo "   Step 2: Verifying project in API Gateway list..."
sleep 2  # Give DynamoDB time to update
response=$(curl -s -X GET "$API_GATEWAY_URL/projects")

if echo "$response" | grep -q "$PROJECT_ID"; then
    echo -e "   ${GREEN}✅ Project found in API Gateway list${NC}"
else
    echo -e "   ${RED}❌ Project not found in API Gateway list${NC}"
    echo "   Response: $response"
    exit 1
fi

# Step 3: Retrieve individual project via API Gateway
echo "   Step 3: Retrieving individual project via API Gateway..."
response=$(curl -s -X GET "$API_GATEWAY_URL/projects/$PROJECT_ID")

if echo "$response" | grep -q '"project_id":"'"$PROJECT_ID"'"'; then
    echo -e "   ${GREEN}✅ Individual project retrieval successful${NC}"
    TARGET_URL=$(echo "$response" | jq -r '.target_url')
    AUTH_TYPE=$(echo "$response" | jq -r '.auth_type')
    CUSTOMER_ID=$(echo "$response" | jq -r '.customer_id')
    echo "   Target URL: $TARGET_URL"
    echo "   Auth Type: $AUTH_TYPE"
    echo "   Customer ID: $CUSTOMER_ID"
else
    echo -e "   ${RED}❌ Individual project retrieval failed${NC}"
    echo "   Response: $response"
    exit 1
fi

# Test 2: Multiple Project Types
echo -e "\n${YELLOW}Test 2: Multiple Project Types${NC}"

# Create OAuth project
echo "   Creating OAuth project..."
oauth_response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json", "auth_type": "oauth"}')

if echo "$oauth_response" | grep -q '"success":true'; then
    echo -e "   ${GREEN}✅ OAuth project created${NC}"
    OAUTH_PROJECT_ID=$(echo "$oauth_response" | jq -r '.project_id')
    echo "   OAuth Project ID: $OAUTH_PROJECT_ID"
else
    echo -e "   ${RED}❌ OAuth project creation failed${NC}"
    echo "   Response: $oauth_response"
    exit 1
fi

# Create default project
echo "   Creating default project..."
default_response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json"}')

if echo "$default_response" | grep -q '"success":true'; then
    echo -e "   ${GREEN}✅ Default project created${NC}"
    DEFAULT_PROJECT_ID=$(echo "$default_response" | jq -r '.project_id')
    echo "   Default Project ID: $DEFAULT_PROJECT_ID"
else
    echo -e "   ${RED}❌ Default project creation failed${NC}"
    echo "   Response: $default_response"
    exit 1
fi

# Test 3: Data Consistency
echo -e "\n${YELLOW}Test 3: Data Consistency${NC}"

# Verify all projects are in the list
sleep 2
response=$(curl -s -X GET "$API_GATEWAY_URL/projects")
PROJECT_COUNT=$(echo "$response" | jq '.projects | length')
echo "   Total projects in database: $PROJECT_COUNT"

# Check if all our test projects are present
if echo "$response" | grep -q "$PROJECT_ID" && \
   echo "$response" | grep -q "$OAUTH_PROJECT_ID" && \
   echo "$response" | grep -q "$DEFAULT_PROJECT_ID"; then
    echo -e "   ${GREEN}✅ All test projects found in database${NC}"
else
    echo -e "   ${RED}❌ Not all test projects found in database${NC}"
    exit 1
fi

# Test 4: Customer Filtering
echo -e "\n${YELLOW}Test 4: Customer Filtering${NC}"

# Test customer filter
response=$(curl -s -X GET "$API_GATEWAY_URL/projects?customer_id=default")
FILTERED_COUNT=$(echo "$response" | jq '.projects | length')
echo "   Projects for customer 'default': $FILTERED_COUNT"

if [ "$FILTERED_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}✅ Customer filtering working${NC}"
else
    echo -e "   ${RED}❌ Customer filtering failed${NC}"
    exit 1
fi

# Test 5: Error Handling
echo -e "\n${YELLOW}Test 5: Error Handling${NC}"

# Test invalid project ID
response=$(curl -s -X GET "$API_GATEWAY_URL/projects/invalid-project-id")
if echo "$response" | grep -q '"error"'; then
    echo -e "   ${GREEN}✅ Invalid project ID handled correctly${NC}"
else
    echo -e "   ${RED}❌ Invalid project ID handling failed${NC}"
    echo "   Response: $response"
    exit 1
fi

# Test invalid JSON to Worker
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"invalid": "json"}')
if echo "$response" | grep -q "APIBLAZE CLI"; then
    echo -e "   ${GREEN}✅ Invalid JSON to Worker handled correctly${NC}"
else
    echo -e "   ${RED}❌ Invalid JSON to Worker handling failed${NC}"
    echo "   Response: $response"
    exit 1
fi

echo -e "\n${GREEN}🎉 All integration tests passed!${NC}"
echo "=========================================="
echo -e "${BLUE}Summary:${NC}"
echo "   - Created 3 test projects (API Key, OAuth, Default)"
echo "   - Verified data consistency across Worker and API Gateway"
echo "   - Tested customer filtering"
echo "   - Verified error handling"
echo "   - All projects successfully stored in DynamoDB" 