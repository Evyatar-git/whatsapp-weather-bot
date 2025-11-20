#!/bin/bash

set -e

echo "=== Minikube Setup for Weather Bot ==="
echo ""

echo "1. Checking minikube installation..."
if ! command -v minikube &> /dev/null; then
    echo "✗ minikube not found. Please install it first:"
    echo "  Windows: choco install minikube"
    echo "  Or download from: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi
echo "✓ minikube found"
echo ""

echo "2. Starting minikube cluster..."
if minikube status &>/dev/null; then
    echo "✓ Minikube cluster already running"
    minikube status
else
    echo "Starting new minikube cluster..."
    minikube start --driver=docker --memory=4096 --cpus=2
    echo "✓ Minikube cluster started"
fi
echo ""

echo "3. Configuring Docker to use minikube's Docker daemon..."
eval $(minikube docker-env)
echo "✓ Docker configured for minikube"
echo ""

echo "4. Building application image..."
cd ..
docker build -t weather-bot:latest .
echo "✓ Image built: weather-bot:latest"
echo ""

echo "5. Installing metrics-server (required for HPA)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
echo "✓ metrics-server installed"
echo ""

echo "6. Verifying cluster is ready..."
kubectl cluster-info
kubectl get nodes
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Deploy the application:"
echo "   helm upgrade --install weather-bot ./whatsapp-weather-bot-chart \\"
echo "     --namespace weather-bot --create-namespace \\"
echo "     --set image.repository=weather-bot \\"
echo "     --set image.tag=latest \\"
echo "     --set autoscaling.enabled=true \\"
echo "     --set podDisruptionBudget.enabled=true \\"
echo "     --set ingress.enabled=false"
echo ""
echo "2. Check status:"
echo "   kubectl get pods -n weather-bot"
echo "   kubectl get hpa -n weather-bot"
echo "   kubectl get pdb -n weather-bot"
echo ""
echo "3. Access application:"
echo "   minikube service weather-bot-service -n weather-bot"
echo ""


