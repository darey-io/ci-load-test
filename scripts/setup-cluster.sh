#!/bin/bash
set -euo pipefail

echo "======================================"
echo "📦 Setting up KinD Cluster"
echo "======================================"

# Install KinD
echo "Installing KinD..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Verify installation
kind version

# Create cluster configuration
echo "Creating KinD cluster configuration..."
cat <<EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
  labels:
    tier: backend
- role: worker
  labels:
    tier: backend
EOF

# Create the cluster
echo "🚀 Creating KinD cluster with 3 nodes (1 control-plane + 2 workers)..."
kind create cluster --name load-test-cluster --config=/tmp/kind-config.yaml --wait 300s

# Verify cluster
echo "✅ Cluster created successfully!"
kubectl cluster-info --context kind-load-test-cluster
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide

# Install Nginx Ingress Controller
echo ""
echo "======================================"
echo "🔧 Installing Nginx Ingress Controller"
echo "======================================"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller to be ready
echo "⏳ Waiting for ingress controller to be ready (this may take 2-3 minutes)..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Verify ingress controller
echo "✅ Ingress controller is ready!"
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Final verification
echo ""
echo "======================================"
echo "✅ Cluster Setup Complete!"
echo "======================================"
echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
echo "Namespaces: $(kubectl get namespaces --no-headers | wc -l)"
echo "Ingress Controller: Running"
echo "======================================"
