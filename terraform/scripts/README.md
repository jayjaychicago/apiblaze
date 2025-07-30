# ApiBlaze Terraform Scripts

This directory contains utility scripts for managing the ApiBlaze infrastructure deployment, verification, rollback, and monitoring.

## 📁 Scripts Overview

### 🔍 **verify-deployment.sh**
Comprehensive deployment verification script that checks all resources and endpoints.

**Usage:**
```bash
./scripts/verify-deployment.sh
```

**What it checks:**
- ✅ Terraform state (35+ resources)
- ✅ Lambda functions (5 functions)
- ✅ DynamoDB tables (7 tables)
- ✅ API Gateway endpoints (admin & webhook)
- ✅ Cognito resources (user pool, client, identity pool)
- ✅ S3 buckets (deployment artifacts & terraform state)
- ✅ IAM roles and policies

### 🔄 **rollback.sh**
Flexible rollback script with multiple options for different scenarios.

**Usage:**
```bash
# Complete rollback (destroy everything)
./scripts/rollback.sh complete

# Interactive selective rollback
./scripts/rollback.sh selective

# Rollback specific components
./scripts/rollback.sh lambda      # Remove only Lambda functions
./scripts/rollback.sh database    # Remove only DynamoDB tables
./scripts/rollback.sh api         # Remove only API Gateway
./scripts/rollback.sh cognito     # Remove only Cognito resources
./scripts/rollback.sh s3          # Remove only S3 buckets
./scripts/rollback.sh custom      # Custom resource selection
```

**Features:**
- 🔒 Automatic backup before rollback
- ⚠️ Confirmation prompts for destructive actions
- 🎯 Selective rollback options
- 📋 Custom resource targeting

### 🚨 **emergency-cleanup.sh**
Manual AWS resource cleanup when Terraform fails.

**Usage:**
```bash
./scripts/emergency-cleanup.sh
```

**What it removes:**
- Lambda functions
- DynamoDB tables
- API Gateway resources
- Cognito user pools and identity pools
- S3 buckets (with all objects)
- IAM roles and policies
- CloudWatch log groups

**⚠️ WARNING:** This script requires typing "EMERGENCY" to confirm and permanently deletes all data!

### 💾 **backup.sh**
Creates backup snapshots of Terraform state.

**Usage:**
```bash
# Create backup with auto-generated name
./scripts/backup.sh

# Create backup with custom name
./scripts/backup.sh my-backup-name
```

**Features:**
- 📅 Timestamped backups
- 📊 Metadata tracking (resources, file size, terraform version)
- 📁 Organized backup directory
- 📋 Backup listing

### 🔄 **restore.sh**
Restores Terraform state from backup files.

**Usage:**
```bash
# Interactive restore (shows available backups)
./scripts/restore.sh

# Restore specific backup
./scripts/restore.sh my-backup-name
```

**Features:**
- 🔒 Automatic backup before restore
- 📋 Backup metadata display
- ✅ State verification after restore
- 📊 Drift detection with terraform plan

### 📊 **monitor.sh**
Monitors AWS costs and resource metrics.

**Usage:**
```bash
# Check costs (default)
./scripts/monitor.sh costs

# Check specific metrics
./scripts/monitor.sh lambda     # Lambda function metrics
./scripts/monitor.sh dynamodb   # DynamoDB metrics
./scripts/monitor.sh api        # API Gateway metrics
./scripts/monitor.sh all        # All metrics
```

**What it monitors:**
- 💰 AWS costs by service (last 30 days)
- 🔢 Lambda invocations, errors, duration
- 📊 DynamoDB read/write capacity, item counts
- 🌐 API Gateway requests, errors, latency

## 🚀 Quick Start

1. **Make scripts executable:**
   ```bash
   chmod +x scripts/*.sh
   ```

2. **Verify deployment:**
   ```bash
   ./scripts/verify-deployment.sh
   ```

3. **Create backup:**
   ```bash
   ./scripts/backup.sh
   ```

4. **Monitor costs:**
   ```bash
   ./scripts/monitor.sh costs
   ```

## 🔧 Prerequisites

- **AWS CLI** configured with appropriate permissions
- **Terraform** installed and configured
- **jq** (for JSON parsing in emergency cleanup)
- **bc** (for calculations in monitoring)

## 📋 Common Workflows

### 🆕 Fresh Deployment
```bash
# 1. Deploy infrastructure
terraform apply -auto-approve

# 2. Verify deployment
./scripts/verify-deployment.sh

# 3. Create initial backup
./scripts/backup.sh initial-deployment
```

### 🔄 Safe Rollback
```bash
# 1. Create backup before changes
./scripts/backup.sh before-changes

# 2. Make changes
terraform apply -auto-approve

# 3. If issues occur, rollback
./scripts/rollback.sh selective

# 4. Or restore from backup
./scripts/restore.sh before-changes
```

### 🚨 Emergency Recovery
```bash
# 1. Try normal rollback first
./scripts/rollback.sh complete

# 2. If Terraform fails, use emergency cleanup
./scripts/emergency-cleanup.sh

# 3. Re-deploy from scratch
terraform init
terraform apply -auto-approve
```

### 📊 Regular Monitoring
```bash
# 1. Check costs weekly
./scripts/monitor.sh costs

# 2. Check performance monthly
./scripts/monitor.sh all

# 3. Create regular backups
./scripts/backup.sh weekly-backup-$(date +%Y%m%d)
```

## 🛡️ Safety Features

- **Automatic backups** before destructive operations
- **Confirmation prompts** for dangerous actions
- **Resource verification** after operations
- **Error handling** and graceful failures
- **Colored output** for easy status identification

## 📁 File Structure

```
terraform/
├── scripts/
│   ├── verify-deployment.sh
│   ├── rollback.sh
│   ├── emergency-cleanup.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── monitor.sh
│   └── README.md
├── backups/           # Created by backup.sh
│   ├── backup-20241201-120000.tfstate
│   ├── backup-20241201-120000.metadata
│   └── ...
└── main.tf
```

## 🔍 Troubleshooting

### Script Permission Denied
```bash
chmod +x scripts/*.sh
```

### AWS CLI Not Found
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Terraform Not Found
```bash
# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform
```

### Backup Directory Issues
```bash
# Create backup directory manually
mkdir -p backups
```

## 📞 Support

If you encounter issues with these scripts:

1. Check the script output for error messages
2. Verify AWS credentials and permissions
3. Ensure you're running from the terraform directory
4. Check that all prerequisites are installed
5. Review the script logs for specific failure points

## 🔄 Version History

- **v1.0.0** - Initial script set with core functionality
- **v1.1.0** - Added monitoring and emergency cleanup
- **v1.2.0** - Enhanced backup/restore with metadata
- **v1.3.0** - Added selective rollback options 