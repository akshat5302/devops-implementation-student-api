# Network Policy Demonstration

This directory contains network policy files to demonstrate blocking and allowing API-to-DB connections.

## Files

- `block-api-db.yaml` - Contains two network policies:
  1. `block-api-db-connection` - Blocks API pod from connecting to database (for demonstration)
  2. `allow-api-db-connection` - Allows API pod to connect to database (fix)

## Usage

### Step 1: Block API-DB Connection

```bash
# Apply the blocking policy
kubectl apply -f block-api-db.yaml

# Wait for policy to take effect
sleep 5

# Verify API cannot reach database
API_POD=$(kubectl get pods -n student-api -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n student-api $API_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || curl -s http://localhost:3000/api/v1/health'
# Should fail or timeout
```

### Step 2: Allow API-DB Connection

```bash
# Delete the blocking policy
kubectl delete networkpolicy -n student-api block-api-db-connection

# The allow-api-db-connection policy is already in the same file
# If you want to apply it separately, uncomment it in block-api-db.yaml
# Or apply the entire file (it will create both, then delete the blocking one)
```

### Step 3: Clean Up

```bash
# Remove all demo network policies
kubectl delete networkpolicy -n student-api block-api-db-connection allow-api-db-connection
```

## Notes

- Network policies are namespace-scoped
- Default deny-all: If a pod matches a network policy, only traffic explicitly allowed by that policy is permitted
- DNS (UDP port 53) must be allowed for service discovery to work
- The blocking policy only allows DNS, preventing database connections on port 5432
- The allowing policy explicitly permits database connections on port 5432

