#!/bin/bash
set -euo pipefail

echo "🚀 Deploying applications..."

# Apply all manifests
kubectl apply -f k8s/foo-deployment.yaml
kubectl apply -f k8s/bar-deployment.yaml
kubectl apply -f k8s/ingress.yaml

echo "⏳ Waiting for deployments to be ready..."

# Wait for foo deployment
kubectl wait --for=condition=available --timeout=180s deployment/foo-echo

# Wait for bar deployment
kubectl wait --for=condition=available --timeout=180s deployment/bar-echo

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=foo-echo --timeout=180s
kubectl wait --for=condition=ready pod -l app=bar-echo --timeout=180s

echo "⏳ Waiting for ingress to be ready..."
sleep 10

# Verify ingress
kubectl get ingress echo-ingress

echo "🔍 Testing connectivity..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
  if curl -s -H "Host: foo.localhost" http://localhost/ | grep -q "foo" && \
     curl -s -H "Host: bar.localhost" http://localhost/ | grep -q "bar"; then
    echo "✅ Both endpoints are responding correctly"
    break
  fi
  attempt=$((attempt + 1))
  echo "Attempt $attempt/$max_attempts: Waiting for endpoints..."
  sleep 2
done

if [ $attempt -eq $max_attempts ]; then
  echo "❌ Endpoints did not become ready in time"
  exit 1
fi

echo "✅ All deployments and ingress are healthy"
kubectl get pods -o wide
kubectl get svc
kubectl get ingress
