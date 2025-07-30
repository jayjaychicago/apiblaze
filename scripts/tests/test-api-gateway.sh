#!/bin/bash

# APIBLAZE API Gateway Test Script
# Tests the admin API endpoints for project management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_GATEWAY_URL="https://334n5q3ww8.execute-api.us-east-1.amazonaws.com/prod/admin"

echo -e "${BLUE}🧪 APIBLAZE API Gateway Test Suite${NC}"
echo "=========================================="

# Test 1: List Projects (GET /admin/projects)
echo -e "\n${YELLOW}Test 1: List Projects (GET /admin/projects)${NC}"
response=$(curl -s -X GET "$API_GATEWAY_URL/projects")
if echo "$response" | grep -q '"projects"'; then
    echo -e "${GREEN}✅ List projects successful${NC}"
    PROJECT_COUNT=$(echo "$response" | jq '.projects | length')
    echo "   Found $PROJECT_COUNT projects"
else
    echo -e "${RED}❌ List projects failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 2: List Projects with Customer Filter
echo -e "\n${YELLOW}Test 2: List Projects with Customer Filter${NC}"
response=$(curl -s -X GET "$API_GATEWAY_URL/projects?customer_id=default")
if echo "$response" | grep -q '"projects"'; then
    echo -e "${GREEN}✅ List projects with customer filter successful${NC}"
    FILTERED_COUNT=$(echo "$response" | jq '.projects | length')
    echo "   Found $FILTERED_COUNT projects for customer 'default'"
else
    echo -e "${RED}❌ List projects with customer filter failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 3: Create Project (POST /admin/projects)
echo -e "\n${YELLOW}Test 3: Create Project (POST /admin/projects)${NC}"
PROJECT_DATA='{
  "project_id": "test-project-123",
  "target_url": "https://httpbin.org/json",
  "auth_type": "api_key",
  "customer_id": "default",
  "active": true,
  "created_at": 1234567890
}'
response=$(curl -s -X POST "$API_GATEWAY_URL/projects" \
    -H "Content-Type: application/json" \
    --data "$PROJECT_DATA")
if echo "$response" | grep -q '"project_id":"test-project-123"'; then
    echo -e "${GREEN}✅ Create project successful${NC}"
    echo "   Project ID: test-project-123"
else
    echo -e "${RED}❌ Create project failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 4: Get Individual Project (GET /admin/projects/{project_id})
echo -e "\n${YELLOW}Test 4: Get Individual Project${NC}"
response=$(curl -s -X GET "$API_GATEWAY_URL/projects/test-project-123")
if echo "$response" | grep -q '"project_id":"test-project-123"'; then
    echo -e "${GREEN}✅ Get individual project successful${NC}"
    TARGET_URL=$(echo "$response" | jq -r '.target_url')
    AUTH_TYPE=$(echo "$response" | jq -r '.auth_type')
    echo "   Target URL: $TARGET_URL"
    echo "   Auth Type: $AUTH_TYPE"
else
    echo -e "${RED}❌ Get individual project failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 5: Get Non-existent Project
echo -e "\n${YELLOW}Test 5: Get Non-existent Project${NC}"
response=$(curl -s -X GET "$API_GATEWAY_URL/projects/non-existent-project")
if echo "$response" | grep -q '"error"'; then
    echo -e "${GREEN}✅ Non-existent project handled correctly${NC}"
else
    echo -e "${RED}❌ Non-existent project handling failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 6: Get a Real Project from the List
echo -e "\n${YELLOW}Test 6: Get a Real Project from the List${NC}"
# Get the first project ID from the list
FIRST_PROJECT_ID=$(curl -s -X GET "$API_GATEWAY_URL/projects" | jq -r '.projects[0].project_id')
if [ "$FIRST_PROJECT_ID" != "null" ] && [ "$FIRST_PROJECT_ID" != "" ]; then
    response=$(curl -s -X GET "$API_GATEWAY_URL/projects/$FIRST_PROJECT_ID")
    if echo "$response" | grep -q '"project_id"'; then
        echo -e "${GREEN}✅ Get real project successful${NC}"
        echo "   Project ID: $FIRST_PROJECT_ID"
        CUSTOMER_ID=$(echo "$response" | jq -r '.customer_id')
        echo "   Customer ID: $CUSTOMER_ID"
    else
        echo -e "${RED}❌ Get real project failed${NC}"
        echo "Response: $response"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  No projects found to test with${NC}"
fi

# Test 7: Invalid Project Data
echo -e "\n${YELLOW}Test 7: Invalid Project Data${NC}"
response=$(curl -s -X POST "$API_GATEWAY_URL/projects" \
    -H "Content-Type: application/json" \
    --data '{"invalid": "data"}')
if echo "$response" | grep -q '"error"'; then
    echo -e "${GREEN}✅ Invalid project data handled correctly${NC}"
else
    echo -e "${RED}❌ Invalid project data handling failed${NC}"
    echo "Response: $response"
    exit 1
fi

echo -e "\n${GREEN}🎉 All API Gateway tests passed!${NC}"
echo "==========================================" 