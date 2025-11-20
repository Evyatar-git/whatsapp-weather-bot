#!/bin/bash

set -e

NAMESPACE="weather-bot"
APP_NAME="weather-bot"

echo "=== Testing Weather Bot on Minikube ==="
echo ""

echo "1. Checking pod status..."
kubectl get pods -n ${NAMESPACE}
echo ""

echo "2. Checking HPA status..."
kubectl get hpa -n ${NAMESPACE}
if kubectl get hpa ${APP_NAME}-hpa -n ${NAMESPACE} &>/dev/null; then
    echo ""
    echo "HPA Details:"
    kubectl describe hpa ${APP_NAME}-hpa -n ${NAMESPACE} | grep -E "(Min replicas|Max replicas|Metrics|Targets|Current)" || true
fi
echo ""

echo "3. Checking PDB status..."
kubectl get pdb -n ${NAMESPACE}
if kubectl get pdb ${APP_NAME}-pdb -n ${NAMESPACE} &>/dev/null; then
    echo ""
    echo "PDB Details:"
    kubectl describe pdb ${APP_NAME}-pdb -n ${NAMESPACE} | grep -E "(Min available|Allowed disruptions)" || true
fi
echo ""

echo "4. Checking service..."
kubectl get svc -n ${NAMESPACE}
echo ""

echo "5. Getting application URL..."
SERVICE_URL=$(minikube service ${APP_NAME}-service -n ${NAMESPACE} --url 2>/dev/null || echo "N/A")
if [ "$SERVICE_URL" != "N/A" ]; then
    echo "Service URL: ${SERVICE_URL}"
    echo ""
    echo "Testing health endpoint..."
    curl -s ${SERVICE_URL}/health | jq . || curl -s ${SERVICE_URL}/health
else
    echo "Service URL not available"
fi
echo ""

echo "6. Resource usage (if metrics available)..."
if kubectl top pods -n ${NAMESPACE} 2>/dev/null | grep ${APP_NAME}; then
    kubectl top pods -n ${NAMESPACE} | grep ${APP_NAME}
else
    echo "Metrics not available yet (may take a minute)"
fi
echo ""

echo "=== Test Complete ==="
echo ""
echo "To generate load and test HPA scaling:"
echo "  kubectl run load-test --image=busybox --rm -it --restart=Never -- \\"
echo "    /bin/sh -c 'while true; do wget -q -O- http://${APP_NAME}-service:80/health; sleep 0.1; done'"
echo ""
echo "Watch scaling in action:"
echo "  kubectl get hpa ${APP_NAME}-hpa -n ${NAMESPACE} -w"
echo "  kubectl get pods -n ${NAMESPACE} -w"
echo ""


