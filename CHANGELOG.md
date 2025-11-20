# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2025-11-20

### Added
- **PostgreSQL (RDS) Support**
  - Full RDS PostgreSQL integration with automatic SSL connections
  - Automatic database detection (PostgreSQL in production, SQLite locally)
  - Terraform RDS module with Parameter Store integration
  - Database initialization on application startup

- **Kubernetes Enhancements**
  - Horizontal Pod Autoscaler (HPA) for automatic scaling
  - Pod Disruption Budget (PDB) for high availability
  - Minikube support for local Kubernetes development

- **Script Organization**
  - Organized scripts into logical categories (deployment, setup, testing, utils)
  - Added comprehensive scripts documentation

### Changed
- **Database Configuration**
  - Application automatically detects and uses PostgreSQL when available
  - Improved database connection handling with connection pooling
  - Enhanced error handling for database operations

- **Project Structure**
  - Reorganized scripts directory for better maintainability
  - Removed redundant scripts (test-rds-migration.sh, monitor-rds.sh, init-database.py, test-hpa-pdb.sh)
  - Updated all script references in documentation

- **Documentation**
  - Updated README with RDS/PostgreSQL information
  - Added scripts/README.md for script organization
  - Improved deployment documentation

### Fixed
- Fixed LOG_LEVEL in production values.yaml (DEBUG → INFO)
- Fixed script path references after reorganization
- Improved database initialization error handling

## [2.0.0] - 2025-09-17

### Added
- **Security Features**
  - Prometheus metrics integration with custom business metrics
  - Pre-commit hooks with security scanning (Bandit, Safety, detect-secrets)
  - Container vulnerability scanning with Trivy
  - Automated security scanning in CI/CD pipeline
  - Multi-stage Docker builds with non-root user security

- **Monitoring & Observability**
  - Grafana dashboards for real-time application monitoring
  - Custom Prometheus metrics for weather requests and WhatsApp messages
  - Database operation timing metrics
  - Infrastructure as Code for monitoring stack

- **Infrastructure Improvements**
  - Enhanced Terraform modules for monitoring
  - Cost-optimized AWS deployment configurations
  - Automated deployment and destruction scripts
  - AWS Parameter Store integration for secure credential management

- **DevOps Enhancements**
  - Comprehensive security scanning workflow
  - Automated dependency vulnerability detection
  - Production-ready container configurations
  - Cost management and billing control scripts

### Security Fixes
- Updated FastAPI from 0.104.1 to 0.116.1 (Fixed CVE-2024-24762)
- Updated Twilio from 8.10.0 to 9.8.0 (Fixed CVE-2023-37920, CVE-2022-23491, CVE-2024-27306)
- Updated requests from 2.31.0 to 2.32.5 (Fixed CVE-2024-35195, CVE-2024-47081)
- Updated python-multipart from 0.0.6 to 0.0.20 (Fixed CVE-2024-53981, ReDoS vulnerability)
- Updated Pydantic to 2.9.2 for compatibility

### Changed
- Enhanced Docker Compose with monitoring stack
- Improved Makefile with security and monitoring commands
- Updated README with comprehensive DevOps feature documentation
- Cleaned up unnecessary development files and comments

## [1.0.0] - Initial Release

### Added
- FastAPI-based WhatsApp Weather Bot
- Twilio WhatsApp API integration
- OpenWeatherMap API integration
- SQLite database with SQLAlchemy
- Docker containerization
- Kubernetes deployment manifests
- Terraform AWS infrastructure modules
- Comprehensive testing suite
- GitHub Actions CI/CD pipeline
