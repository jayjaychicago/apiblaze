#!/bin/bash

# APIBLAZE Test Runner
# Central script to run all test suites

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

echo -e "${BLUE}🚀 APIBLAZE Test Runner${NC}"
echo "=========================="

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq is required but not installed. Please install jq first.${NC}"
    echo "   Ubuntu/Debian: sudo apt-get install jq"
    echo "   macOS: brew install jq"
    echo "   CentOS/RHEL: sudo yum install jq"
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl is required but not installed.${NC}"
    exit 1
fi

# Function to run a test script
run_test() {
    local test_name="$1"
    local test_script="$2"
    
    echo -e "\n${YELLOW}Running $test_name...${NC}"
    echo "----------------------------------------"
    
    if [ -f "$test_script" ]; then
        if bash "$test_script"; then
            echo -e "${GREEN}✅ $test_name passed${NC}"
            return 0
        else
            echo -e "${RED}❌ $test_name failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Test script not found: $test_script${NC}"
        return 1
    fi
}

# Initialize counters
total_tests=0
passed_tests=0
failed_tests=0

# Run Cloudflare Worker tests
if run_test "Cloudflare Worker Tests" "$TESTS_DIR/test-cloudflare-worker.sh"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Run API Gateway tests
if run_test "API Gateway Tests" "$TESTS_DIR/test-api-gateway.sh"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Run Integration tests
if run_test "Integration Tests" "$TESTS_DIR/test-integration.sh"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Summary
echo -e "\n${BLUE}📊 Test Summary${NC}"
echo "=================="
echo -e "Total test suites: ${YELLOW}$total_tests${NC}"
echo -e "Passed: ${GREEN}$passed_tests${NC}"
echo -e "Failed: ${RED}$failed_tests${NC}"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All test suites passed!${NC}"
    echo "APIBLAZE is ready for production use."
    exit 0
else
    echo -e "\n${RED}❌ Some test suites failed.${NC}"
    echo "Please check the output above for details."
    exit 1
fi 