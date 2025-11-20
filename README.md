# WhatsApp Weather Bot
![CI](https://github.com/Evyatar-git/whatsapp-weather-bot/actions/workflows/ci.yml/badge.svg)

A production-ready WhatsApp Weather Bot built with FastAPI featuring enterprise-grade DevOps practices. Includes real-time monitoring, automated security scanning, Infrastructure as Code, and complete AWS EKS deployment pipeline.

## Recent Updates (September 2025)

### Major Improvements:
- **Migrated to EKS**: Full Kubernetes deployment with AWS Load Balancer Controller
- **PostgreSQL (RDS) Integration**: Full production database support with automatic SSL connections
- **Automatic Database Detection**: Application automatically uses PostgreSQL when available, falls back to SQLite locally
- **Fixed Critical Bug**: Resolved weather data access error in webhook processing
- **Enhanced Security**: Added `force_delete` to ECR repositories for cleaner deployments
- **Simplified Secrets**: Direct Parameter Store access via IRSA (no init containers)
- **Improved Infrastructure**: Auto-deploying ALB Controller, better subnet tagging
- **RDS Terraform Module**: Automated RDS provisioning with Parameter Store integration
- **Code Quality**: Removed redundancies, cleaned up dependencies, consolidated logic
- **New: Optional PVC for SQLite (Helm)**: Persistence is OFF by default; enable via `values.yaml` → `persistence.enabled=true`. When enabled, set `replicas: 1` (SQLite single-writer).
- **Security Hardening**: Pod/container security contexts (non-root, fsGroup, read-only root FS, dropped capabilities).
- **Webhook Rate Limiting**: In-app per-sender limiter (default: 5 requests / 60s) with Prometheus metric `webhook_rate_limited_total`.
- **Resilience**: OpenWeather requests retry with exponential backoff on transient errors.
- **Docker Healthcheck**: Uses curl against `/health` to reduce coupling to Python libs.

### Architecture:
- **AWS EKS** with managed node groups (SPOT instances for cost optimization)
- **AWS Load Balancer Controller** automatically deployed via Terraform
- **IRSA (IAM Roles for Service Accounts)** for secure Parameter Store access
- **PostgreSQL (RDS)** for production database with automatic SSL connections
- **SQLite** fallback for local development
- **Helm charts** for application deployment and management

## What it does
- Accepts a city name over WhatsApp and replies with: city, temperature, description, humidity, feels_like, created_at
- Stores weather lookups in PostgreSQL (RDS) for production or SQLite for local development
- Automatically detects and uses PostgreSQL when available via Parameter Store
- Supports offline mode when no OpenWeather API key is provided

## Tech Stack
- **FastAPI** (Python 3.11) with Prometheus metrics
- **Twilio WhatsApp API** for messaging
- **PostgreSQL (RDS)** for production database with SSL
- **SQLite + SQLAlchemy 2.0** for local development
- **Pydantic** models with validation
- **Docker** multi-stage builds with security hardening
- **Terraform** (custom AWS modules for VPC, EKS, ALB, RDS)
- **Kubernetes (EKS)** with Helm charts for deployment
- **Prometheus + Grafana** for monitoring and observability
- **Automated security scanning** (Trivy, Bandit, Safety)
- **Pre-commit hooks** for code quality and security

## DevOps Features
- **Security**: Automated vulnerability scanning, pre-commit hooks, container hardening
- **Monitoring**: Prometheus metrics, Grafana dashboards, custom business metrics
- **Infrastructure**: Terraform modules for AWS (VPC, EKS, ALB, ECR)
- **Kubernetes**: EKS cluster with Helm charts, auto-scaling, health checks
- **CI/CD**: GitHub Actions with security gates and automated testing
- **Containers**: Multi-stage builds, non-root users, health checks
- **Cost Management**: Minimal resources, destroy/rebuild capability

## Prerequisites
- Docker Desktop
- Python 3.11 (optional for local dev without containers)
- Twilio account with WhatsApp Sandbox (for messaging)
- OpenWeatherMap API key (optional; enables live mode)
- AWS CLI configured (for production deployment)
- Terraform (for infrastructure deployment)
- kubectl (for Kubernetes cluster management)
- Helm (for application deployment)

## Configuration
Environment variables (via Docker Compose or AWS Parameter Store):
- `WEATHER_API_KEY` (required for live weather data; otherwise offline mode)
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM` (for outbound messages)
- `API_HOST` (default `0.0.0.0`), `API_PORT` (default `8000`), `LOG_LEVEL` (default `INFO`)
- `DATABASE_URL` (optional; if not set, uses SQLite locally or PostgreSQL from Parameter Store in AWS)

**Database Configuration:**
- **Local Development**: Uses SQLite (`sqlite:///./weather_bot.db`) by default
- **AWS Production**: Automatically uses PostgreSQL (RDS) when database parameters are found in Parameter Store
- **Manual Override**: Set `DATABASE_URL` environment variable to override automatic detection

AWS Parameter Store is used for secure credential management in production. Database credentials are automatically stored by Terraform when RDS is enabled. Do not commit real secrets.

## Run locally (Docker Compose)
```bash
docker-compose up --build
# API at http://localhost:8000

# Test weather endpoint (offline mode if no API key)
curl -X POST http://localhost:8000/weather -H "Content-Type: application/json" -d '{"city":"London"}'
```

Notes:
- The compose file sets `API_HOST=0.0.0.0` and `API_PORT=8000` by default.
- Healthcheck is enabled; container reports healthy when `/health` returns 200 (checked via curl).
- Optional local conveniences (commented in `docker-compose.yml`):
  - Map `./.env.local` to `/app/.env` if you use a local env file
  - Mount `./src` for hot-reload during development


## Twilio WhatsApp setup
1) Enable WhatsApp in Twilio Console
2) Configure WhatsApp messaging service
3) Set the webhook URL to your bot endpoint (local: use `ngrok http 8000` and configure the public URL)
4) Environment vars required: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM`

Local webhook test:
```bash
curl -X POST http://localhost:8000/webhook \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "From=whatsapp:+1234567890&Body=London"
```

Webhook security:
- Bot validates Twilio signatures on `/webhook` when `TWILIO_AUTH_TOKEN` is set.
- Ensure the webhook URL exactly matches the URL configured in Twilio Console.

## API endpoints
- `GET /health` – health and DB connectivity check
- `POST /weather` – JSON body `{ "city": "London" }`
- `POST /webhook` – Twilio WhatsApp webhook (form-encoded)


## Security and secrets
- Do not commit real secrets. Use AWS Parameter Store for production
- Terraform references SSM Parameter Store ARNs (see `terraform/environments/dev/main.tf`)
- `.gitignore` excludes `.env*`, `*.db`, `*.log`, security reports

## Cost efficiency
- Local-first development with Docker Compose
- Offline mode avoids external API calls when no key is set
- Terraform modules prepared for on-demand deployments (destroy when not in use)

## Development tips
- Logs write to console and `weather_bot.log`; adjust `LOG_LEVEL`
- SQLite file `weather_bot.db` is volume-mounted in Docker Compose
- Pydantic validates input (rejects empty or numeric city names)

## Quick Start
```bash
# 1. Clone and setup
git clone <repository-url>
cd whatsapp-weather-bot

# 2. Install pre-commit hooks (recommended)
make pre-commit-install

# 3. Run locally with monitoring
docker compose up --build

# 4. Access services
# - Application: http://localhost:8000
# - Grafana: http://localhost:3000 (admin/admin)
# - Prometheus: http://localhost:9090
```

## Developer Workflow

### Development Commands
```bash
# Setup and quality
make pre-commit-install     # Install pre-commit hooks
make security-scan         # Run comprehensive security scan
make ci                    # Full check pipeline (lint + type + tests)

# Local development
docker compose up --build   # Start app with monitoring
make monitoring-up         # Start monitoring stack only
make logs                  # View application logs

# Testing
make test                  # Run pytest suite
curl -X POST http://localhost:8000/weather \
  -H "Content-Type: application/json" \
  -d '{"city":"London"}'   # Test weather API
```

### Production Deployment
```bash
# AWS deployment (requires AWS CLI configured)
make aws-setup-secrets     # Store credentials in Parameter Store
make aws-deploy-production # Deploy complete infrastructure
make aws-destroy          # Destroy infrastructure (stop billing)
```

### Secrets (IRSA) quick steps
- **Application Secrets**: Store in SSM Parameter Store (SecureString), example:
  - `weather-bot-openweather-key`, `weather-bot-account-sid`, `weather-bot-auth-token`, `weather-bot-whatsapp-from`
- **Database Secrets**: Automatically created by Terraform when RDS is enabled:
  - `/weather-bot/database/host`, `/weather-bot/database/port`, `/weather-bot/database/name`, `/weather-bot/database/username`, `/weather-bot/database/password`
- The app reads secrets via IRSA; ensure the app is deployed in namespace `weather-bot` with service account `weather-bot-sa`.
- The service account must be annotated with the IAM role:
  - `eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/weather-bot-parameter-store-role`
- After updating secrets/annotation, restart the deployment to pick up changes.
  - `kubectl rollout restart deploy/weather-bot -n weather-bot`

### CI
- GitHub Actions runs on every push/PR:
  - Install deps, run tests, ruff lint, and mypy type checks
  - Failing checks block merges so the repo stays healthy

## Production Deployment (AWS/EKS/ALB)
Automated deployment with Kubernetes and cost management:

### Quick Deploy:
```bash
# 1. Store application secrets in AWS Parameter Store
./scripts/setup/setup-aws-secrets.sh

# 2. Deploy complete infrastructure (VPC, EKS, ALB, ECR, RDS) + application to EKS
./scripts/deployment/deploy-aws-production.sh
# Note: RDS PostgreSQL is enabled by default. Terraform automatically creates database
# parameters in Parameter Store. The application will automatically use PostgreSQL.

# 3. (Optional) If RDS was created separately, set up database parameters:
# python scripts/setup/setup-rds-parameters.py

# 4. Configure Twilio webhook with provided ALB URL
# 5. Test WhatsApp integration
```

### Alternative Manual Steps:
```bash
# 1. Deploy infrastructure (includes RDS PostgreSQL by default)
cd terraform/environments/dev
terraform init && terraform apply
# RDS is enabled by default (var.enable_rds = true)
# Terraform automatically creates database parameters in Parameter Store

# 2. Build and push Docker image
docker build -t weather-bot .
aws ecr get-login-password --region <AWS_REGION> | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com
docker tag weather-bot:latest <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/weather-bot:latest
docker push <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/weather-bot:latest

# 3. Deploy application with Helm
helm upgrade --install weather-bot ./whatsapp-weather-bot-chart \
    --namespace weather-bot \
    --create-namespace \
    --set image.repository=<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/weather-bot \
    --set image.tag=latest \
    --set iam.roleArn=arn:aws:iam::<AWS_ACCOUNT_ID>:role/weather-bot-parameter-store-role \
    --set aws.region=<AWS_REGION>
# Application will automatically detect and use PostgreSQL from Parameter Store
```

### Cost Management:
```bash
# Stop ALL billing immediately
cd terraform/environments/dev
terraform destroy -auto-approve

# Force cleanup ECR repositories if needed
aws ecr delete-repository --repository-name weather-bot --force
aws ecr delete-repository --repository-name weather-bot-init --force
```

### Estimated Costs:
- **EKS cluster**: ~$72/month (control plane)
- **Worker nodes (2x t3.small SPOT)**: ~$15/month
- **ALB**: ~$16/month
- **RDS PostgreSQL (db.t3.micro)**: ~$15/month
- **Total**: ~$118/month
- **When destroyed**: $0/month

### EKS Management Commands:
```bash
# Connect kubectl to EKS cluster
make eks-connect

# Check cluster and application status
make eks-status

# View application logs
make eks-logs

# Scale application
kubectl scale deployment weather-bot -n weather-bot --replicas=3
```

Notes:
- Kubernetes pods read secrets from SSM via service accounts; redeploy to pick up changes.
- Logs are in CloudWatch `/aws/eks/weather-bot/cluster` and pod logs via kubectl.
- **Database**: RDS PostgreSQL is enabled by default and automatically configured via Parameter Store.
- Application automatically detects PostgreSQL when database parameters exist in Parameter Store.
- To disable RDS: Set `enable_rds = false` in Terraform variables or use `terraform apply -var="enable_rds=false"`.

### Troubleshooting
- ALB not reachable yet: wait a few minutes for DNS to propagate; verify Ingress `ingressClassName: alb` and controller installed.
- `/health` shows `"credentials_present": false`: check
  - SSM parameter exists in the correct region
  - App runs in namespace `weather-bot` and SA is annotated with the correct role ARN
  - Pod has `AWS_REGION` set (Helm value `aws.region`)
  - Restart the deployment after fixing the above
- `/health` shows `"database_connected": false`: check
  - RDS instance is running (if enabled)
  - Database parameters exist in Parameter Store (`/weather-bot/database/*`)
  - Security groups allow EKS pods to reach RDS (configured automatically by Terraform)
  - Application logs show database connection attempts
  - Verify RDS endpoint: `terraform output rds_endpoint`

### Database Configuration

**Production (AWS):**
- **RDS PostgreSQL** is enabled by default via Terraform (`enable_rds = true`)
- Database credentials are automatically stored in Parameter Store by Terraform
- Application automatically detects and connects to PostgreSQL when parameters are available
- Supports multiple replicas with shared database state
- SSL connections are enforced (`sslmode=require`)

**Local Development:**
- Uses **SQLite** by default (`sqlite:///./weather_bot.db`)
- Optional: enable PVC-backed persistence for SQLite in Helm:
  - Set in `whatsapp-weather-bot-chart/values.yaml`:
    - `persistence.enabled: true`
    - `persistence.size: 1Gi` (as needed)
    - `persistence.storageClass: ""` (empty → use cluster default)
  - Important: When enabling SQLite persistence, set `replicas: 1` (SQLite is single-writer)
  - Security: The pod runs as non-root and uses `fsGroup` so the mounted volume is writable without being world-writable

**Manual RDS Setup:**
If RDS was created outside of Terraform or parameters need to be updated:
```bash
python scripts/setup/setup-rds-parameters.py
```
This script retrieves RDS details from Terraform or AWS and creates/updates Parameter Store entries.

## Project Architecture

```
├── src/                           # Application source code
│   ├── api/                      # FastAPI endpoints with Prometheus metrics
│   ├── config/                   # Settings and logging configuration
│   ├── database/                 # SQLAlchemy models and database setup
│   ├── models/                   # Pydantic request/response schemas
│   └── services/                 # Business logic (weather API integration)
├── terraform/                    # Infrastructure as Code
│   ├── modules/                  # Custom Terraform modules (VPC, EKS, ALB, RDS)
│   │   ├── vpc/                  # VPC with public/private subnets
│   │   ├── eks/                  # EKS cluster with node groups
│   │   ├── alb-eks/              # ALB with AWS Load Balancer Controller
│   │   └── rds/                  # RDS PostgreSQL database module
│   └── environments/dev/         # Environment-specific configurations
├── whatsapp-weather-bot-chart/   # Helm chart for Kubernetes deployment
│   ├── templates/                # Kubernetes resource templates
│   └── values.yaml               # Configuration values
├── monitoring/                   # Prometheus and Grafana configurations
├── scripts/                      # Deployment and utility scripts
├── tests/                        # Comprehensive test suite
└── .github/workflows/            # CI/CD pipeline with security scanning
```

## Security Features
- **Vulnerability Scanning**: Automated container and dependency scanning
- **Pre-commit Hooks**: Code quality and security checks before commits
- **Container Hardening**: Multi-stage builds, non-root users, minimal attack surface
- **Secrets Management**: AWS Parameter Store for production credentials
- **Network Security**: VPC isolation, security groups, ALB with health checks
- **Least-Privilege Runtime**: Pod/container security contexts
  - Non-root user (`runAsNonRoot`, `runAsUser`)
  - Group-owned writable volumes (`fsGroup`)
  - Read-only root filesystem
  - Linux capabilities dropped and privilege escalation disabled

## Monitoring & Observability
- **Custom Metrics**: Weather requests by city, WhatsApp message types, database operations
- **Grafana Dashboards**: Real-time visualization of application and business metrics
- **Health Checks**: Application and infrastructure health monitoring
- **Structured Logging**: JSON logs with correlation IDs and context
- **Rate Limiting Metrics**: `webhook_rate_limited_total{sender}` – counts requests rejected by the app’s per-sender limiter.
- **Access Control**: Expose `/metrics` only inside the cluster. If public access is required, protect with auth/allowlists.

## Abuse protection

- In-app per-sender rate limiting on `/webhook`:
  - Default: 5 requests per 60 seconds per `From` number
  - Exceeding the limit returns HTTP 429 with a short message
  - Implementation is per-pod (in-memory). For strict global limits across replicas, use Redis or WAF.