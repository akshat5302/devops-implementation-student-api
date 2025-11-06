#!/bin/bash

# Set the profile name
PROFILE_NAME="atlan-sre-task"

# Start Minikube with 4 nodes, each with 2GB RAM, using the specified profile
minikube start --nodes 4 -p $PROFILE_NAME --memory 2048 --cpus 4

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

# Label the nodes
kubectl label nodes $PROFILE_NAME $PROFILE_NAME-m02 type=application
kubectl label nodes $PROFILE_NAME-m03 type=database
kubectl label nodes $PROFILE_NAME-m04 type=dependent_services

# Verify the labels and memory allocation
echo "Verifying node labels and memory allocation:"
kubectl get nodes --show-labels
echo ""
echo "Memory allocation for each node:"
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for node in $nodes
do
    memory_allocatable=$(kubectl get node $node -o jsonpath='{.status.allocatable.memory}')
    memory_allocatable_mi=$((${memory_allocatable%Ki} / 1024))
    echo "Node: $node, Allocatable Memory: ${memory_allocatable_mi}Mi"
done

# Display cluster info
echo ""
echo "Cluster information:"
minikube profile $PROFILE_NAME
kubectl cluster-info

echo "Multi-node Minikube cluster '$PROFILE_NAME' with labels and 2GB RAM per node has been created successfully!"

# Provide instructions for switching to this profile
echo ""
echo "To use this cluster in future commands, run:"
echo "minikube profile $PROFILE_NAME"