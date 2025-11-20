#!/bin/bash

# Full AWS Production Deployment Script
# This script deploys the Weather Bot to AWS using Terraform + EKS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Weather Bot AWS Production Deployment${NC}"
echo "This will deploy your Weather Bot to AWS with full infrastructure"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Terraform not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}Helm not found. Please install it first.${NC}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${RED}AWS credentials not configured${NC}"
        echo "Please run: aws configure"
        exit 1
    fi
    
    echo -e "${GREEN}All prerequisites met${NC}"
}

# Deploy infrastructure
deploy_infrastructure() {
    echo -e "${BLUE}Checking AWS infrastructure...${NC}"
    
    cd terraform/environments/dev
    
    # Check if infrastructure already exists
    if terraform output ecr_repository_url > /dev/null 2>&1; then
        echo -e "${GREEN}Infrastructure already deployed!${NC}"
        ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
        echo -e "${BLUE}ECR Repository: ${ECR_REPOSITORY_URL}${NC}"
        
        # Save outputs for next steps
        echo "ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL" > ../../../.aws-outputs
        
        cd ../../..
        return 0
    fi
    
    echo -e "${YELLOW}Infrastructure not found. Deploying...${NC}"
    
    # Initialize Terraform
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
    
    # Plan deployment
    echo -e "${YELLOW}Planning deployment...${NC}"
    terraform plan
    
    # Ask for confirmation
    echo ""
    read -p "Do you want to proceed with infrastructure deployment? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
    
    # Apply infrastructure
    echo -e "${YELLOW}Applying infrastructure...${NC}"
    terraform apply -auto-approve
    
    # Get outputs (ECR is from Terraform, ALB will be discovered from Ingress later)
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
    
    echo -e "${GREEN}Infrastructure deployed successfully!${NC}"
    echo -e "${BLUE}ECR Repository: ${ECR_REPOSITORY_URL}${NC}"
    
    # Save outputs for next steps
    echo "ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL" > ../../../.aws-outputs
    
    cd ../../..
}

# Build and push Docker image
build_and_push_image() {
    echo -e "${BLUE}Building and pushing Docker image...${NC}"
    
    # Source the outputs
    source .aws-outputs
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    # Extract ECR base URL for login (remove repository name)
    ECR_BASE_URL=$(echo $ECR_REPOSITORY_URL | sed 's|/.*||')
    
    # Login to ECR
    echo -e "${YELLOW}Logging in to ECR...${NC}"
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_BASE_URL
    
    # Build image
    echo -e "${YELLOW}Building Docker image...${NC}"
    docker build -t weather-bot:latest .
    
    # Tag image for ECR
    docker tag weather-bot:latest $ECR_REPOSITORY_URL:latest
    IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
    docker tag weather-bot:latest $ECR_REPOSITORY_URL:$IMAGE_TAG
    
    # Push to ECR
    echo -e "${YELLOW}Pushing to ECR...${NC}"
    docker push $ECR_REPOSITORY_URL:latest
    docker push $ECR_REPOSITORY_URL:$IMAGE_TAG
    
    echo -e "${GREEN}Docker image pushed successfully!${NC}"
}

# Deploy to EKS using Helm
deploy_to_eks() {
    echo -e "${BLUE}Deploying to EKS using Helm...${NC}"
    
    # Source the outputs
    source .aws-outputs
    
    # Configure kubectl to use EKS cluster
    echo -e "${YELLOW}Configuring kubectl for EKS...${NC}"
    AWS_REGION=$(aws configure get region)
    aws eks update-kubeconfig --region $AWS_REGION --name weather-bot
    
    # Verify cluster connection
    echo -e "${YELLOW}Verifying cluster connection...${NC}"
    kubectl cluster-info
    
    # Install AWS Load Balancer Controller if not already installed
    echo -e "${YELLOW}Installing AWS Load Balancer Controller...${NC}"
    helm repo add eks https://aws.github.io/eks-charts || true
    helm repo update
    
    # Let Helm manage the namespace; do not pre-create to avoid ownership conflicts
    
    # Get AWS account ID and region for IAM role
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/weather-bot-parameter-store-role"
    
    # Deploy the application using Helm
    echo -e "${YELLOW}Deploying Weather Bot with Helm...${NC}"
    helm upgrade --install weather-bot ./whatsapp-weather-bot-chart \
        --namespace weather-bot --create-namespace \
        --set image.repository=$ECR_REPOSITORY_URL \
        --set image.tag=latest \
        --set iam.roleArn=$IAM_ROLE_ARN \
        --set aws.region=$AWS_REGION \
        --wait --timeout=300s
    
    echo -e "${GREEN}EKS deployment completed successfully!${NC}"
    
    # Get service status
    echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app=weather-bot -n weather-bot --timeout=300s
    
    # Get ingress URL
    echo -e "${YELLOW}Getting ALB URL...${NC}"
    # Wait and poll up to ~5 minutes
    for i in {1..30}; do
        ALB_URL=$(kubectl get ingress weather-bot-ingress -n weather-bot -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        if [ -n "$ALB_URL" ]; then
            break
        fi
        echo "Waiting for ALB to be provisioned... ($i/30)"
        sleep 10
    done

    if [ -n "$ALB_URL" ]; then
        echo -e "${GREEN}Application URL: http://$ALB_URL${NC}"
        echo "ALB_URL=$ALB_URL" >> .aws-outputs
    else
        echo -e "${YELLOW}ALB is still provisioning. Check later with:${NC}"
        echo "kubectl get ingress weather-bot-ingress -n weather-bot -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
    fi
}

# Configure Twilio webhook
configure_webhook() {
    echo -e "${BLUE}Webhook Configuration${NC}"
    
    source .aws-outputs || true

    # Prefer ALB_URL discovered from Ingress
    WEBHOOK_URL="${ALB_URL:-}"
    if [ -z "$WEBHOOK_URL" ]; then
        echo -e "${YELLOW}ALB URL not yet available. Retrieve it with:${NC}"
        echo "kubectl get ingress weather-bot-ingress -n weather-bot -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
        WEBHOOK_URL="<ALB_HOSTNAME_PENDING>"
    fi
    
    echo ""
    echo -e "${YELLOW}Manual Step Required:${NC}"
    echo "1. Go to Twilio Console: https://console.twilio.com/"
    echo "2. Navigate to: Messaging → Try it out → Send a WhatsApp message"
    echo "3. In the 'Webhook URL' field, enter:"
    echo -e "${GREEN}   http://$WEBHOOK_URL/webhook${NC}"
    echo "4. Save the configuration"
    echo ""
    echo -e "${BLUE}Your application is now running at: http://$WEBHOOK_URL${NC}"
}

# Main deployment flow
main() {
    check_prerequisites
    
    echo -e "${YELLOW}Deployment Steps:${NC}"
    echo "1. Set up secrets in Parameter Store (if not done)"
    echo "2. Deploy AWS infrastructure (VPC, EKS, ALB, ECR) - SKIP if already done"
    echo "3. Build and push Docker image to ECR"  
    echo "4. Deploy to EKS using Helm"
    echo "5. Configure Twilio webhook"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Have you set up secrets in Parameter Store?${NC}"
    echo "Run: ./scripts/setup/setup-aws-secrets.sh (if not done yet)"
    echo ""
    
    read -p "Ready to start deployment? (y/N): " ready
    if [[ $ready != [yY] ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
    
    deploy_infrastructure
    build_and_push_image
    deploy_to_eks
    configure_webhook
    
    echo ""
    echo -e "${GREEN}DEPLOYMENT COMPLETE!${NC}"
    echo ""
    echo -e "${BLUE}Your Weather Bot is now running in production:${NC}"
    APP_HOST=$(source .aws-outputs 2>/dev/null && echo $ALB_URL)
    echo -e "${GREEN}Application URL: http://$APP_HOST${NC}"
    echo -e "${GREEN}Health Check: http://$APP_HOST/health${NC}"
    echo -e "${GREEN}Metrics: http://$APP_HOST/metrics${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Configure Twilio webhook (see instructions above)"
    echo "2. Test WhatsApp integration by sending a city name"
    echo "3. Monitor logs in AWS CloudWatch"
    echo "4. Scale or destroy resources as needed"
    echo ""
    echo -e "${BLUE}Cost Management:${NC}"
    echo "Run 'terraform destroy' when done testing to avoid charges"
    echo "Monitor costs in AWS Cost Explorer"
}

# Run main function
main "$@"
