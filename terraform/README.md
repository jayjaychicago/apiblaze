# 🚀 ApiBlaze Infrastructure as Code

This directory contains the complete Terraform infrastructure for ApiBlaze, a multi-tenant API proxy platform that allows customers to create API proxies from OpenAPI/Swagger specifications with flexible authentication options.

## 📋 Overview

ApiBlaze is built on a **Cloudflare + AWS hybrid architecture** that provides:
- **Multi-tenant API proxy platform** with dynamic OAuth support
- **Scalable authentication** supporting any OAuth 2.0 provider per customer
- **Automatic deployment** from GitHub OpenAPI specifications
- **Developer portals** with Swagger UI integration
- **Custom domain support** for customer APIs

## 🏗️ Architecture

### AWS Components (us-east-1)
- **Cognito**: Multi-tenant authentication with customer-prefixed groups
- **DynamoDB**: 7 tables for user management, project metadata, and OAuth configurations
- **Lambda**: 5 functions for core business logic and OAuth handling
- **API Gateway**: REST API for admin functions and webhooks
- **S3**: Deployment artifacts and Terraform state with versioning and encryption

### Cloudflare Components
- **Worker**: Main routing and proxy logic
- **KV Store**: Fast access cache for OAuth tokens, API keys, and project configs
- **Pages**: Customer UI deployment
- **DNS**: Domain management for all subdomains

## 📁 Directory Structure

```
terraform/
├── main.tf                    # Main Terraform configuration
├── terraform.tfvars           # Configuration variables
├── outputs.tf                 # Output values
├── scripts/                   # Management scripts
│   ├── verify-deployment.sh   # Deployment verification
│   ├── rollback.sh           # Rollback management
│   ├── emergency-cleanup.sh  # Emergency AWS cleanup
│   ├── backup.sh             # State backup
│   ├── restore.sh            # State restoration
│   ├── monitor.sh            # Cost and performance monitoring
│   ├── README.md             # Script documentation
│   └── QUICK_REFERENCE.md    # Quick reference guide
├── backups/                   # Terraform state backups
└── README.md                 # This file
```

## 🚀 Quick Start

### Prerequisites
- **AWS CLI** configured with appropriate permissions
- **Terraform** v1.0+ installed
- **Cloudflare API Token** with DNS and Worker permissions

### 1. Initial Setup
```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan
```

### 2. Deploy Infrastructure
```bash
# Deploy all resources
terraform apply -auto-approve

# Verify deployment
./scripts/verify-deployment.sh
```

### 3. Create Backup
```bash
# Create initial backup
./scripts/backup.sh initial-deployment
```

## 🔧 Configuration

### Environment Variables
Edit `terraform.tfvars` to configure your environment:

```hcl
environment = "production"
domain_name = "apiblaze.com"
aws_region = "us-east-1"
cloudflare_api_token = "your-cloudflare-api-token"
```

### Key Resources Created

#### DynamoDB Tables (7 tables)
- `apiblaze-users`: User profiles and customer associations
- `apiblaze-customers`: Customer information and settings
- `apiblaze-projects`: Project metadata and configuration
- `apiblaze-user-project-access`: User access to projects
- `apiblaze-api-keys`: API key metadata and audit trail
- `apiblaze-customer-oauth-configs`: Dynamic OAuth provider configurations
- `apiblaze-oauth-tokens`: OAuth token storage

#### Lambda Functions (5 functions)
- `apiblaze-admin-api`: Customer management API
- `apiblaze-oauth-handler`: Dynamic OAuth provider handling
- `apiblaze-oauth-callback`: OAuth callback processing
- `apiblaze-github-webhook`: GitHub webhook processing
- `apiblaze-config-change-handler`: DynamoDB stream processing

#### Authentication
- **Cognito User Pool**: Multi-tenant with email-based usernames
- **Cognito Groups**: Customer-prefixed groups (e.g., `customer1:owners`)
- **OAuth Support**: Google, GitHub, Microsoft, and extensible for any OAuth 2.0 provider

## 🔄 Multi-Customer OAuth Architecture

### Key Features
- **Dynamic OAuth Configuration**: Each customer can configure multiple OAuth providers
- **Customer-Specific Settings**: Each customer has their own OAuth client IDs and secrets
- **Scalable Design**: Supports "many many customers who will have many many OAuth client IDs"
- **Extensible Framework**: Easy to add new OAuth providers

### Supported Providers
- **Google OAuth 2.0**: Standard Google authentication
- **GitHub OAuth**: GitHub user authentication
- **Microsoft OAuth**: Microsoft 365 and Azure AD authentication
- **Custom Providers**: Extensible framework for any OAuth 2.0 provider

### Configuration Example
```json
{
  "customerId": "customer1",
  "providerType": "google",
  "clientId": "customer1-google-client-id",
  "clientSecret": "customer1-google-client-secret",
  "redirectUri": "https://redirect.apiblaze.com/oauth/callback",
  "scopes": "openid email profile"
}
```

## 🛠️ Management Scripts

### Deployment Verification
```bash
# Check all resources and endpoints
./scripts/verify-deployment.sh
```

### Rollback Management
```bash
# Complete rollback (destroy everything)
./scripts/rollback.sh complete

# Selective rollback
./scripts/rollback.sh selective

# Rollback specific components
./scripts/rollback.sh lambda      # Remove only Lambda functions
./scripts/rollback.sh database    # Remove only DynamoDB tables
./scripts/rollback.sh api         # Remove only API Gateway
./scripts/rollback.sh cognito     # Remove only Cognito resources
./scripts/rollback.sh s3          # Remove only S3 buckets
```

### State Management
```bash
# Create backup
./scripts/backup.sh my-backup-name

# Restore from backup
./scripts/restore.sh my-backup-name

# List available backups
./scripts/restore.sh
```

### Monitoring
```bash
# Check AWS costs
./scripts/monitor.sh costs

# Check Lambda metrics
./scripts/monitor.sh lambda

# Check all metrics
./scripts/monitor.sh all
```

### Emergency Cleanup
```bash
# Manual AWS cleanup (when Terraform fails)
./scripts/emergency-cleanup.sh
```

## 🔒 Security Features

### Authentication & Authorization
- **Multi-tenant Cognito**: Single user pool with customer isolation
- **Customer-Prefixed Groups**: Role-based access control per customer
- **OAuth Token Security**: Encrypted storage and rotation
- **API Key Validation**: Fast KV-based validation for every request

### Data Protection
- **S3 Encryption**: Server-side encryption for all buckets
- **DynamoDB Encryption**: At-rest encryption for all tables
- **IAM Least Privilege**: Minimal permissions for all roles
- **Secure Token Handling**: OAuth tokens stored securely in Cloudflare KV

### Network Security
- **API Gateway**: HTTPS-only endpoints
- **Cloudflare Protection**: DDoS protection and rate limiting
- **VPC Isolation**: Lambda functions in secure VPC (if needed)

## 📊 Monitoring & Observability

### CloudWatch Metrics
- **Lambda**: Invocations, errors, duration, throttles
- **DynamoDB**: Read/write capacity, item counts, throttles
- **API Gateway**: Request count, 4xx/5xx errors, latency
- **S3**: Request count, data transfer, errors

### Cost Monitoring
- **AWS Cost Explorer**: Service-level cost breakdown
- **Resource Usage**: Lambda execution time, DynamoDB capacity
- **Alerting**: Cost threshold alerts (configure manually)

### Logging
- **CloudWatch Logs**: All Lambda function logs
- **API Gateway Access Logs**: Request/response logging
- **DynamoDB Streams**: Real-time data change events

## 🔄 Deployment Workflow

### Before Making Changes
```bash
# 1. Verify current state
./scripts/verify-deployment.sh

# 2. Create backup
./scripts/backup.sh before-changes

# 3. Review plan
terraform plan
```

### Deploy Changes
```bash
# Apply changes
terraform apply -auto-approve

# Verify deployment
./scripts/verify-deployment.sh
```

### If Issues Occur
```bash
# 1. Try selective rollback
./scripts/rollback.sh selective

# 2. Or restore from backup
./scripts/restore.sh before-changes

# 3. Or emergency cleanup (last resort)
./scripts/emergency-cleanup.sh
```

## 🚨 Troubleshooting

### Common Issues

#### Terraform State Issues
```bash
# Reinitialize Terraform
terraform init -reconfigure

# Import existing resources
terraform import aws_dynamodb_table.projects apiblaze-projects
```

#### Lambda Function Issues
```bash
# Check Lambda logs
aws logs tail /aws/lambda/apiblaze-admin-api --follow

# Test Lambda function
aws lambda invoke --function-name apiblaze-admin-api response.json
```

#### API Gateway Issues
```bash
# Check API Gateway logs
aws logs describe-log-groups --log-group-name-prefix API-Gateway-Execution-Logs

# Test endpoint
curl -X GET https://oyue74ev69.execute-api.us-east-1.amazonaws.com/prod/admin
```

#### DynamoDB Issues
```bash
# Check table status
aws dynamodb describe-table --table-name apiblaze-users

# Scan table (for debugging)
aws dynamodb scan --table-name apiblaze-users --limit 10
```

### Emergency Procedures

#### Complete Infrastructure Failure
```bash
# 1. Emergency cleanup
./scripts/emergency-cleanup.sh

# 2. Re-deploy from scratch
terraform init
terraform apply -auto-approve

# 3. Verify deployment
./scripts/verify-deployment.sh
```

#### State File Corruption
```bash
# 1. Restore from backup
./scripts/restore.sh latest-backup

# 2. Refresh state
terraform refresh

# 3. Apply any drift
terraform apply
```

## 📈 Scaling Considerations

### Current Limits
- **Lambda**: 1000 concurrent executions per region
- **DynamoDB**: On-demand capacity with auto-scaling
- **API Gateway**: 10,000 requests per second
- **Cloudflare**: 100,000 requests per day (free tier)

### Scaling Strategies
- **Lambda**: Increase memory allocation for better performance
- **DynamoDB**: Enable auto-scaling for read/write capacity
- **API Gateway**: Add caching for frequently accessed endpoints
- **Cloudflare**: Upgrade to paid plan for higher limits

### Performance Optimization
- **KV Caching**: Use Cloudflare KV for frequently accessed data
- **Lambda Warmup**: Keep functions warm for better response times
- **DynamoDB Indexing**: Optimize queries with GSI and LSI
- **API Gateway Caching**: Cache responses for static data

## 🔮 Future Enhancements

### Phase 2: Core Functionality
- [ ] Deploy Cloudflare Worker for routing
- [ ] Configure OAuth providers per customer
- [ ] Test OAuth flow with dynamic providers
- [ ] Add missing DynamoDB streams
- [ ] Configure Cloudflare DNS records

### Phase 3: Advanced Features
- [ ] Custom domain support with wildcard SSL
- [ ] MCP server for LLM integration
- [ ] Advanced analytics and monitoring
- [ ] Rate limiting and throttling
- [ ] API versioning and management

## 📞 Support

### Documentation
- **Scripts**: See `scripts/README.md` for detailed script documentation
- **Quick Reference**: See `scripts/QUICK_REFERENCE.md` for common commands
- **PRD**: See `../docs/PRD.txt` for product requirements

### Getting Help
1. Check the script output for error messages
2. Verify AWS credentials and permissions
3. Ensure you're running from the terraform directory
4. Check that all prerequisites are installed
5. Review the script logs for specific failure points

### Useful Commands
```bash
# Check AWS account
aws sts get-caller-identity

# Check Terraform version
terraform version

# List all resources
terraform state list

# Show resource details
terraform show
```

## 📄 License

This infrastructure is part of the ApiBlaze platform. All rights reserved.

---

**Last Updated**: July 2024  
**Version**: 1.0.0  
**Status**: Phase 1 Complete - Ready for Phase 2 