#!/bin/bash

# Script to fetch secrets from AWS Parameter Store and create Kubernetes Secret
# This runs in an init container before the main application starts

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
APP_NAME="weather-bot"

echo "Fetching secrets from AWS Parameter Store..."

# Function to fetch a parameter
fetch_secret() {
    local param_name="$1"
    local full_param_name="weather-bot-${param_name}"
    
    echo "Fetching parameter: $full_param_name"
    
    # Fetch the parameter value
    aws ssm get-parameter \
        --name "$full_param_name" \
        --with-decryption \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null
}

# Fetch all required secrets (match application parameter names)
WEATHER_API_KEY=$(fetch_secret "openweather-key")
TWILIO_ACCOUNT_SID=$(fetch_secret "account-sid")
TWILIO_AUTH_TOKEN=$(fetch_secret "auth-token")
TWILIO_WHATSAPP_FROM=$(fetch_secret "whatsapp-from")

# Create Kubernetes Secret
echo "Creating Kubernetes Secret..."
kubectl create secret generic "$APP_NAME-secrets" \
    --from-literal=WEATHER_API_KEY="$WEATHER_API_KEY" \
    --from-literal=TWILIO_ACCOUNT_SID="$TWILIO_ACCOUNT_SID" \
    --from-literal=TWILIO_AUTH_TOKEN="$TWILIO_AUTH_TOKEN" \
    --from-literal=TWILIO_WHATSAPP_FROM="$TWILIO_WHATSAPP_FROM" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Kubernetes Secret created successfully!"
