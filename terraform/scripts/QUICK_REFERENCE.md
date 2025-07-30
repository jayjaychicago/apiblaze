# 🚀 ApiBlaze Quick Reference

## 📋 Most Common Commands

### ✅ **Verify Everything is Working**
```bash
./scripts/verify-deployment.sh
```

### 💾 **Create Backup (Before Changes)**
```bash
./scripts/backup.sh before-changes
```

### 🔄 **Rollback Everything**
```bash
./scripts/rollback.sh complete
```

### 🔄 **Selective Rollback**
```bash
./scripts/rollback.sh selective
```

### 📊 **Check Costs**
```bash
./scripts/monitor.sh costs
```

### 🚨 **Emergency Cleanup (When Terraform Fails)**
```bash
./scripts/emergency-cleanup.sh
```

## 🎯 **Rollback Options**

| Option | What it removes |
|--------|----------------|
| `complete` | Everything (all resources) |
| `lambda` | Only Lambda functions |
| `database` | Only DynamoDB tables |
| `api` | Only API Gateway |
| `cognito` | Only Cognito resources |
| `s3` | Only S3 buckets |
| `selective` | Interactive menu |

## 📊 **Monitoring Options**

| Option | What it shows |
|--------|---------------|
| `costs` | AWS costs by service |
| `lambda` | Lambda metrics (invocations, errors, duration) |
| `dynamodb` | DynamoDB metrics (capacity, item counts) |
| `api` | API Gateway metrics (requests, errors, latency) |
| `all` | All metrics |

## 🔄 **Typical Workflow**

### Before Making Changes
```bash
# 1. Verify current state
./scripts/verify-deployment.sh

# 2. Create backup
./scripts/backup.sh before-changes

# 3. Make changes
terraform apply -auto-approve
```

### If Something Goes Wrong
```bash
# 1. Try selective rollback
./scripts/rollback.sh selective

# 2. Or restore from backup
./scripts/restore.sh before-changes

# 3. Or emergency cleanup (last resort)
./scripts/emergency-cleanup.sh
```

### Regular Maintenance
```bash
# 1. Check costs weekly
./scripts/monitor.sh costs

# 2. Verify deployment monthly
./scripts/verify-deployment.sh

# 3. Create regular backups
./scripts/backup.sh weekly-$(date +%Y%m%d)
```

## ⚠️ **Safety Reminders**

- **Always backup before changes**
- **Use selective rollback when possible**
- **Emergency cleanup requires typing "EMERGENCY"**
- **Check costs regularly to avoid surprises**

## 🆘 **Emergency Contacts**

- **Terraform fails**: Use `emergency-cleanup.sh`
- **Can't rollback**: Use `emergency-cleanup.sh`
- **Lost state**: Restore from backup with `restore.sh`
- **High costs**: Check with `monitor.sh costs`

## 📁 **File Locations**

- **Scripts**: `terraform/scripts/`
- **Backups**: `terraform/backups/`
- **Main config**: `terraform/main.tf`
- **Variables**: `terraform/terraform.tfvars` 