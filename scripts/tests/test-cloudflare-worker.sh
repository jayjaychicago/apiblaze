#!/bin/bash

# APIBLAZE Cloudflare Worker Test Script
# Tests the main CLI interface and project creation functionality

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

echo -e "${BLUE}🧪 APIBLAZE Cloudflare Worker Test Suite${NC}"
echo "=========================================="

# Test 1: CLI Help (empty request)
echo -e "\n${YELLOW}Test 1: CLI Help (empty request)${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" --data '{}')
if echo "$response" | grep -q "APIBLAZE CLI"; then
    echo -e "${GREEN}✅ CLI help returned correctly${NC}"
else
    echo -e "${RED}❌ CLI help failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 2: Project Creation (API Key)
echo -e "\n${YELLOW}Test 2: Project Creation (API Key)${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json", "auth_type": "api_key"}')
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Project creation (API Key) successful${NC}"
    PROJECT_ID=$(echo "$response" | jq -r '.project_id')
    API_KEY=$(echo "$response" | jq -r '.api_key')
    echo "   Project ID: $PROJECT_ID"
    echo "   API Key: $API_KEY"
else
    echo -e "${RED}❌ Project creation (API Key) failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 3: Project Creation (OAuth)
echo -e "\n${YELLOW}Test 3: Project Creation (OAuth)${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json", "auth_type": "oauth"}')
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Project creation (OAuth) successful${NC}"
    OAUTH_PROJECT_ID=$(echo "$response" | jq -r '.project_id')
    OAUTH_API_KEY=$(echo "$response" | jq -r '.api_key')
    echo "   Project ID: $OAUTH_PROJECT_ID"
    echo "   API Key: $OAUTH_API_KEY"
else
    echo -e "${RED}❌ Project creation (OAuth) failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 4: Project Creation (Default)
echo -e "\n${YELLOW}Test 4: Project Creation (Default)${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"target": "https://httpbin.org/json"}')
if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Project creation (Default) successful${NC}"
    DEFAULT_PROJECT_ID=$(echo "$response" | jq -r '.project_id')
    DEFAULT_API_KEY=$(echo "$response" | jq -r '.api_key')
    echo "   Project ID: $DEFAULT_PROJECT_ID"
    echo "   API Key: $DEFAULT_API_KEY"
else
    echo -e "${RED}❌ Project creation (Default) failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 5: Invalid JSON Handling
echo -e "\n${YELLOW}Test 5: Invalid JSON Handling${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"invalid": "json", "missing": "target"}')
if echo "$response" | grep -q "APIBLAZE CLI"; then
    echo -e "${GREEN}✅ Invalid JSON handled correctly (returns CLI help)${NC}"
else
    echo -e "${RED}❌ Invalid JSON handling failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Test 6: Missing Target URL
echo -e "\n${YELLOW}Test 6: Missing Target URL${NC}"
response=$(curl -s -X POST "$WORKER_URL/" -H "Content-Type: application/json" \
    --data '{"auth_type": "api_key"}')
if echo "$response" | grep -q "APIBLAZE CLI"; then
    echo -e "${GREEN}✅ Missing target URL handled correctly${NC}"
else
    echo -e "${RED}❌ Missing target URL handling failed${NC}"
    echo "Response: $response"
    exit 1
fi

echo -e "\n${GREEN}🎉 All Cloudflare Worker tests passed!${NC}"
echo "==========================================" 