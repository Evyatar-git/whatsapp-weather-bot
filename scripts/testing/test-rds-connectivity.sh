#!/bin/bash

# RDS Connectivity Diagnostic Script
# This script helps diagnose connectivity issues between EKS pods and RDS
# Usage: ./scripts/test-rds-connectivity.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== RDS Connectivity Diagnostic Tool ===${NC}\n"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Get RDS endpoint from Parameter Store or Terraform output
echo -e "${BLUE}Step 1: Retrieving RDS endpoint...${NC}"
cd terraform/environments/dev 2>/dev/null || cd ../../environments/dev

RDS_HOST=""
RDS_PORT="5432"

if terraform output rds_endpoint &> /dev/null; then
    RDS_HOST=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
fi

if [ -z "$RDS_HOST" ]; then
    # Try Parameter Store
    echo -e "${YELLOW}Attempting to get RDS endpoint from Parameter Store...${NC}"
    RDS_HOST=$(aws ssm get-parameter --name "/weather-bot/database/host" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    RDS_PORT=$(aws ssm get-parameter --name "/weather-bot/database/port" --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
fi

if [ -z "$RDS_HOST" ]; then
    echo -e "${RED}Error: Could not retrieve RDS endpoint. Please ensure infrastructure is deployed.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ RDS Endpoint: ${RDS_HOST}:${RDS_PORT}${NC}\n"

# Check if we're connected to the right cluster
echo -e "${BLUE}Step 2: Verifying Kubernetes cluster connection...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Not connected to Kubernetes cluster${NC}"
    echo -e "${YELLOW}Run: aws eks update-kubeconfig --name weather-bot --region us-east-1${NC}"
    exit 1
fi

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null || echo "unknown")
echo -e "${GREEN}✓ Connected to cluster: ${CLUSTER_NAME}${NC}\n"

# Check if weather-bot namespace exists
echo -e "${BLUE}Step 3: Checking namespace...${NC}"
if ! kubectl get namespace weather-bot &> /dev/null; then
    echo -e "${YELLOW}Namespace 'weather-bot' does not exist. Creating it...${NC}"
    kubectl create namespace weather-bot
fi
echo -e "${GREEN}✓ Namespace exists${NC}\n"

# Create a test pod with network tools
echo -e "${BLUE}Step 4: Creating diagnostic pod...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rds-connectivity-test
  namespace: weather-bot
spec:
  containers:
  - name: netcat
    image: busybox:latest
    command: ['sh', '-c', 'sleep 3600']
  restartPolicy: Never
EOF

echo -e "${YELLOW}Waiting for pod to be ready...${NC}"
kubectl wait --for=condition=Ready pod/rds-connectivity-test -n weather-bot --timeout=60s || {
    echo -e "${RED}Error: Pod failed to start${NC}"
    kubectl describe pod rds-connectivity-test -n weather-bot
    exit 1
}
echo -e "${GREEN}✓ Diagnostic pod is ready${NC}\n"

# Test 1: Basic network connectivity (TCP connection)
echo -e "${BLUE}Step 5: Testing TCP connectivity to RDS (port ${RDS_PORT})...${NC}"
if kubectl exec -n weather-bot rds-connectivity-test -- nc -zv -w 5 ${RDS_HOST} ${RDS_PORT} 2>&1; then
    echo -e "${GREEN}✓ TCP connection successful!${NC}\n"
    TCP_SUCCESS=true
else
    echo -e "${RED}✗ TCP connection failed${NC}\n"
    TCP_SUCCESS=false
fi

# Test 2: DNS resolution
echo -e "${BLUE}Step 6: Testing DNS resolution...${NC}"
if kubectl exec -n weather-bot rds-connectivity-test -- nslookup ${RDS_HOST} 2>&1 | grep -q "Address"; then
    RESOLVED_IP=$(kubectl exec -n weather-bot rds-connectivity-test -- nslookup ${RDS_HOST} 2>&1 | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    echo -e "${GREEN}✓ DNS resolution successful: ${RDS_HOST} → ${RESOLVED_IP}${NC}\n"
else
    echo -e "${RED}✗ DNS resolution failed${NC}\n"
fi

# Test 3: Check security groups (if we can get the info)
echo -e "${BLUE}Step 7: Gathering security group information...${NC}"
echo -e "${YELLOW}Note: This requires AWS CLI access${NC}"

# Get pod's node
POD_NODE=$(kubectl get pod rds-connectivity-test -n weather-bot -o jsonpath='{.spec.nodeName}')
echo -e "Pod is running on node: ${POD_NODE}"

# Get EKS node group security group
if terraform output node_group_security_group_id &> /dev/null; then
    NODE_SG=$(terraform output -raw node_group_security_group_id 2>/dev/null || echo "")
    echo -e "EKS Node Group Security Group: ${NODE_SG}"
fi

# Get RDS security group
if terraform output rds_security_group_id &> /dev/null; then
    RDS_SG=$(terraform output -raw rds_security_group_id 2>/dev/null || echo "")
    echo -e "RDS Security Group: ${RDS_SG}"
    
    if [ -n "$RDS_SG" ]; then
        echo -e "\n${BLUE}Checking RDS security group ingress rules...${NC}"
        aws ec2 describe-security-groups --group-ids ${RDS_SG} --query 'SecurityGroups[0].IpPermissions' --output table 2>/dev/null || echo -e "${YELLOW}Could not retrieve security group rules${NC}"
    fi
fi

echo ""

# Test 4: PostgreSQL connection (if psql is available)
echo -e "${BLUE}Step 8: Testing PostgreSQL connection...${NC}"
echo -e "${YELLOW}Note: This requires database credentials${NC}"

# Try to get credentials from Parameter Store
DB_USER=$(aws ssm get-parameter --name "/weather-bot/database/username" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "")
DB_NAME=$(aws ssm get-parameter --name "/weather-bot/database/name" --query 'Parameter.Value' --output text 2>/dev/null || echo "")

if [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
    echo -e "${YELLOW}Attempting PostgreSQL connection (password required)...${NC}"
    echo -e "${YELLOW}Note: Full connection test requires password. Testing connection string format only.${NC}"
    echo -e "Connection string: postgresql://${DB_USER}:***@${RDS_HOST}:${RDS_PORT}/${DB_NAME}"
else
    echo -e "${YELLOW}Could not retrieve database credentials from Parameter Store${NC}"
fi

echo ""

# Summary
echo -e "${BLUE}=== Diagnostic Summary ===${NC}"
if [ "$TCP_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ Network connectivity: PASSED${NC}"
    echo -e "${GREEN}Next steps: Verify application can connect using credentials${NC}"
else
    echo -e "${RED}✗ Network connectivity: FAILED${NC}"
    echo -e "${YELLOW}Possible issues:${NC}"
    echo -e "  1. Security group rules not allowing traffic"
    echo -e "  2. RDS and EKS in different subnets without proper routing"
    echo -e "  3. RDS subnet group misconfiguration"
    echo -e "  4. Network ACLs blocking traffic"
fi

echo ""
echo -e "${BLUE}Cleaning up diagnostic pod...${NC}"
kubectl delete pod rds-connectivity-test -n weather-bot --ignore-not-found=true
echo -e "${GREEN}✓ Cleanup complete${NC}"

