#!/bin/bash

# APIBLAZE GitHub Webhook Setup Script
# This script helps customers set up GitHub webhooks for automatic redeployment

set -e

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

# Check if required tools are installed
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed. Please install curl first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq first."
        exit 1
    fi
    
    print_success "All dependencies are installed"
}

# Get GitHub webhook URL from Terraform outputs
get_webhook_url() {
  if [ ! -f "outputs.json" ]; then
    print_error "Terraform outputs not found. Please run the deployment script first."
    exit 1
  fi
  
  WEBHOOK_URL=$(jq -r '.github_webhook_url.value' outputs.json)
  
  echo $WEBHOOK_URL
}

# Generate webhook secret
generate_webhook_secret() {
    openssl rand -hex 32
}

# Create GitHub webhook
create_github_webhook() {
    local repo_owner=$1
    local repo_name=$2
    local github_token=$3
    local webhook_url=$4
    local webhook_secret=$5
    
    print_status "Creating GitHub webhook for ${repo_owner}/${repo_name}..."
    
    local webhook_data=$(cat <<EOF
{
  "name": "web",
  "active": true,
  "events": ["push", "pull_request", "create"],
  "config": {
    "url": "${webhook_url}",
    "content_type": "json",
    "secret": "${webhook_secret}"
  }
}
EOF
)
    
    local response=$(curl -s -w "%{http_code}" \
        -X POST \
        -H "Authorization: token ${github_token}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "${webhook_data}" \
        "https://api.github.com/repos/${repo_owner}/${repo_name}/hooks")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" = "201" ]; then
        print_success "GitHub webhook created successfully"
        echo $response_body | jq -r '.id'
    else
        print_error "Failed to create GitHub webhook: $http_code"
        echo $response_body | jq -r '.message // "Unknown error"'
        exit 1
    fi
}

# Update project with GitHub information
update_project_with_github() {
    local project_id=$1
    local repo_owner=$2
    local repo_name=$3
    local branch=$4
    local webhook_secret=$5
    
    print_status "Updating project ${project_id} with GitHub information..."
    
    local project_data=$(cat <<EOF
{
  "github_repo": "${repo_owner}/${repo_name}",
  "github_branch": "${branch}",
  "github_webhook_secret": "${webhook_secret}"
}
EOF
)
    
    local webhook_url=$(get_webhook_url)
    local response=$(curl -s -w "%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "${project_data}" \
        "${webhook_url}/projects/${project_id}")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        print_success "Project updated with GitHub information"
    else
        print_error "Failed to update project: $http_code"
        echo $response_body | jq -r '.error // "Unknown error"'
        exit 1
    fi
}

# Main setup function
setup_github_webhook() {
    local repo_owner=$1
    local repo_name=$2
    local github_token=$3
    local project_id=$4
    local branch=${5:-main}
    
    print_status "Setting up GitHub webhook for automatic redeployment..."
    
    # Check dependencies
    check_dependencies
    
    # Generate webhook secret
    local webhook_secret=$(generate_webhook_secret)
    print_status "Generated webhook secret"
    
    # Get webhook URL
    local webhook_url=$(get_webhook_url)
    print_status "Webhook URL: ${webhook_url}"
    
    # Create GitHub webhook
    local webhook_id=$(create_github_webhook "$repo_owner" "$repo_name" "$github_token" "$webhook_url" "$webhook_secret")
    
    # Update project with GitHub information
    update_project_with_github "$project_id" "$repo_owner" "$repo_name" "$branch" "$webhook_secret"
    
    print_success "GitHub webhook setup completed!"
    
    echo ""
    echo "Setup Summary:"
    echo "=============="
    echo "Repository: ${repo_owner}/${repo_name}"
    echo "Branch: ${branch}"
    echo "Project ID: ${project_id}"
    echo "Webhook ID: ${webhook_id}"
    echo "Webhook URL: ${webhook_url}"
    echo ""
    echo "Next steps:"
    echo "1. Make changes to your OpenAPI spec in the repository"
    echo "2. Push changes to the ${branch} branch"
    echo "3. The webhook will automatically trigger redeployment"
    echo ""
    echo "To test the webhook:"
    echo "1. Make a small change to your openapi.yaml file"
    echo "2. Commit and push the change"
    echo "3. Check the CloudWatch logs for the webhook handler"
}

# Show usage
show_usage() {
    echo "Usage: $0 <repo_owner> <repo_name> <github_token> <project_id> [branch]"
    echo ""
    echo "Arguments:"
    echo "  repo_owner    GitHub repository owner (e.g., 'username' or 'organization')"
    echo "  repo_name     GitHub repository name"
    echo "  github_token  GitHub personal access token with repo scope"
    echo "  project_id    APIBLAZE project ID"
    echo "  branch        Git branch to monitor (default: main)"
    echo ""
    echo "Example:"
    echo "  $0 myusername my-api-repo ghp_xxxxxxxxxxxxx abc123def456 develop"
    echo ""
    echo "Note: The GitHub token needs the 'repo' scope to create webhooks."
}

# Main execution
if [ $# -lt 4 ]; then
    show_usage
    exit 1
fi

REPO_OWNER=$1
REPO_NAME=$2
GITHUB_TOKEN=$3
PROJECT_ID=$4
BRANCH=${5:-main}

setup_github_webhook "$REPO_OWNER" "$REPO_NAME" "$GITHUB_TOKEN" "$PROJECT_ID" "$BRANCH" 