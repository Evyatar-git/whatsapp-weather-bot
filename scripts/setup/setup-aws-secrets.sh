#!/bin/bash

# AWS Secrets Setup Script
# This script stores all credentials in AWS Systems Manager Parameter Store
# Run this script after collecting all your credentials

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Weather Bot AWS Secrets Setup${NC}"
echo "This script will store your credentials in AWS Parameter Store"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}AWS CLI not configured${NC}"
    echo "Please run: aws configure"
    echo "Enter your AWS Access Key ID, Secret Access Key, and region"
    exit 1
fi

echo -e "${GREEN}AWS CLI configured${NC}"
echo ""

# Function to create secure parameter
create_parameter() {
    local param_name=$1
    local param_value=$2
    local description=$3
    
    echo -e "${YELLOW}Creating parameter: $param_name${NC}"
    
    aws ssm put-parameter \
        --name "$param_name" \
        --value "$param_value" \
        --type "SecureString" \
        --description "$description" \
        --overwrite || {
        echo -e "${RED}Failed to create $param_name${NC}"
        return 1
    }
    
    echo -e "${GREEN}Created $param_name${NC}"
}

# Prompt for credentials
echo -e "${BLUE}Please enter your credentials:${NC}"
echo ""

read -p "OpenWeatherMap API Key: " WEATHER_API_KEY
read -p "Twilio Account SID: " TWILIO_ACCOUNT_SID  
read -s -p "Twilio Auth Token: " TWILIO_AUTH_TOKEN
echo ""
read -p "Twilio WhatsApp From (e.g., whatsapp:+14155238886): " TWILIO_WHATSAPP_FROM

echo ""
echo -e "${BLUE}Creating AWS Parameter Store secrets...${NC}"
echo ""

# Create all parameters (without leading slash to match application lookup: weather-bot-<name>)
create_parameter "weather-bot-openweather-key" "$WEATHER_API_KEY" "OpenWeatherMap API key for weather data"
create_parameter "weather-bot-account-sid" "$TWILIO_ACCOUNT_SID" "Twilio Account SID for WhatsApp messaging" 
create_parameter "weather-bot-auth-token" "$TWILIO_AUTH_TOKEN" "Twilio Auth Token for WhatsApp messaging"
create_parameter "weather-bot-whatsapp-from" "$TWILIO_WHATSAPP_FROM" "Twilio WhatsApp From number"

echo ""
echo -e "${GREEN}All secrets stored successfully in AWS Parameter Store!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Deploy infrastructure: cd terraform/environments/dev && terraform apply"
echo "2. Build and push Docker image to ECR"
echo "3. Deploy application to EKS using Helm"
echo "4. Configure Twilio webhook with ALB URL"
echo ""
echo -e "${YELLOW}Remember: You can view/update these secrets in AWS Console → Systems Manager → Parameter Store${NC}"
