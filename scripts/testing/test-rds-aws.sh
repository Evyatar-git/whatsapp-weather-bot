#!/bin/bash

set -e

echo "=== Testing RDS on AWS ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

cd terraform/environments/dev

echo -e "${BLUE}1. Checking Terraform outputs...${NC}"
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_PORT=$(terraform output -raw rds_port 2>/dev/null || echo "")
RDS_DB_NAME=$(terraform output -raw rds_database_name 2>/dev/null || echo "")
RDS_SSM_PARAMS=$(terraform output -json rds_ssm_parameters 2>/dev/null || echo "[]")

if [ -z "$RDS_ENDPOINT" ]; then
    echo -e "${RED}✗ RDS endpoint not found. Is RDS deployed?${NC}"
    exit 1
fi

echo -e "${GREEN}✓ RDS Endpoint: ${RDS_ENDPOINT}${NC}"
echo -e "${GREEN}✓ RDS Port: ${RDS_PORT}${NC}"
echo -e "${GREEN}✓ RDS Database: ${RDS_DB_NAME}${NC}"
echo ""

echo -e "${BLUE}2. Checking Parameter Store...${NC}"
SSM_PARAMS=$(echo "$RDS_SSM_PARAMS" | jq -r '.[]' 2>/dev/null || echo "")

if [ -z "$SSM_PARAMS" ]; then
    echo -e "${YELLOW}⚠ No SSM parameters found in output${NC}"
else
    echo -e "${GREEN}✓ SSM Parameters:${NC}"
    echo "$SSM_PARAMS" | while read param; do
        echo "  - $param"
    done
fi
echo ""

echo -e "${BLUE}3. Verifying Parameter Store values...${NC}"
for param in "/weather-bot/database/host" "/weather-bot/database/port" "/weather-bot/database/name" "/weather-bot/database/username" "/weather-bot/database/password"; do
    if aws ssm get-parameter --name "$param" --region us-east-1 >/dev/null 2>&1; then
        VALUE=$(aws ssm get-parameter --name "$param" --region us-east-1 --query 'Parameter.Value' --output text 2>/dev/null)
        if [ "$param" == "/weather-bot/database/password" ]; then
            echo -e "${GREEN}✓ $param: [REDACTED]${NC}"
        else
            echo -e "${GREEN}✓ $param: $VALUE${NC}"
        fi
    else
        echo -e "${RED}✗ $param: NOT FOUND${NC}"
    fi
done
echo ""

echo -e "${BLUE}4. Checking EKS pods...${NC}"
kubectl get pods -n weather-bot -l app=weather-bot 2>/dev/null || echo -e "${YELLOW}⚠ No pods found. Is application deployed?${NC}"
echo ""

echo -e "${BLUE}5. Checking application logs for database connection...${NC}"
PODS=$(kubectl get pods -n weather-bot -l app=weather-bot -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$PODS" ]; then
    echo -e "${YELLOW}⚠ No pods found. Deploy application first.${NC}"
else
    for pod in $PODS; do
        echo -e "${BLUE}Pod: $pod${NC}"
        kubectl logs -n weather-bot "$pod" --tail=50 | grep -i -E "(database|postgresql|sqlite|connection|error)" | tail -10 || echo "  No database-related logs found"
    done
fi
echo ""

echo -e "${BLUE}6. Testing health endpoint...${NC}"
SERVICE_URL=$(kubectl get ingress weather-bot-ingress -n weather-bot -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$SERVICE_URL" ]; then
    echo -e "${YELLOW}⚠ Ingress not ready. Checking service...${NC}"
    SERVICE_URL=$(kubectl get svc weather-bot-service -n weather-bot -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
fi

if [ -n "$SERVICE_URL" ]; then
    HEALTH=$(curl -s "http://${SERVICE_URL}/health" 2>/dev/null || echo "")
    if [ -n "$HEALTH" ]; then
        echo -e "${GREEN}✓ Health endpoint response:${NC}"
        echo "$HEALTH" | jq '.' 2>/dev/null || echo "$HEALTH"
    else
        echo -e "${YELLOW}⚠ Could not reach health endpoint${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Service URL not available${NC}"
fi
echo ""

echo -e "${BLUE}7. Testing database connection from pod...${NC}"
if [ -n "$PODS" ]; then
    FIRST_POD=$(echo $PODS | awk '{print $1}')
    echo -e "${BLUE}Executing database test in pod: $FIRST_POD${NC}"
    kubectl exec -n weather-bot "$FIRST_POD" -- python -c "
from src.database import test_database_connection
result = test_database_connection()
print('Database connection:', 'PASSED' if result else 'FAILED')
" 2>&1 || echo -e "${YELLOW}⚠ Could not execute test${NC}"
else
    echo -e "${YELLOW}⚠ No pods available for testing${NC}"
fi

echo ""
echo -e "${GREEN}=== Testing Complete ===${NC}"


