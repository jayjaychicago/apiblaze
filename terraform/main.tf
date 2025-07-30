terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project     = "apiblaze"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "apiblaze-terraform-state-240232487139"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB tables for source of truth
# DynamoDB table for projects with API versions
resource "aws_dynamodb_table" "projects" {
  name           = "apiblaze-projects"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name     = "GSI1"
    hash_key = "GSI1PK"
    range_key = "GSI1SK"
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams for automatic redeployment
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

resource "aws_dynamodb_table" "users" {
  name           = "apiblaze-users"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name     = "email-index"
    hash_key = "email"
    projection_type = "ALL"
  }
}

resource "aws_dynamodb_table" "user_project_access" {
  name           = "apiblaze-user-project-access"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"
  range_key      = "project_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "project_id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  global_secondary_index {
    name     = "customer_id-index"
    hash_key = "customer_id"
    projection_type = "ALL"
  }
}

resource "aws_dynamodb_table" "customers" {
  name           = "apiblaze-customers"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "customer_id"

  attribute {
    name = "customer_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "api_keys" {
  name           = "apiblaze-api-keys"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "api_key_hash"
  range_key      = "project_id"

  attribute {
    name = "api_key_hash"
    type = "S"
  }

  attribute {
    name = "project_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name     = "user_id-index"
    hash_key = "user_id"
    projection_type = "ALL"
  }
}

# DynamoDB table for customer OAuth provider configurations
resource "aws_dynamodb_table" "customer_oauth_configs" {
  name           = "apiblaze-customer-oauth-configs"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "customer_id"
  range_key      = "provider_id"

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "provider_id"
    type = "S"
  }

  attribute {
    name = "provider_type"
    type = "S"
  }

  global_secondary_index {
    name     = "provider_type-index"
    hash_key = "provider_type"
    projection_type = "ALL"
  }
}

# Cognito User Pool - Configured for dynamic OAuth providers
resource "aws_cognito_user_pool" "main" {
  name = "apiblaze-user-pool"

  # Allow users to sign up with email
  username_attributes = ["email"]
  
  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }

  # Tags
  tags = {
    Environment = var.environment
    Project     = "apiblaze"
    ManagedBy   = "terraform"
  }
}

# Cognito User Pool Client - Configured for custom OAuth flow
resource "aws_cognito_user_pool_client" "main" {
  name         = "apiblaze-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Generate client secret
  generate_secret = true

  # Allowed OAuth flows
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # Callback URLs - will be dynamically configured per customer
  callback_urls = ["https://apiblaze.com/oauth/callback"]
  logout_urls   = ["https://apiblaze.com/logout"]

  # Supported identity providers - only Cognito initially
  supported_identity_providers = ["COGNITO"]

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name = "apiblaze_identity_pool"

  allow_unauthenticated_identities = false
  allow_classic_flow               = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }
}

# IAM roles for authenticated users
resource "aws_iam_role" "authenticated" {
  name = "apiblaze_cognito_authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "authenticated" {
  name = "authenticated_policy"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          # aws_dynamodb_table.projects.arn,  # Already exists
          aws_dynamodb_table.users.arn,
          aws_dynamodb_table.user_project_access.arn,
          aws_dynamodb_table.customers.arn,
          aws_dynamodb_table.api_keys.arn
        ]
      }
    ]
  })
}

# Attach roles to identity pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}

# Lambda functions for core business logic
resource "aws_lambda_function" "admin_api" {
  filename         = "../lambda/admin-api.zip"
  function_name    = "apiblaze-admin-api"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      REGION       = "us-east-1"
      INTERNAL_API_KEY = var.internal_api_key
    }
  }
}

resource "aws_lambda_function" "oauth_handler" {
  filename         = "../lambda/oauth-handler.zip"
  function_name    = "apiblaze-oauth-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      REGION       = "us-east-1"
    }
  }
}

resource "aws_lambda_function" "oauth_callback" {
  filename         = "../lambda/oauth-callback.zip"
  function_name    = "apiblaze-oauth-callback"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      REGION       = "us-east-1"
    }
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "apiblaze_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda_dynamodb_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.projects.arn,
          "${aws_dynamodb_table.projects.arn}/index/GSI1",
          aws_dynamodb_table.users.arn,
          aws_dynamodb_table.user_project_access.arn,
          aws_dynamodb_table.customers.arn,
          aws_dynamodb_table.api_keys.arn
        ]
      }
    ]
  })
}

# API Gateway for shared endpoints
resource "aws_api_gateway_rest_api" "main" {
  name = "apiblaze-api"
}

# Admin resource
resource "aws_api_gateway_resource" "admin" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "admin"
}

# Projects resource under admin
resource "aws_api_gateway_resource" "projects" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.admin.id
  path_part   = "projects"
}

# Individual project resource
resource "aws_api_gateway_resource" "project" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.projects.id
  path_part   = "{project_id}"
}

# POST /admin/projects - Create project
resource "aws_api_gateway_method" "create_project" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.projects.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_project" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.projects.id
  http_method = aws_api_gateway_method.create_project.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.admin_api.invoke_arn
}

# GET /admin/projects - List projects
resource "aws_api_gateway_method" "list_projects" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.projects.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "list_projects" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.projects.id
  http_method = aws_api_gateway_method.list_projects.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.admin_api.invoke_arn
}

# GET /admin/projects/{project_id} - Get individual project
resource "aws_api_gateway_method" "get_project" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.project.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_project" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.project.id
  http_method = aws_api_gateway_method.get_project.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.admin_api.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "admin_api_projects" {
  statement_id  = "AllowExecutionFromAPIGatewayProjects"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/admin/projects"
}

resource "aws_lambda_permission" "admin_api_project" {
  statement_id  = "AllowExecutionFromAPIGatewayProject"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/admin/projects/*"
}

# Deploy the API
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.create_project,
    aws_api_gateway_integration.list_projects,
    aws_api_gateway_integration.get_project,
    aws_api_gateway_integration.webhook
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.main.id
}

output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.main.invoke_url}/admin"
}

output "github_webhook_url" {
  value = "${aws_api_gateway_deployment.main.invoke_url}/webhook"
}

output "dynamodb_tables" {
  value = {
    projects         = aws_dynamodb_table.projects.name
    users           = aws_dynamodb_table.users.name
    user_project_access = aws_dynamodb_table.user_project_access.name
    customers       = aws_dynamodb_table.customers.name
    api_keys        = aws_dynamodb_table.api_keys.name
  }
}

# output "cloudflare_dns_records" {
#   value = {
#     githubwebhook = cloudflare_record.githubwebhook.hostname
#     dashboard     = cloudflare_record.dashboard.hostname
#     apiportal     = cloudflare_record.apiportal.hostname
#     redirect      = cloudflare_record.redirect.hostname
#   }
# } 

# GitHub Webhook Lambda for automatic redeployment
resource "aws_lambda_function" "github_webhook" {
  filename         = "../lambda/github-webhook.zip"
  function_name    = "apiblaze-github-webhook"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      REGION       = "us-east-1"
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      DEPLOYMENT_ARTIFACTS_BUCKET = aws_s3_bucket.deployment_artifacts.bucket
    }
  }
}

# API Gateway webhook endpoint for GitHub
resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "webhook"
}

resource "aws_api_gateway_method" "webhook" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.github_webhook.invoke_arn
}

resource "aws_lambda_permission" "github_webhook" {
  statement_id  = "AllowExecutionFromAPIGatewayWebhook"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Cloudflare DNS records for subdomains - will be added after API token permissions are fixed
# resource "cloudflare_record" "githubwebhook" {
#   zone_id = var.cloudflare_zone_id
#   name    = "githubwebhook"
#   value   = "githubwebhook.apiblaze.com"
#   type    = "CNAME"
#   proxied = true
# }
#
# resource "cloudflare_record" "dashboard" {
#   zone_id = var.cloudflare_zone_id
#   name    = "dashboard"
#   value   = "dashboard.apiblaze.com"
#   type    = "CNAME"
#   proxied = true
# }
#
# resource "cloudflare_record" "apiportal" {
#   zone_id = var.cloudflare_zone_id
#   name    = "apiportal"
#   value   = "apiportal.apiblaze.com"
#   type    = "CNAME"
#   proxied = true
# }
#
# resource "cloudflare_record" "redirect" {
#   zone_id = var.cloudflare_zone_id
#   name    = "redirect"
#   value   = "redirect.apiblaze.com"
#   type    = "CNAME"
#   proxied = true
# }



# Lambda function to handle DynamoDB Stream events (config changes)
resource "aws_lambda_function" "config_change_handler" {
  filename         = "../lambda/config-change-handler.zip"
  function_name    = "apiblaze-config-change-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      REGION = "us-east-1"
      CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
      CLOUDFLARE_ACCOUNT_ID = var.cloudflare_account_id
    }
  }
}

# DynamoDB Stream event source mapping
# Lambda event source mapping for DynamoDB streams - will be added after table is configured
# resource "aws_lambda_event_source_mapping" "projects_stream" {
#   event_source_arn  = aws_dynamodb_table.projects.stream_arn
#   function_name     = aws_lambda_function.config_change_handler.function_name
#   starting_position = "LATEST"
#   batch_size        = 1
# }

# IAM policy for DynamoDB Stream access
resource "aws_iam_role_policy" "lambda_dynamodb_stream" {
  name = "lambda_dynamodb_stream_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:240232487139:table/apiblaze-projects/stream/*"  # Already exists
      }
    ]
  })
}

# S3 bucket for storing OpenAPI specs and deployment artifacts
resource "aws_s3_bucket" "deployment_artifacts" {
  bucket = "apiblaze-deployment-artifacts"
}

resource "aws_s3_bucket_versioning" "deployment_artifacts" {
  bucket = aws_s3_bucket.deployment_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deployment_artifacts" {
  bucket = aws_s3_bucket.deployment_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "lambda_s3" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deployment_artifacts.arn,
          "${aws_s3_bucket.deployment_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Variables for Cloudflare configuration
variable "cloudflare_api_token" {
  description = "Cloudflare API token for deployment automation"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for apiblaze.com"
  type        = string
}

variable "github_webhook_secret" {
  description = "GitHub webhook secret for signature verification"
  type        = string
  sensitive   = true
  default     = ""
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "apiblaze.com"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "internal_api_key" {
  description = "Internal API key for Cloudflare Worker to Lambda communication"
  type        = string
  sensitive   = true
}