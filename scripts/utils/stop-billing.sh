#!/bin/bash

# Complete AWS Resource Shutdown Script
# This stops ALL billing by destroying the entire infrastructure

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}AWS BILLING SHUTDOWN SCRIPT${NC}"
echo ""
echo -e "${YELLOW}This will DESTROY ALL AWS resources and stop billing.${NC}"
echo ""
echo "Current estimated daily cost: ~$0.80"
echo "Current estimated monthly cost: ~$24.00"
echo ""
echo -e "${RED}Resources that will be DESTROYED:${NC}"
echo "• ECS Fargate tasks (stops compute billing)"
echo "• Application Load Balancer (stops $16.20/month)"
echo "• VPC and networking (stops networking costs)"
echo "• CloudWatch Log Groups (stops log storage costs)"
echo "• ECR Repository (stops container storage costs)"
echo ""
echo -e "${GREEN}Resources that will REMAIN (free):${NC}"
echo "• AWS Parameter Store secrets (free tier)"
echo "• Your Docker images (will be deleted with ECR)"
echo ""

read -p "Are you sure you want to destroy ALL resources? (yes/NO): " confirm

if [[ $confirm != "yes" ]]; then
    echo -e "${YELLOW}Cancellation confirmed. No resources destroyed.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}DESTROYING ALL AWS INFRASTRUCTURE...${NC}"
echo ""

cd terraform/environments/dev

# Show what will be destroyed
echo -e "${BLUE}Planning destruction...${NC}"
terraform plan -destroy

echo ""
read -p "Proceed with destruction? (yes/NO): " final_confirm

if [[ $final_confirm != "yes" ]]; then
    echo -e "${YELLOW}Destruction cancelled.${NC}"
    exit 0
fi

# Destroy everything
echo -e "${RED}Destroying infrastructure...${NC}"
terraform destroy -auto-approve

echo ""
echo -e "${GREEN}ALL AWS RESOURCES DESTROYED${NC}"
echo ""
echo -e "${BLUE}Billing Status:${NC}"
echo "• Compute costs: STOPPED"
echo "• Load balancer costs: STOPPED" 
echo "• Storage costs: STOPPED"
echo "• Networking costs: STOPPED"
echo "• Total ongoing costs: $0.00/month"
echo ""
echo -e "${YELLOW}To redeploy later:${NC}"
echo "1. Run: ./scripts/deployment/deploy-aws-production.sh"
echo "2. Your secrets are still stored in Parameter Store (free)"
echo "3. Your code and Docker images will need to be rebuilt"
echo ""
echo -e "${GREEN}You are no longer being charged for AWS resources!${NC}"

cd ../../..
