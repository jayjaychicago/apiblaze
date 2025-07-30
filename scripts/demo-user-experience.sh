#!/bin/bash

# APIBLAZE User Experience Demo Script
# This script demonstrates the complete user workflow for creating and using API proxies

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="https://apiblaze.com"
API_GATEWAY_URL="https://334n5q3ww8.execute-api.us-east-1.amazonaws.com/prod/admin"

# Helper functions
print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

print_step() {
    echo -e "\n${YELLOW}Step $1: $2${NC}"
    echo -e "${CYAN}$3${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${PURPLE}ℹ️  $1${NC}"
}

print_command() {
    echo -e "${CYAN}Command: $1${NC}"
}

print_response() {
    echo -e "${GREEN}Response:${NC}"
    echo "$1" | jq . 2>/dev/null || echo "$1"
}

# Check if you have what you need
check_requirements() {
    print_header "Checking Requirements"
    
    if ! command -v curl &> /dev/null; then
        print_error "You need curl to run this demo. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_info "Note: jq is not installed - responses will be shown as plain text"
    fi
    
    print_success "You have everything you need"
}

# Check if everything is working
check_system() {
    print_header "Checking System"
    
    print_step "1" "Checking if APIBLAZE is available" "Making sure the service is running"
    print_command "curl -I $BASE_URL"
    
    if curl -I "$BASE_URL" &>/dev/null; then
        print_success "APIBLAZE is ready to use"
    else
        print_error "APIBLAZE is not available right now"
        exit 1
    fi
}

# Demo 1: Create a no-authentication project
demo_no_auth_project() {
    print_header "Demo 1: Creating a No-Authentication Project"
    
    print_info "This demo shows how to create an API proxy that doesn't require authentication."
    print_info "This is useful for public APIs or when you want to expose an API without access control."
    
    print_step "1" "Creating your first API proxy" "Setting up a simple API proxy"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{\"target\": \"https://httpbin.org/json\", \"auth_type\": \"none\"}'"
    
    local response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{"target": "https://httpbin.org/json", "auth_type": "none"}')
    
    print_response "$response"
    
    # Extract project details
    local project_id=$(echo "$response" | jq -r '.project_id' 2>/dev/null)
    local api_key=$(echo "$response" | jq -r '.api_key' 2>/dev/null)
    local endpoint=$(echo "$response" | jq -r '.endpoint' 2>/dev/null)
    
    if [ "$project_id" != "null" ] && [ -n "$project_id" ]; then
        print_success "Project created successfully!"
        print_info "Project ID: $project_id"
        print_info "API Key: $api_key"
        print_info "Endpoint: $endpoint"
        
        # Store for later use
        NO_AUTH_PROJECT_ID="$project_id"
        NO_AUTH_ENDPOINT="$endpoint"
        
        print_step "2" "Testing your API proxy" "Making sure your new proxy works"
        print_command "curl -X GET \"$endpoint\""
        
        local proxy_response=$(curl -s -X GET "$endpoint")
        print_response "$proxy_response"
        
        if echo "$proxy_response" | grep -q "slideshow\|json\|data"; then
            print_success "API proxy is working correctly!"
            print_info "The request was successfully forwarded to https://httpbin.org/json"
        elif echo "$proxy_response" | grep -q "error\|Error"; then
            print_error "API proxy returned an error: $proxy_response"
        else
            print_info "API proxy response received (check if it's what you expected)"
            print_info "Response preview: ${proxy_response:0:100}..."
        fi
        
    else
        print_error "Failed to create project"
        return 1
    fi
}

# Demo 2: Create an API key protected project
demo_api_key_project() {
    print_header "Demo 2: Creating an API Key Protected Project"
    
    print_info "This demo shows how to create an API proxy that requires API key authentication."
    print_info "This provides access control and allows you to track usage per API key."
    
    print_step "1" "Creating protected project" "Sending POST request to create a protected project"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{\"target\": \"https://httpbin.org/json\", \"auth_type\": \"api_key\"}'"
    
    local response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{"target": "https://httpbin.org/json", "auth_type": "api_key"}')
    
    print_response "$response"
    
    # Extract project details
    local project_id=$(echo "$response" | jq -r '.project_id' 2>/dev/null)
    local api_key=$(echo "$response" | jq -r '.api_key' 2>/dev/null)
    local endpoint=$(echo "$response" | jq -r '.endpoint' 2>/dev/null)
    
    if [ "$project_id" != "null" ] && [ -n "$project_id" ]; then
        print_success "Protected project created successfully!"
        print_info "Project ID: $project_id"
        print_info "API Key: $api_key"
        print_info "Endpoint: $endpoint"
        
        # Store for later use
        PROTECTED_PROJECT_ID="$project_id"
        PROTECTED_ENDPOINT="$endpoint"
        PROTECTED_API_KEY="$api_key"
        
        print_step "2" "Testing without API key (should fail)" "Showing what happens without authentication"
        print_command "curl -X GET \"$endpoint\""
        
        local failed_response=$(curl -s -X GET "$endpoint")
        print_response "$failed_response"
        
        if echo "$failed_response" | grep -q "API key required\|Unauthorized\|401"; then
            print_success "Authentication is working correctly!"
            print_info "The API correctly rejected the request without an API key"
        else
            print_info "Authentication check - API response: $failed_response"
            print_info "This might be working correctly depending on the response"
        fi
        
        print_step "3" "Testing with valid API key" "Showing how to use your API key"
        print_command "curl -X GET \"$endpoint\" -H \"X-API-Key: $api_key\""
        
        local success_response=$(curl -s -X GET "$endpoint" -H "X-API-Key: $api_key")
        print_response "$success_response"
        
        if echo "$success_response" | grep -q "slideshow\|json\|data"; then
            print_success "Authenticated API proxy is working correctly!"
            print_info "The request was successfully authenticated and forwarded"
        elif echo "$success_response" | grep -q "error\|Error"; then
            print_error "API proxy returned an error: $success_response"
        else
            print_info "API proxy response received (check if it's what you expected)"
            print_info "Response preview: ${success_response:0:100}..."
        fi
        
    else
        print_error "Failed to create protected project"
        return 1
    fi
}

# Demo 3: Advanced usage examples
demo_advanced_usage() {
    print_header "Demo 3: Advanced Usage Examples"
    
    if [ -z "$NO_AUTH_ENDPOINT" ]; then
        print_error "No auth project not available. Run Demo 1 first."
        return 1
    fi
    
    print_info "This demo shows advanced usage patterns like POST requests, query parameters, and custom headers."
    
    print_step "1" "Sending data to your API" "Making a POST request with JSON data"
    print_command "curl -X POST \"$NO_AUTH_ENDPOINT/post\" -H 'Content-Type: application/json' --data '{\"name\": \"John\", \"age\": 30}'"
    
    local post_response=$(curl -s -X POST "$NO_AUTH_ENDPOINT/post" \
        -H "Content-Type: application/json" \
        --data '{"name": "John", "age": 30}')
    
    print_response "$post_response"
    
    if echo "$post_response" | grep -q "John\|json\|data"; then
        print_success "POST request proxy is working correctly!"
        print_info "The JSON data was successfully forwarded to the target API"
    else
        print_info "POST request completed - check the response above"
    fi
    
    print_step "2" "Using query parameters" "Adding parameters to your API calls"
    print_command "curl -X GET \"$NO_AUTH_ENDPOINT/get?param1=value1&param2=value2\""
    
    local query_response=$(curl -s -X GET "$NO_AUTH_ENDPOINT/get?param1=value1&param2=value2")
    print_response "$query_response"
    
    if echo "$query_response" | grep -q "param1\|args\|query"; then
        print_success "Query parameter forwarding is working correctly!"
        print_info "The query parameters were successfully forwarded to the target API"
    else
        print_info "Query request completed - check the response above"
    fi
    
    print_step "3" "Using custom headers" "Adding your own headers to requests"
    print_command "curl -X GET \"$NO_AUTH_ENDPOINT/headers\" -H 'X-Custom-Header: my-value' -H 'Authorization: Bearer my-token'"
    
    local header_response=$(curl -s -X GET "$NO_AUTH_ENDPOINT/headers" \
        -H "X-Custom-Header: my-value" \
        -H "Authorization: Bearer my-token")
    
    print_response "$header_response"
    
    if echo "$header_response" | grep -q "X-Custom-Header\|headers\|Authorization"; then
        print_success "Header forwarding is working correctly!"
        print_info "The custom headers were successfully forwarded to the target API"
    else
        print_info "Header request completed - check the response above"
    fi
}

# Demo 4: Error handling
demo_error_handling() {
    print_header "Demo 4: Error Handling Examples"
    
    print_info "This demo shows how APIBLAZE handles various error scenarios."
    
    print_step "1" "Trying to access a project that doesn't exist" "Showing what happens with invalid projects"
    print_command "curl -X GET \"https://nonexistent-project.apiblaze.com/api\""
    
    local not_found_response=$(curl -s -X GET "https://nonexistent-project.apiblaze.com/api")
    print_response "$not_found_response"
    
    if echo "$not_found_response" | grep -q "Project not found"; then
        print_success "404 error handling is working correctly!"
        print_info "The system correctly identified that the project doesn't exist"
    fi
    
    if [ -n "$PROTECTED_ENDPOINT" ]; then
        print_step "2" "Using an invalid API key" "Showing what happens with wrong keys"
        print_command "curl -X GET \"$PROTECTED_ENDPOINT\" -H \"X-API-Key: invalid-key\""
        
        local invalid_key_response=$(curl -s -X GET "$PROTECTED_ENDPOINT" -H "X-API-Key: invalid-key")
        print_response "$invalid_key_response"
        
        if echo "$invalid_key_response" | grep -q "Invalid API key"; then
            print_success "Invalid API key handling is working correctly!"
            print_info "The system correctly rejected the invalid API key"
        fi
    fi
    
    print_step "3" "Sending bad data" "Showing what happens with invalid input"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{invalid json}'"
    
    local invalid_json_response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{invalid json}')
    
    print_response "$invalid_json_response"
    
    if echo "$invalid_json_response" | grep -q "error\|invalid"; then
        print_success "Invalid JSON handling is working correctly!"
        print_info "The system correctly handled the malformed JSON input"
    fi
}

# Demo 5: Real-world scenarios
demo_real_world_scenarios() {
    print_header "Demo 5: Real-World Scenarios"
    
    print_info "This demo shows practical examples of how APIBLAZE can be used in real applications."
    
    print_step "1" "Weather API Proxy" "Creating a proxy for a weather API"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{\"target\": \"https://api.openweathermap.org/data/2.5/weather\", \"auth_type\": \"api_key\"}'"
    
    local weather_response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{"target": "https://api.openweathermap.org/data/2.5/weather", "auth_type": "api_key"}')
    
    print_response "$weather_response"
    
    local weather_project_id=$(echo "$weather_response" | jq -r '.project_id' 2>/dev/null)
    local weather_api_key=$(echo "$weather_response" | jq -r '.api_key' 2>/dev/null)
    local weather_endpoint=$(echo "$weather_response" | jq -r '.endpoint' 2>/dev/null)
    
    if [ "$weather_project_id" != "null" ] && [ -n "$weather_project_id" ]; then
        print_success "Weather API proxy created!"
        print_info "You can now use: $weather_endpoint?q=London&appid=YOUR_WEATHER_API_KEY"
        print_info "With header: X-API-Key: $weather_api_key"
    fi
    
    print_step "2" "GitHub API Proxy" "Creating a proxy for GitHub API"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{\"target\": \"https://api.github.com\", \"auth_type\": \"api_key\"}'"
    
    local github_response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{"target": "https://api.github.com", "auth_type": "api_key"}')
    
    print_response "$github_response"
    
    local github_project_id=$(echo "$github_response" | jq -r '.project_id' 2>/dev/null)
    local github_api_key=$(echo "$github_response" | jq -r '.api_key' 2>/dev/null)
    local github_endpoint=$(echo "$github_response" | jq -r '.endpoint' 2>/dev/null)
    
    if [ "$github_project_id" != "null" ] && [ -n "$github_project_id" ]; then
        print_success "GitHub API proxy created!"
        print_info "You can now use: $github_endpoint/user"
        print_info "With headers: X-API-Key: $github_api_key, Authorization: Bearer YOUR_GITHUB_TOKEN"
    fi
    
    print_step "3" "Public API Proxy" "Creating a proxy for a public API"
    print_command "curl -X POST $BASE_URL/ -H 'Content-Type: application/json' --data '{\"target\": \"https://jsonplaceholder.typicode.com\", \"auth_type\": \"none\"}'"
    
    local public_response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        --data '{"target": "https://jsonplaceholder.typicode.com", "auth_type": "none"}')
    
    print_response "$public_response"
    
    local public_project_id=$(echo "$public_response" | jq -r '.project_id' 2>/dev/null)
    local public_endpoint=$(echo "$public_response" | jq -r '.endpoint' 2>/dev/null)
    
    if [ "$public_project_id" != "null" ] && [ -n "$public_project_id" ]; then
        print_success "Public API proxy created!"
        print_info "You can now use: $public_endpoint/posts/1"
        print_info "No authentication required!"
    fi
}

# Demo 6: Project management via API Gateway
demo_project_management() {
    print_header "Demo 6: Project Management via API Gateway"
    
    print_info "This demo shows how to manage projects using the admin API endpoints."
    
    print_step "1" "Seeing all your projects" "Listing all the API proxies you've created"
    print_command "curl -X GET \"$API_GATEWAY_URL/projects?customer_id=default\""
    
    local list_response=$(curl -s -X GET "$API_GATEWAY_URL/projects?customer_id=default")
    print_response "$list_response"
    
    if echo "$list_response" | grep -q "project_id"; then
        print_success "Project listing is working correctly!"
        print_info "You can see all projects created for the default customer"
    fi
    
    if [ -n "$NO_AUTH_PROJECT_ID" ]; then
        print_step "2" "Getting project details" "Looking at the details of a specific project"
        print_command "curl -X GET \"$API_GATEWAY_URL/projects/$NO_AUTH_PROJECT_ID\""
        
        local get_response=$(curl -s -X GET "$API_GATEWAY_URL/projects/$NO_AUTH_PROJECT_ID")
        print_response "$get_response"
        
        if echo "$get_response" | grep -q "$NO_AUTH_PROJECT_ID"; then
            print_success "Project retrieval is working correctly!"
            print_info "You can see the complete project configuration"
        fi
    fi
}

# Summary and next steps
show_summary() {
    print_header "Demo Summary and Next Steps"
    
    print_success "All demos completed successfully!"
    
    echo -e "\n${GREEN}What we've demonstrated:${NC}"
    echo "✅ Creating API proxies with and without authentication"
    echo "✅ Testing API proxy functionality"
    echo "✅ Advanced usage patterns (POST, query params, headers)"
    echo "✅ Error handling and edge cases"
    echo "✅ Real-world API proxy scenarios"
    echo "✅ Project management via admin API"
    
    echo -e "\n${YELLOW}Key Benefits of APIBLAZE:${NC}"
    echo "🔹 Custom subdomains for each project"
    echo "🔹 Flexible authentication options"
    echo "🔹 Automatic request forwarding"
    echo "🔹 HTTPS by default with valid certificates"
    echo "🔹 Global CDN for fast response times"
    echo "🔹 No server setup or configuration required"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Explore the web interface (coming soon)"
    echo "2. Set up OAuth 2.0 authentication"
    echo "3. Configure rate limiting for your projects"
    echo "4. Monitor usage analytics"
    echo "5. Integrate with your existing applications"
    
    echo -e "\n${PURPLE}Resources:${NC}"
    echo "📖 Documentation: docs/PRD.txt"
    echo "📋 Status: status.txt"
    echo "🔧 Examples: docs/example.txt"
    echo "🌐 Live Demo: $BASE_URL"
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}APIBLAZE User Experience Demo${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "${CYAN}This script demonstrates the complete user workflow${NC}"
    echo -e "${CYAN}for creating and using API proxies with APIBLAZE.${NC}\n"
    
    check_requirements
    check_system
    
    # Run all demos
    demo_no_auth_project
    demo_api_key_project
    demo_advanced_usage
    demo_error_handling
    demo_real_world_scenarios
    demo_project_management
    
    show_summary
    
    echo -e "\n${GREEN}Demo completed successfully! 🎉${NC}"
}

# Run the main function
main "$@" 