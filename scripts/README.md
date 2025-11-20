# Scripts Directory

This directory contains all deployment, setup, testing, and utility scripts organized by purpose.

## Directory Structure

```
scripts/
├── deployment/     # Deployment scripts for AWS and local environments
├── setup/          # Configuration and setup scripts
├── testing/        # Testing and validation scripts
└── utils/          # Utility scripts (security, cleanup, etc.)
```

## Scripts by Category

### Deployment (`deployment/`)
- **`deploy-aws-production.sh`** - Complete AWS production deployment (Terraform + EKS + Helm)
- **`deploy-minikube.sh`** - Deploy application to local Minikube cluster
- **`setup-minikube.sh`** - Set up Minikube environment for local development

### Setup (`setup/`)
- **`setup-aws-secrets.sh`** - Store application secrets (Twilio, OpenWeather) in AWS Parameter Store
- **`setup-rds-parameters.py`** - Set up RDS database connection parameters in Parameter Store

### Testing (`testing/`)
- **`test-minikube.sh`** - Test local Minikube deployment
- **`test-rds-aws.sh`** - Test RDS integration on AWS
- **`test-rds-connectivity.sh`** - Diagnose RDS connectivity issues from EKS pods

### Utilities (`utils/`)
- **`security-scan.sh`** - Comprehensive security scanning (matches CI/CD pipeline)
- **`stop-billing.sh`** - Safely destroy all AWS infrastructure to stop billing

## Usage Examples

### Production Deployment
```bash
# 1. Set up secrets
./scripts/setup/setup-aws-secrets.sh

# 2. Deploy to AWS
./scripts/deployment/deploy-aws-production.sh
```

### Local Development
```bash
# 1. Set up Minikube
./scripts/deployment/setup-minikube.sh

# 2. Deploy to Minikube
./scripts/deployment/deploy-minikube.sh

# 3. Test deployment
./scripts/testing/test-minikube.sh
```

### Testing
```bash
# Test RDS connectivity
./scripts/testing/test-rds-connectivity.sh

# Test RDS integration
./scripts/testing/test-rds-aws.sh
```

### Utilities
```bash
# Security scan
./scripts/utils/security-scan.sh

# Stop AWS billing
./scripts/utils/stop-billing.sh
```

## Notes

- All scripts use relative paths and should be run from the project root
- Scripts include error handling and colored output for better UX
- Most scripts check for prerequisites before execution
- See individual script headers for detailed usage instructions

