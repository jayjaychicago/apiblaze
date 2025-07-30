#!/bin/bash

# APIBLAZE Deployment Script
# Deploys the complete infrastructure using Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo -e "${BLUE}🚀 APIBLAZE Deployment Script${NC}"
echo "=================================="

# Check if required tools are installed
check_requirements() {
    echo -e "\n${YELLOW}Checking requirements...${NC}"
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}❌ Terraform is required but not installed.${NC}"
        echo "   Please install Terraform: https://www.terraform.io/downloads.html"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is required but not installed.${NC}"
        echo "   Please install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! command -v wrangler &> /dev/null; then
        echo -e "${RED}❌ Wrangler is required but not installed.${NC}"
        echo "   Please install Wrangler: npm install -g wrangler"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All requirements met${NC}"
}

# Check AWS credentials
check_aws_credentials() {
    echo -e "\n${YELLOW}Checking AWS credentials...${NC}"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS credentials not configured.${NC}"
        echo "   Please run: aws configure"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✅ AWS credentials valid (Account: $ACCOUNT_ID)${NC}"
}

# Check Cloudflare credentials
check_cloudflare_credentials() {
    echo -e "\n${YELLOW}Checking Cloudflare credentials...${NC}"
    
    if ! wrangler whoami &> /dev/null; then
        echo -e "${RED}❌ Cloudflare credentials not configured.${NC}"
        echo "   Please run: wrangler login"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Cloudflare credentials valid${NC}"
}

# Deploy Terraform infrastructure
deploy_terraform() {
    echo -e "\n${YELLOW}Deploying Terraform infrastructure...${NC}"
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    echo "   Initializing Terraform..."
    terraform init
    
    # Plan deployment
    echo "   Planning deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    echo "   Applying deployment..."
    terraform apply tfplan
    
    # Get outputs
    echo "   Getting outputs..."
    terraform output
    
    echo -e "${GREEN}✅ Terraform deployment complete${NC}"
}

# Deploy Cloudflare Worker
deploy_worker() {
    echo -e "\n${YELLOW}Deploying Cloudflare Worker...${NC}"
    
    cd "$PROJECT_ROOT/cloudflare"
    
    # Deploy to production environment
    echo "   Deploying to production environment..."
    wrangler deploy --env production
    
    echo -e "${GREEN}✅ Cloudflare Worker deployment complete${NC}"
}

# Run tests
run_tests() {
    echo -e "\n${YELLOW}Running tests...${NC}"
    
    cd "$PROJECT_ROOT"
    
    if [ -f "scripts/run-tests.sh" ]; then
        bash scripts/run-tests.sh
        echo -e "${GREEN}✅ Tests completed${NC}"
    else
        echo -e "${YELLOW}⚠️  Test script not found, skipping tests${NC}"
    fi
}

# Main deployment flow
main() {
    check_requirements
    check_aws_credentials
    check_cloudflare_credentials
    
    echo -e "\n${BLUE}Starting deployment...${NC}"
    
    deploy_terraform
    deploy_worker
    run_tests
    
    echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
    echo "=================================="
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Test the deployment: bash scripts/run-tests.sh"
    echo "2. Check status: cat status.txt"
    echo "3. View API documentation: cat docs/openapi.yaml"
}

# Run main function
main "$@"

 