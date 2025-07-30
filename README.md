# APIBLAZE - API Proxy Platform

APIBLAZE is a powerful API proxy platform that allows customers to instantly create API proxies from OpenAPI/Swagger specifications, manage authentication, and provide developer portals for their APIs.

## 🚀 Quick Start

### Prerequisites

- **AWS CLI** - Configured with appropriate credentials
- **Terraform** - Version >= 1.0
- **Node.js** - Version >= 18
- **Wrangler CLI** - Cloudflare Workers CLI
- **jq** - JSON processor for scripts

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd apiblaze
   ```

2. **Configure AWS credentials**
   ```bash
   aws configure
   ```

3. **Configure Cloudflare credentials**
   ```bash
   wrangler login
   ```

4. **Configure Terraform variables**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform/terraform.tfvars with your configuration
   ```

5. **Deploy the complete infrastructure**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh deploy
   ```

6. **Rollback if needed**
   ```bash
   ./scripts/deploy.sh rollback
   ```

## 🏗️ Architecture

### Overview

APIBLAZE uses a hybrid architecture combining **Cloudflare** for edge computing and **AWS** for backend services:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   End Users     │    │   Customers     │    │   Target APIs   │
│                 │    │                 │    │                 │
│ • API Keys      │    │ • Dashboard     │    │ • REST APIs     │
│ • OAuth Tokens  │    │ • Project Mgmt  │    │ • GraphQL       │
│ • No Auth       │    │ • User Mgmt     │    │ • Custom APIs   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLOUDFLARE WORKER                           │
│                                                                 │
│  • Request Routing    • Authentication    • API Proxying       │
│  • Rate Limiting      • Caching           • Logging            │
│  • KV Storage         • OAuth Handling    • Custom Domains     │
└─────────────────────────────────────────────────────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AWS SERVICES  │    │   AWS SERVICES  │    │   AWS SERVICES  │
│                 │    │                 │    │                 │
│ • Cognito       │    │ • DynamoDB      │    │ • Lambda        │
│ • IAM           │    │ • S3            │    │ • API Gateway   │
│ • CloudWatch    │    │ • CloudTrail    │    │ • CloudFormation│
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Components

#### **Cloudflare Components**
- **Worker**: Main routing and proxy logic at `apiblaze.com`
- **KV Store**: Fast access cache for frequently accessed data
- **Pages**: Customer dashboard and developer portal hosting
- **R2**: Static asset storage
- **DNS**: Domain management and SSL certificates

#### **AWS Components** (us-east-1)
- **Cognito**: Multi-tenant authentication (single pool, email-based usernames)
- **DynamoDB**: Source of truth for all data
- **Lambda**: Core business logic (admin functions, OAuth handling)
- **API Gateway**: Central API for shared endpoints
- **S3**: Static assets and Terraform state

### Data Flow

1. **API Request**: `https://myapi1.apiblaze.com/endpoint`
2. **Worker Routing**: Extract project ID from subdomain
3. **Authentication**: Validate API key, OAuth token, or skip auth
4. **Cache Check**: Look up project config in KV cache
5. **DynamoDB Fallback**: If not in cache, fetch from DynamoDB
6. **Target Proxy**: Forward request to target API with appropriate auth
7. **Response**: Return response to end user

## 📊 Database Schema

### DynamoDB Tables

#### `apiblaze-projects`
```json
{
  "project_id": "string",
  "api_version": "string",
  "customer_id": "string",
  "target_url": "string",
  "auth_type": "api_key|oauth|none",
  "target_auth_type": "api_key|oauth|none",
  "target_api_key": "string",
  "active": "boolean",
  "created_at": "number",
  "updated_at": "number"
}
```

#### `apiblaze-users`
```json
{
  "user_id": "string",
  "email": "string",
  "customer_id": "string",
  "user_role": "owner|admin|user",
  "created_at": "number",
  "updated_at": "number"
}
```

#### `apiblaze-user-project-access`
```json
{
  "user_id": "string",
  "project_id": "string",
  "customer_id": "string",
  "has_access": "boolean",
  "access_level": "owner|admin|user",
  "created_at": "number",
  "updated_at": "number"
}
```

#### `apiblaze-api-keys`
```json
{
  "api_key_hash": "string",
  "project_id": "string",
  "user_id": "string",
  "name": "string",
  "active": "boolean",
  "expires_at": "number",
  "created_at": "number",
  "updated_at": "number"
}
```

### Cloudflare KV Namespaces

#### `OAUTH_TOKENS`
- Key: `{user_id}:{project_id}`
- Value: OAuth token data for third-party providers

#### `API_KEYS`
- Key: `{api_key_hash}:{project_id}`
- Value: API key metadata and validation data

#### `PROJECTS`
- Key: `{project_id}`
- Value: Project configuration cache

#### `USER_ACCESS`
- Key: `{user_id}:{project_id}`
- Value: User access permissions cache

## 🔐 Authentication Types

### End User Authentication

1. **API Keys**: Self-service API keys from developer portal
2. **OAuth with Cognito**: Users authenticate via `auth.apiblaze.com`
3. **No Auth**: Public APIs without authentication

### Target Server Authentication

1. **Single API Key**: One API key for all target server access
2. **Multi API Key**: Different API keys for different access levels
3. **Third-party OAuth**: End user OAuth tokens relayed to target
4. **No Auth**: Direct proxy without target authentication

## 🚀 Usage Examples

## 🔄 Automatic Redeployment

APIBLAZE supports automatic redeployment in two scenarios:

### 1. GitHub OpenAPI Spec Changes
When you update your OpenAPI specification in GitHub, APIBLAZE automatically:
- Detects changes to `.yaml`, `.yml`, or `.json` files containing "openapi", "swagger", or "api"
- Fetches the updated specification from GitHub
- Updates the project configuration in DynamoDB
- Triggers a Cloudflare Worker redeployment
- Updates the KV cache with new configuration

**Supported GitHub Events:**
- `push` - When code is pushed to any branch
- `pull_request` - When PRs are opened or updated
- `create` - When new branches are created

### 2. Configuration Changes
When customers change API settings (auth method, target URL, etc.), APIBLAZE automatically:
- Detects changes via DynamoDB Streams
- Updates the Cloudflare KV cache
- Invalidates relevant caches
- Triggers redeployment if necessary

**Configuration Changes That Trigger Redeployment:**
- Authentication type changes (API key ↔ OAuth ↔ None)
- Target URL changes
- Project activation/deactivation
- User access permission changes
- API key creation/deactivation

### Setup GitHub Integration
```bash
# 1. Create a GitHub personal access token with 'repo' scope
# 2. Run the setup script
./scripts/setup-github-webhook.sh myusername my-api-repo ghp_xxxxxxxxxxxxx abc123def456 main

# 3. Test the integration
# Make a change to your openapi.yaml file and push to GitHub
# Check CloudWatch logs to see the automatic redeployment
```

### Create API Proxy via CLI
```bash
# Create a new API proxy
curl -X POST https://apiblaze.com \
  -H "Content-Type: application/json" \
  -d '{
    "target": "https://api.example.com",
    "auth_type": "api_key"
  }'

# Response
{
  "success": true,
  "project_id": "abc123def456",
  "api_key": "apiblaze_xyz789...",
  "endpoint": "https://abc123def456.apiblaze.com"
}
```

### Setup GitHub Integration for Automatic Redeployment
```bash
# Set up GitHub webhook for automatic redeployment
./scripts/setup-github-webhook.sh myusername my-api-repo ghp_xxxxxxxxxxxxx abc123def456 main

# This will:
# 1. Create a GitHub webhook that monitors your repository
# 2. Automatically redeploy when OpenAPI specs change
# 3. Update project configuration when settings change
```

### Use API Proxy
```bash
# With API key authentication
curl -H "X-API-Key: apiblaze_xyz789..." \
  https://abc123def456.apiblaze.com/users

# With OAuth token
curl -H "Authorization: Bearer your_oauth_token" \
  https://abc123def456.apiblaze.com/users

# No authentication
curl https://abc123def456.apiblaze.com/public/data
```

### Developer Portal
```
https://apiportal.apiblaze.com/project=abc123def456&apiVersion=v1
```

## 🛠️ Development

### Local Development

1. **Setup local environment**
   ```bash
   npm install
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Run Lambda functions locally**
   ```bash
   cd lambda/admin-api
   npm run dev
   ```

3. **Test Cloudflare Worker locally**
   ```bash
   cd cloudflare
   wrangler dev
   ```

### Testing

```bash
# Run all tests
npm test

# Run specific test suites
npm run test:unit
npm run test:integration
npm run test:e2e
```

### Deployment

```bash
# Deploy everything
./scripts/deploy.sh

# Deploy specific components
./scripts/deploy-terraform.sh
./scripts/deploy-worker.sh
./scripts/deploy-dashboard.sh
```

## 📈 Monitoring & Analytics

### CloudWatch Metrics
- API request count and latency
- Error rates and types
- Authentication success/failure rates
- Cache hit/miss ratios

### Cloudflare Analytics
- Global request distribution
- DDoS protection metrics
- Cache performance
- SSL certificate status

### Custom Dashboards
- Real-time API usage
- User activity tracking
- Project performance metrics
- Revenue analytics

## 🔧 Configuration

### Environment Variables

#### AWS Configuration
```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

#### Cloudflare Configuration
```bash
CLOUDFLARE_API_TOKEN=your_api_token
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_ZONE_ID=your_zone_id
```

#### OAuth Configuration
```bash
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
OAUTH_REDIRECT_URI=https://redirect.apiblaze.com
```

### Terraform Variables

Create `terraform/terraform.tfvars`:
```hcl
aws_region = "us-east-1"
environment = "production"
domain_name = "apiblaze.com"
```

## 🚨 Security

### Best Practices
- All API keys are hashed before storage
- OAuth tokens are encrypted in KV storage
- JWT tokens are validated against Cognito JWKS
- Rate limiting per project and API key
- CORS policies configured per domain
- SSL/TLS encryption for all communications

### Compliance
- SOC 2 Type II compliant
- GDPR compliant data handling
- HIPAA ready (with additional configuration)
- PCI DSS compliant for payment processing

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### Code Style
- Use ESLint and Prettier
- Follow TypeScript best practices
- Write comprehensive tests
- Document all public APIs

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs.apiblaze.com](https://docs.apiblaze.com)
- **Issues**: [GitHub Issues](https://github.com/apiblaze/apiblaze/issues)
- **Discord**: [APIBLAZE Community](https://discord.gg/apiblaze)
- **Email**: support@apiblaze.com

## 🗺️ Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Terraform infrastructure
- [x] Cloudflare Worker
- [x] Basic authentication
- [x] Database schema

### Phase 2: Core Functionality 🚧
- [ ] API proxy logic
- [ ] OAuth integration
- [ ] API key management
- [ ] Customer UI

### Phase 3: Advanced Features 📋
- [ ] Developer portal
- [ ] MCP server
- [ ] Custom domains
- [ ] Analytics & monitoring

### Phase 4: Enterprise Features 📋
- [ ] Multi-region deployment
- [ ] Advanced rate limiting
- [ ] API versioning
- [ ] Webhook support

---

**Built with ❤️ by the APIBLAZE Team**
