#!/bin/bash

# Local Security Scanning Script
# This script performs the same security checks that run in CI/CD
# Run this before pushing code to catch issues early

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

IMAGE_NAME="weather-bot:latest"
REPORTS_DIR="security-reports"

echo -e "${BLUE}Starting comprehensive security scan...${NC}"
echo "This will check for vulnerabilities in:"
echo "  - Docker container (base image + dependencies)"
echo "  - Python dependencies (PyPI vulnerability database)"
echo "  - Python code (security anti-patterns)"
echo ""

# Create reports directory
mkdir -p $REPORTS_DIR

# Step 1: Build Docker image
echo -e "${BLUE}Building Docker image for scanning...${NC}"
docker build -t $IMAGE_NAME . --quiet
echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Step 2: Install scanning tools if not present
echo -e "${BLUE}Installing security scanning tools...${NC}"
pip install --quiet trivy-python safety bandit pip-audit 2>/dev/null || {
    echo -e "${YELLOW}Some tools may not be available via pip. Using Docker alternatives...${NC}"
}

# Step 3: Container vulnerability scanning with Trivy
echo -e "${BLUE}Scanning Docker container with Trivy...${NC}"
echo "Trivy scans for:"
echo "  - OS package vulnerabilities in base image"
echo "  - Known vulnerabilities in Python packages"
echo "  - Container configuration issues"

# Try to use local Trivy, fall back to Docker if not available
if command -v trivy &> /dev/null; then
    trivy image --severity HIGH,CRITICAL --format table $IMAGE_NAME
    trivy image --severity HIGH,CRITICAL --format json --output $REPORTS_DIR/trivy-report.json $IMAGE_NAME
else
    echo "Using Docker version of Trivy..."
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        -v $(pwd):/workspace aquasec/trivy:latest \
        image --severity HIGH,CRITICAL --format table $IMAGE_NAME
    
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        -v $(pwd):/workspace aquasec/trivy:latest \
        image --severity HIGH,CRITICAL --format json --output /workspace/$REPORTS_DIR/trivy-report.json $IMAGE_NAME
fi

echo -e "${GREEN}Container scan completed${NC}"
echo ""

# Step 4: Python dependency vulnerability scanning
echo -e "${BLUE}Scanning Python dependencies for known vulnerabilities...${NC}"

# Safety check
echo "Running Safety (PyPI vulnerability database)..."
safety check --json --output $REPORTS_DIR/safety-report.json 2>/dev/null || {
    echo -e "${YELLOW}Safety found some issues (see report)${NC}"
}
safety check --short-report || echo -e "${YELLOW}Safety completed with warnings${NC}"

# pip-audit check
echo "Running pip-audit (PyPA vulnerability scanner)..."
pip-audit --format=json --output=$REPORTS_DIR/pip-audit-report.json 2>/dev/null || {
    echo -e "${YELLOW}pip-audit found some issues (see report)${NC}"
}

echo -e "${GREEN}Dependency scan completed${NC}"
echo ""

# Step 5: Python code security scanning
echo -e "${BLUE}Scanning Python code for security issues with Bandit...${NC}"
echo "Bandit looks for common security issues like:"
echo "  - Hardcoded passwords or API keys"
echo "  - SQL injection vulnerabilities"
echo "  - Use of insecure functions"
echo "  - Weak cryptographic practices"

bandit -r src/ -f json -o $REPORTS_DIR/bandit-report.json 2>/dev/null || {
    echo -e "${YELLOW}Bandit found some issues (see report)${NC}"
}
bandit -r src/ || echo -e "${YELLOW}Bandit completed with warnings${NC}"

echo -e "${GREEN}Code security scan completed${NC}"
echo ""

# Step 6: Generate summary report
echo -e "${BLUE}Generating security summary...${NC}"

# Count vulnerabilities from reports
TRIVY_CRITICAL=0
TRIVY_HIGH=0
SAFETY_VULNS=0
BANDIT_ISSUES=0

if [ -f "$REPORTS_DIR/trivy-report.json" ]; then
    TRIVY_CRITICAL=$(cat $REPORTS_DIR/trivy-report.json | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' 2>/dev/null || echo 0)
    TRIVY_HIGH=$(cat $REPORTS_DIR/trivy-report.json | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' 2>/dev/null || echo 0)
fi

if [ -f "$REPORTS_DIR/safety-report.json" ]; then
    SAFETY_VULNS=$(cat $REPORTS_DIR/safety-report.json | jq '.vulnerabilities | length' 2>/dev/null || echo 0)
fi

if [ -f "$REPORTS_DIR/bandit-report.json" ]; then
    BANDIT_ISSUES=$(cat $REPORTS_DIR/bandit-report.json | jq '.results | length' 2>/dev/null || echo 0)
fi

# Display summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}           SECURITY SCAN SUMMARY        ${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""
echo "Container Vulnerabilities (Trivy):"
echo -e "  Critical: $TRIVY_CRITICAL"
echo -e "  High: $TRIVY_HIGH"
echo ""
echo "Dependency Vulnerabilities (Safety):"
echo -e "  Python packages: $SAFETY_VULNS"
echo ""
echo "Code Security Issues (Bandit):"
echo -e "  Security issues: $BANDIT_ISSUES"
echo ""

# Determine overall status
TOTAL_CRITICAL=$((TRIVY_CRITICAL))
TOTAL_HIGH=$((TRIVY_HIGH + SAFETY_VULNS + BANDIT_ISSUES))

if [ $TOTAL_CRITICAL -gt 0 ]; then
    echo -e "${RED}CRITICAL ISSUES FOUND${NC}"
    echo "   Action required: Fix critical vulnerabilities before deployment"
    echo "   Check detailed reports in: $REPORTS_DIR/"
    exit 1
elif [ $TOTAL_HIGH -gt 0 ]; then
    echo -e "${YELLOW}HIGH PRIORITY ISSUES FOUND${NC}"
    echo "   Recommendation: Review and fix high priority issues"
    echo "   Check detailed reports in: $REPORTS_DIR/"
    exit 0
else
    echo -e "${GREEN}NO CRITICAL OR HIGH PRIORITY ISSUES FOUND${NC}"
    echo "   Your application appears to be secure!"
fi

echo ""
echo "Detailed reports saved in: $REPORTS_DIR/"
echo "  - trivy-report.json (container vulnerabilities)"
echo "  - safety-report.json (Python dependency vulnerabilities)"
echo "  - bandit-report.json (Python code security issues)"
echo ""
echo -e "${GREEN}Security scan completed!${NC}"
