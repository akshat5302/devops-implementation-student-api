#!/bin/bash

# Script to rebuild Docker image and redeploy the Student API with test endpoints

set -e

NAMESPACE="${NAMESPACE:-student-api}"
RELEASE_NAME="${RELEASE_NAME:-student-crud-api}"
IMAGE_NAME="${IMAGE_NAME:-akshat5302/student-crud-api}"
CHART_PATH="${CHART_PATH:-charts/crud-api}"

echo "=========================================="
echo "Rebuild and Deploy Student API"
echo "=========================================="
echo ""

# Generate new image tag
TAG=test-alerts
echo "New image tag: $TAG"
echo ""

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo "Error: Dockerfile not found. Please run this script from the project root."
    exit 1
fi

# Build Docker image
echo "1. Building Docker image..."
docker build -t ${IMAGE_NAME}:${TAG} -t ${IMAGE_NAME}:latest .

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

echo "✓ Docker image built successfully"
echo ""

# Check if we should push to registry
read -p "Do you want to push the image to Docker Hub? (yes/no): " push_image
if [ "$push_image" = "yes" ]; then
    echo "2. Pushing Docker image to registry..."
    docker push ${IMAGE_NAME}:${TAG}
    docker push ${IMAGE_NAME}:latest
    echo "✓ Image pushed successfully"
    echo ""
else
    echo "2. Skipping image push (using local image)"
    echo "   Note: For Kubernetes deployment, you'll need to either:"
    echo "   - Push the image to a registry, or"
    echo "   - Load the image into minikube: minikube image load ${IMAGE_NAME}:${TAG}"
    echo ""
    
    # Check if using minikube
    if command -v minikube &> /dev/null; then
        read -p "Load image into minikube? (yes/no): " load_minikube
        if [ "$load_minikube" = "yes" ]; then
            echo "Loading image into minikube..."
            minikube image load ${IMAGE_NAME}:${TAG}
            minikube image load ${IMAGE_NAME}:latest
            echo "✓ Image loaded into minikube"
            echo ""
        fi
    fi
fi

# Update Helm values
echo "3. Updating Helm values with new image tag..."
if command -v yq &> /dev/null; then
    yq e -i ".api.image.repository = \"${IMAGE_NAME}\"" ${CHART_PATH}/values.yaml
    yq e -i ".api.image.tag = \"${TAG}\"" ${CHART_PATH}/values.yaml
    echo "✓ Helm values updated"
elif command -v sed &> /dev/null; then
    # Fallback to sed if yq is not available
    sed -i.bak "s|repository:.*|repository: ${IMAGE_NAME}|" ${CHART_PATH}/values.yaml
    sed -i.bak "s|tag:.*|tag: ${TAG}|" ${CHART_PATH}/values.yaml
    echo "✓ Helm values updated (using sed)"
else
    echo "Warning: Neither yq nor sed found. Please manually update ${CHART_PATH}/values.yaml:"
    echo "  api.image.repository: ${IMAGE_NAME}"
    echo "  api.image.tag: ${TAG}"
fi
echo ""

# Upgrade Helm release
echo "4. Upgrading Helm release..."
if helm list -n ${NAMESPACE} | grep -q ${RELEASE_NAME}; then
    helm upgrade ${RELEASE_NAME} ${CHART_PATH} \
        -n ${NAMESPACE} \
        -f ${CHART_PATH}/values.yaml
    
    if [ $? -eq 0 ]; then
        echo "✓ Helm release upgraded successfully"
        echo ""
        
        # Wait for rollout
        echo "5. Waiting for rollout to complete..."
        kubectl rollout status deployment/${RELEASE_NAME}-api -n ${NAMESPACE} --timeout=300s
        
        if [ $? -eq 0 ]; then
            echo "✓ Deployment rolled out successfully"
            echo ""
            
            # Verify pods are running
            echo "6. Verifying pods..."
            kubectl get pods -n ${NAMESPACE} -l app=${RELEASE_NAME}-api
            
            echo ""
            echo "=========================================="
            echo "Deployment Complete!"
            echo "=========================================="
            echo ""
            echo "Test the new endpoint:"
            echo "  curl http://student-api.atlan.com/api/v1/test/trigger-alerts?alertType=high-error-rate"
            echo ""
        else
            echo "Error: Rollout failed or timed out"
            exit 1
        fi
    else
        echo "Error: Helm upgrade failed"
        exit 1
    fi
else
    echo "Error: Helm release '${RELEASE_NAME}' not found in namespace '${NAMESPACE}'"
    echo "Please install it first:"
    echo "  helm install ${RELEASE_NAME} ${CHART_PATH} -n ${NAMESPACE} -f ${CHART_PATH}/values.yaml"
    exit 1
fi

