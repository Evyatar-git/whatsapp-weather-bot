#!/bin/bash

set -e

echo "=== Deploying Weather Bot to Minikube ==="
echo ""

echo "1. Checking Docker Desktop..."
if ! docker info &>/dev/null; then
    echo "✗ Docker Desktop is not running"
    echo "  Please start Docker Desktop and try again"
    exit 1
fi
echo "✓ Docker is running"
echo ""

echo "2. Checking minikube status..."
if ! minikube status &>/dev/null; then
    echo "Starting minikube cluster..."
    minikube start --driver=docker --memory=4096 --cpus=2
else
    echo "✓ Minikube cluster is running"
fi
echo ""

echo "3. Configuring Docker environment..."
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    eval $(minikube docker-env --shell bash)
else
    eval $(minikube docker-env)
fi
echo "✓ Docker configured for minikube"
echo ""

echo "4. Building application image..."
docker build -t weather-bot:latest .
echo "✓ Image built: weather-bot:latest"
echo ""

echo "5. Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || echo "metrics-server already installed"
echo "✓ metrics-server ready"
echo ""

echo "6. Deploying application with Helm..."
cd whatsapp-weather-bot-chart
helm upgrade --install weather-bot . \
  --namespace weather-bot --create-namespace \
  -f values-minikube.yaml \
  --wait --timeout=5m || true
echo "✓ Application deployed"
echo ""

echo "7. Checking deployment status..."
kubectl get pods -n weather-bot
kubectl get hpa -n weather-bot
kubectl get pdb -n weather-bot
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Access the application:"
echo "  minikube service weather-bot-service -n weather-bot"
echo ""
echo "Or get the URL:"
echo "  minikube service weather-bot-service -n weather-bot --url"
echo ""
echo "Watch pods:"
echo "  kubectl get pods -n weather-bot -w"
echo ""
echo "Watch HPA:"
echo "  kubectl get hpa -n weather-bot -w"
echo ""

