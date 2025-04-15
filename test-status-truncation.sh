#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Envoy Gateway Status Truncation Test ===${NC}"
echo -e "${YELLOW}This script will:${NC}"
echo "1. Set up a kind cluster"
echo "2. Build a local image of Envoy Gateway with our fix"
echo "3. Push it to the kind cluster"
echo "4. Deploy Envoy Gateway"
echo "5. Create 1000 gateways with 2 routes each to generate load"
echo "6. Create a ClientTrafficPolicy that attaches to one of these merged gateways to test our fix"
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed. Please install kind first.${NC}"
    echo "Visit https://kind.sigs.k8s.io/docs/user/quick-start/#installation for installation instructions."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed. Please install kubectl first.${NC}"
    echo "Visit https://kubernetes.io/docs/tasks/tools/install-kubectl/ for installation instructions."
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed. Please install docker first.${NC}"
    echo "Visit https://docs.docker.com/get-docker/ for installation instructions."
    exit 1
fi

echo -e "${GREEN}=== Creating kind cluster ===${NC}"
make create-cluster

echo -e "${GREEN}=== Building Envoy Gateway image ===${NC}"
make kube-install-image

echo -e "${GREEN}=== Deploying Envoy Gateway ===${NC}"
make kube-deploy

echo -e "${GREEN}=== Waiting for Envoy Gateway to be ready ===${NC}"
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

echo -e "${GREEN}=== Creating GatewayClass for merged gateways ===${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: merge-gateways
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: merge-gateways
    namespace: envoy-gateway-system
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: merge-gateways
  namespace: envoy-gateway-system
spec:
  mergeGateways: true
  provider:
    type: Kubernetes
EOF

echo -e "${GREEN}=== Creating test namespace ===${NC}"
kubectl create namespace test-status-truncation

echo -e "${GREEN}=== Creating backend service ===${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: test-status-truncation
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: test-status-truncation
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: gcr.io/k8s-staging-gateway-api/echo-basic:v20230802-v0.7.0-58-g42344f1a
        ports:
        - containerPort: 8080
EOF

echo -e "${GREEN}=== Creating 1000 gateways with 2 routes each ===${NC}"
for i in {1..1000}; do
  echo -e "${YELLOW}Creating gateway $i/1000${NC}"
  
  cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-$i
  namespace: test-status-truncation
spec:
  gatewayClassName: merge-gateways
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: route-a-$i
  namespace: test-status-truncation
spec:
  parentRefs:
  - name: gateway-$i
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /a
    backendRefs:
    - name: backend
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: route-b-$i
  namespace: test-status-truncation
spec:
  parentRefs:
  - name: gateway-$i
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /b
    backendRefs:
    - name: backend
      port: 80
EOF

  # Apply in batches of 50 to avoid overwhelming the API server
  if (( i % 50 == 0 )); then
    echo -e "${YELLOW}Waiting for resources to be processed...${NC}"
    sleep 5
  fi
done

echo -e "${GREEN}=== Waiting for gateways to be processed ===${NC}"
sleep 30

echo -e "${GREEN}=== Creating ClientTrafficPolicy with a very long error message ===${NC}"
# Create a ClientTrafficPolicy that will generate a very long error message
cat <<EOF | kubectl apply -f -
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: test-truncation
  namespace: test-status-truncation
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: gateway-1
  http1:
    preserveHeaderCase: true
EOF

echo -e "${GREEN}=== Waiting for ClientTrafficPolicy to be processed ===${NC}"
sleep 10

echo -e "${GREEN}=== Checking ClientTrafficPolicy status ===${NC}"
kubectl get clienttrafficpolicy -n test-status-truncation test-truncation -o yaml

echo -e "${GREEN}=== Test completed ===${NC}"
echo "To clean up, run: make delete-cluster"
