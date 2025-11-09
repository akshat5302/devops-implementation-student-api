# SRE Challenge Round - Practical Demo Guide

## Repository Information

**GitHub Repository**: [https://github.com/akshat5302/devops-implementation-student-api](https://github.com/akshat5302/devops-implementation-student-api)  
**Branch**: `sre-implementation`  
**Document Location**: `deliverables/SRE-REPORT.md`

**To get started**:
```bash
git clone https://github.com/akshat5302/devops-implementation-student-api.git
cd devops-implementation-student-api
git checkout sre-implementation
```

---

## Overview

This guide provides a hands-on walkthrough of diagnosing and resolving a simulated production outage in a Kubernetes-based Student API application. Follow along step-by-step to reproduce the issues, diagnose them, and apply fixes.

**Environment**: Kubernetes (Minikube) with Prometheus/Grafana monitoring  
**Application**: Student CRUD API (Frontend + Backend API + PostgreSQL Database)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Setup Environment](#step-1-setup-environment)
3. [Step 2: Deploy Application with Issues](#step-2-deploy-application-with-issues)
4. [Step 3: Observe the Problems](#step-3-observe-the-problems)
5. [Step 4: Diagnose Issues](#step-4-diagnose-issues)
6. [Step 5: Apply Fixes](#step-5-apply-fixes)
7. [Step 6: Verify Fixes](#step-6-verify-fixes)
8. [Step 7: View Monitoring Dashboards](#step-7-view-monitoring-dashboards)
9. [Step 8: Test Alerts](#step-8-test-alerts)
10. [Root Cause Summary](#root-cause-summary)
11. [Configuration Changes](#configuration-changes)

---

## Prerequisites

Before starting, ensure you have:

```bash
# Check required tools
minikube version
kubectl version --client
helm version
```

**Required Tools**:
- Minikube (for local Kubernetes cluster)
- kubectl (Kubernetes CLI)
- Helm 3.8+
- Docker (for building/pulling images)

---

## Step 1: Setup Environment

### 1.1 Clone and Navigate to Project

```bash
# Navigate to project root
cd /path/to/devops-implementation-student-api

# Verify you're in the right directory
ls -la charts/crud-api/
```

### 1.2 Run Setup Script

The project includes an automated setup script that handles all cluster setup, monitoring installation, and application deployment:

```bash
# Navigate to scripts directory
cd deliverables/scripts

# Make script executable (if not already)
chmod +x setup-cluster.sh

# Run the setup script
./setup-cluster.sh
```

**What the script does**:
1. Sets up Minikube cluster (using `minikube.sh`)
2. Creates namespaces (student-api, monitoring, vault)
3. Installs monitoring stack (Prometheus/Grafana)
4. Optionally installs Vault and External Secrets
5. Deploys Student API application
6. Applies Prometheus alert rules

**During setup, you'll be prompted**:
- Whether to recreate existing cluster (if one exists)
- Whether to install Vault (optional - answer 'n' for this demo)
- Whether to install External Secrets (optional - answer 'n' for this demo)
- Whether to deploy with External Secrets (answer 'n' - will use Kubernetes secrets)

**Expected Output** (excerpt):
```
==========================================
SRE Implementation Setup Script
==========================================

Checking prerequisites...
✓ All prerequisites met

Step 1: Setting up Minikube cluster
...
Step 2: Creating namespaces
✓ Namespaces created

Step 3: Installing Monitoring Stack
...
Step 6: Deploying Student API
...
✓ Student API deployment initiated (without External Secrets)

Step 8: Applying Prometheus Alert Rules
✓ Alert rules applied

Setup Complete!
```

### 1.3 Wait for Pods to be Ready

After the setup script completes, wait for all pods to be ready:

```bash
# Check monitoring stack pods
kubectl get pods -n monitoring

# Check application pods
kubectl get pods -n student-api

# Wait for all pods to be ready (optional)
kubectl wait --for=condition=ready pod --all -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod --all -n student-api --timeout=300s
```

**Expected Output** (after a few minutes):
```
# Monitoring namespace
NAME                                                     READY   STATUS    RESTARTS   AGE
observability-grafana-xxx                                1/1     Running   0          2m
observability-kube-prometheus-stack-prometheus-xxx       2/2     Running   0          2m
...

# Student API namespace
NAME                                    READY   STATUS    RESTARTS   AGE
student-crud-api-api-xxx                1/1     Running   0          1m
student-crud-api-api-db-0               1/1     Running   0          1m
student-crud-api-frontend-xxx           1/1     Running   0          1m
```

---

## Step 2: Deploy Application with Issues

### 2.1 Verify Initial Deployment

The setup script already deployed the application. Verify it's running:

```bash
# Check pod status
kubectl get pods -n student-api
```

**Expected Output** (Initial - should be healthy):
```
NAME                                    READY   STATUS    RESTARTS   AGE
student-crud-api-api-xxx                1/1     Running   0          2m
student-crud-api-api-db-0               1/1     Running   0          2m
student-crud-api-frontend-xxx           1/1     Running   0          2m
```

### 2.2 Trigger CrashLoopBackOff Scenario

Use the provided script to simulate the frontend failure:

```bash
# Navigate to scripts directory
cd deliverables/scripts

# Make script executable
chmod +x test-frontend-failure.sh

# Enable faulty configuration (triggers CrashLoopBackOff)
./test-frontend-failure.sh enable
```

**What this does**:
- Sets incorrect API URL: `http://wrong-backend-url:3000/api/v1`
- Enables `checkApiConnectivity: true`
- Enables `failOnApiUnreachable: true` (causes container to exit)

### 2.3 Observe the Failure

```bash
# Watch pod status
kubectl get pods -n student-api -w
```

**Expected Output** (After a few seconds):
```
NAME                                    READY   STATUS             RESTARTS   AGE
student-crud-api-frontend-xxx           0/1     CrashLoopBackOff   3          2m
```

**Press Ctrl+C to stop watching**

---

## Step 3: Observe the Problems

### 3.1 Check Pod Status

```bash
# Get all pods in student-api namespace
kubectl get pods -n student-api
```

**Observe**:
- Frontend pod in `CrashLoopBackOff` state
- High restart count
- Pod not ready (0/1)

### 3.2 Check Service Endpoints

```bash
# Check if services have endpoints
kubectl get svc,endpoints -n student-api
```

**Observe**:
- Frontend service may have no endpoints (if pod keeps crashing)
- API service should have endpoints

### 3.3 Check Resource Usage

```bash
# Check resource usage (requires metrics-server)
kubectl top pods -n student-api
```

**Note**: If metrics-server is not installed, this command will fail. You can install it or skip this step.

---

## Step 4: Diagnose Issues

### 4.1 Check Pod Logs

```bash
# Get frontend pod name
FRONTEND_POD=$(kubectl get pods -n student-api -l app=student-crud-api-frontend -o jsonpath='{.items[0].metadata.name}')

# View current logs
kubectl logs -n student-api $FRONTEND_POD

# View previous container logs (if crashed)
kubectl logs -n student-api $FRONTEND_POD --previous
```

**Expected Log Output**:
```
Checking API connectivity to http://wrong-backend-url:3000/api/v1...
Attempt 1/3: Checking wrong-backend-url:3000...
❌ API check failed (attempt 1/3), retrying in 2s...
❌ API is NOT reachable at http://wrong-backend-url:3000/api/v1 after 3 attempts
🚨 FAIL_ON_API_UNREACHABLE is true - exiting container
```

**Root Cause Identified**: Frontend configured with wrong API URL and exits on connection failure.

### 4.2 Check Pod Events

```bash
# Describe the failing pod
kubectl describe pod -n student-api $FRONTEND_POD
```

**Look for Events section**:
```
Events:
  Type     Reason          Age                From               Message
  ----     ------          ----               ----               -------
  Warning  Failed          30s (x3 over 2m)    kubelet            Error: container exited with code 1
  Warning  BackOff         15s (x2 over 1m)   kubelet            Back-off restarting failed container
```

### 4.3 Check Service Configuration

```bash
# Check frontend service
kubectl describe service -n student-api student-crud-api-frontend
```

**Observe**:
- Service selector: `app=student-crud-api-frontend`
- Endpoints: May be empty or showing pod IP

### 4.4 Check ConfigMap

```bash
# View frontend ConfigMap (after enabling faulty config)
kubectl get configmap -n student-api student-crud-api-frontend-config -o yaml
```

**Observe** (after running `test-frontend-failure.sh enable`):
- `API_BASE_URL: "http://wrong-backend-url:3000/api/v1"` (incorrect)
- `FAIL_ON_API_UNREACHABLE: "true"` (causes exit)

**Observe** (before running failure script - correct configuration):
- `API_BASE_URL: "http://student-crud-api-api:3000/api/v1"` (uses Kubernetes service DNS)
- `FAIL_ON_API_UNREACHABLE: "false"`

**Note**: The frontend uses Kubernetes service DNS (`student-crud-api-api:3000`) instead of external domains.

### 4.5 Test DNS Resolution

```bash
# Test DNS from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -n student-api -- nslookup student-crud-api-api
```

**Expected Output** (for correct service):
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      student-crud-api-api
Address 1: 10.244.1.5 student-crud-api-api.student-api.svc.cluster.local
```

**Note**: The frontend is trying to reach `wrong-backend-url` which doesn't exist, so DNS will fail for that.

### 4.6 Check Resource Limits

```bash
# Check pod resource configuration
kubectl get pod -n student-api $FRONTEND_POD -o jsonpath='{.spec.containers[0].resources}' | jq
```

**Observe**:
- Memory limits: `128Mi`
- CPU limits: `100m`

### 4.7 Check Node Conditions

```bash
# Check node resource pressure
kubectl describe node minikube | grep -A 10 Conditions
```

**Look for**:
- `MemoryPressure: True/False`
- `DiskPressure: True/False`

---

## Step 5: Apply Fixes

### 5.1 Fix Frontend Configuration

Use the provided script to fix the configuration:

```bash
# Disable faulty configuration (fixes the issue)
cd deliverables/scripts
./test-frontend-failure.sh disable
```

**What this does**:
- Removes incorrect API URL (sets to empty, which uses Kubernetes service DNS: `student-crud-api-api:3000`)
- Sets `checkApiConnectivity: false`
- Sets `failOnApiUnreachable: false`

**OR manually edit values.yaml**:

```bash
# Edit values file
vim charts/crud-api/values.yaml

# Change these values:
frontend:
  apiUrl: ""  # Empty = use Kubernetes service DNS (student-crud-api-api:3000)
  checkApiConnectivity: false
  failOnApiUnreachable: false

# Upgrade the release
helm upgrade student-crud-api ./charts/crud-api -n student-api --wait
```

### 5.2 Verify Configuration Change

```bash
# Check ConfigMap was updated
kubectl get configmap -n student-api student-crud-api-frontend-config -o yaml | grep -A 2 API_BASE_URL
```

**Expected** (after fix):
```yaml
API_BASE_URL: http://student-crud-api-api:3000/api/v1
```

**Note**: The frontend uses Kubernetes service DNS (`student-crud-api-api.student-api.svc.cluster.local:3000` or short form `student-crud-api-api:3000`) for internal communication.

### 5.3 Wait for Pod Recovery

```bash
# Watch pods recover
kubectl get pods -n student-api -w
```

**Expected Output** (after ~30 seconds):
```
NAME                                    READY   STATUS    RESTARTS   AGE
student-crud-api-frontend-xxx           1/1     Running   0          1m
```

**Press Ctrl+C to stop watching**

---

## Step 6: Verify Fixes

### 6.1 Verify Pod Status

```bash
# Check all pods are running
kubectl get pods -n student-api
```

**Expected Output** (after fixes):
```
NAME                                    READY   STATUS    RESTARTS   AGE
student-crud-api-api-xxx                1/1     Running   0          10m
student-crud-api-api-db-0               1/1     Running   0          10m
student-crud-api-frontend-xxx           1/1     Running   0          2m
```

**✅ All pods should be in `Running` state with `1/1` ready**

**If pods are still not ready, check**:
```bash
# Check pod events
kubectl describe pod -n student-api <pod-name>

# Check if pods are being recreated
kubectl get pods -n student-api -w
```

### 6.2 Verify Service Endpoints

```bash
# Check service endpoints
kubectl get svc,endpoints -n student-api
```

**Expected Output**:
```
NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/student-crud-api-api   ClusterIP   10.96.xxx.xxx   <none>        3000/TCP   10m
service/student-crud-api-frontend ClusterIP 10.96.xxx.xxx  <none>        8080/TCP   10m

NAME                           ENDPOINTS                    AGE
endpoints/student-crud-api-api  10.244.x.x:3000            10m
endpoints/student-crud-api-frontend 10.244.x.x:8080        10m
```

**✅ All services should have active endpoints (IP addresses shown)**

**If endpoints are empty**:
```bash
# Check if pods are ready
kubectl get pods -n student-api

# Check service selector matches pod labels
kubectl describe service -n student-api student-crud-api-frontend
kubectl get pods -n student-api --show-labels
```

### 6.3 Test API Health Endpoint

```bash
# Get API pod name
API_POD=$(kubectl get pods -n student-api -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}')

# Verify pod exists
if [ -z "$API_POD" ]; then
  echo "Error: API pod not found. Check with: kubectl get pods -n student-api"
  exit 1
fi

echo "Testing health endpoint on pod: $API_POD"

# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api $API_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

# Test health endpoint (try wget first, fallback to curl)
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || curl -s http://localhost:3000/api/v1/health'
```

**Expected Output**:
```json
{"status":"healthy","timestamp":"2024-01-XX","uptime":600}
```

**✅ Health endpoint should return healthy status**

### 6.4 Test Frontend to Backend Connectivity

```bash
# Get frontend pod name
FRONTEND_POD=$(kubectl get pods -n student-api -l app=student-crud-api-frontend -o jsonpath='{.items[0].metadata.name}')

# Verify pod name is set
if [ -z "$FRONTEND_POD" ]; then
  echo "Error: Frontend pod not found. Check with: kubectl get pods -n student-api"
  exit 1
fi

echo "Testing connectivity from frontend pod: $FRONTEND_POD"

# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api $FRONTEND_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

# Test connectivity from frontend to backend (try wget first, fallback to curl)
kubectl exec -n student-api $FRONTEND_POD -- sh -c 'wget -qO- http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health 2>/dev/null || curl -s http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health'
```

**Expected Output**:
```json
{"status":"healthy","timestamp":"2024-01-XX","uptime":600}
```

**✅ Frontend can successfully reach backend via Kubernetes DNS**

**If DNS resolution fails**:
```bash
# Test DNS from within pod
kubectl exec -n student-api $FRONTEND_POD -- nslookup student-crud-api-api.student-api.svc.cluster.local

# Or use busybox for DNS test
kubectl run -it --rm debug --image=busybox --restart=Never -n student-api -- nslookup student-crud-api-api
```

### 6.5 Test API Functionality

```bash
# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api $API_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

# Test GET students endpoint (try wget first, fallback to curl)
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/students 2>/dev/null || curl -s http://localhost:3000/api/v1/students'
```

**Expected Output**:
```json
[]
```

**✅ API endpoint responding correctly (empty array is expected for new database)**

**Test creating a student**:
```bash
# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api $API_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

# Create a student (POST request)
kubectl exec -n student-api $API_POD -- sh -c 'curl -s -X POST http://localhost:3000/api/v1/students -H "Content-Type: application/json" -d "{\"name\":\"Test Student\",\"email\":\"test@example.com\",\"age\":20}"'

# Get all students
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/students 2>/dev/null || curl -s http://localhost:3000/api/v1/students'
```

### 6.6 Test Resource Usage

```bash
# Check resource usage (requires metrics-server)
kubectl top pods -n student-api
```

**Expected Output** (if metrics-server is installed):
```
NAME                            CPU(cores)   MEMORY(bytes)
student-crud-api-frontend-xxx   8m           45Mi/128Mi
student-crud-api-api-xxx        50m          180Mi/512Mi
student-crud-api-api-db-0       20m          120Mi/512Mi
```

**✅ All pods operating within resource limits**

**If metrics-server is not installed**:
```bash
# Install metrics-server in Minikube
minikube addons enable metrics-server

# Wait a moment, then try again
sleep 10
kubectl top pods -n student-api
```

**Alternative: Check resource limits in pod spec**:
```bash
# Check resource limits configured
kubectl get pod -n student-api $FRONTEND_POD -o jsonpath='{.spec.containers[0].resources}' | jq
```

### 6.7 Verify DNS Resolution

```bash
# Test DNS resolution from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -n student-api -- nslookup student-crud-api-api
```

**Expected Output**:
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      student-crud-api-api
Address 1: 10.244.x.x student-crud-api-api.student-api.svc.cluster.local
```

**✅ DNS resolution working correctly**

**If DNS fails**:
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

### 6.8 Test End-to-End (via Port-Forward)

```bash
# Port-forward to API service (run in background)
kubectl port-forward svc/student-crud-api-api 3000:3000 -n student-api &
PORT_FORWARD_PID=$!

# Wait a moment for port-forward to establish
sleep 2

# Test health endpoint
curl http://localhost:3000/api/v1/health

# Create a student
curl -X POST http://localhost:3000/api/v1/students \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com","age":25}'

# Get students
curl http://localhost:3000/api/v1/students

# Stop port-forward when done
kill $PORT_FORWARD_PID 2>/dev/null || true
```

**Expected Output**:
```json
# Health check
{"status":"healthy","timestamp":"2024-01-XX","uptime":600}

# Create student
{"id":1,"name":"John Doe","email":"john@example.com","age":25,...}

# Get students
[{"id":1,"name":"John Doe","email":"john@example.com","age":25,...}]
```

**✅ Full CRUD operations working end-to-end**

**Note**: 
- Using `kubectl port-forward` (as shown above) is the recommended approach for this demo
- If you have a domain name configured, you can use Ingress instead by:
  1. Setting `ingress.enabled: true` in `charts/crud-api/values.yaml`
  2. Configuring `ingress.appHost` and `ingress.api` with your domain names
  3. Using `minikube tunnel` or an ingress controller to expose services
- All access uses `localhost` - no /etc/hosts modifications needed

---

## Step 7: View Monitoring Dashboards

### 7.1 Access Grafana

```bash
# Port-forward Grafana service (run in background)
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring &
GRAFANA_PID=$!

# Wait a moment
sleep 2

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring observability-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "prom-operator")
echo "Grafana password: $GRAFANA_PASSWORD"
```

**Access Grafana**: Open browser to http://localhost:3000

**Default Credentials**:
- Username: `admin`
- Password: Check the output above or run:
  ```bash
  kubectl get secret -n monitoring observability-grafana -o jsonpath='{.data.admin-password}' | base64 -d
  echo
  ```

**Note**: Keep the port-forward running. To stop it later: `kill $GRAFANA_PID`

### 7.2 Import Dashboard

1. Navigate to **Dashboards** → **Import**
2. Upload the dashboard JSON file:
   ```bash
   # Copy dashboard JSON
   cat deliverables/grafana-dashboards/dashboard.json
   ```
3. Paste the JSON content or upload the file
4. Select **Prometheus** as data source
5. Click **Import**

### 7.3 View Dashboard Panels

**Dashboard includes**:
- **CPU Usage**: Real-time CPU usage per pod
- **Memory Usage**: Memory usage in bytes and percentage
- **Pod Restart Count**: Number of pod restarts over time
- **Container Status**: Current status of containers

**Dashboard Panels to Review**:
- Memory usage graphs (before/after fixes)
- Pod restart count (should show 0 after fixes)
- CPU usage trends
- All pods in healthy state

### 7.4 View Prometheus Metrics

```bash
# Port-forward Prometheus (run in background, or use separate terminal)
kubectl port-forward svc/observability-kube-prometheus-stack-prometheus 9090:9090 -n monitoring &
PROMETHEUS_PID=$!

# Wait a moment
sleep 2
```

**Access Prometheus**: Open browser to http://localhost:9090

**Note**: Keep the port-forward running. To stop it later: `kill $PROMETHEUS_PID`

**Test Queries**:
```promql
# Pod memory usage
container_memory_working_set_bytes{pod=~"student-crud-api-.*"}

# Pod restart count
kube_pod_container_status_restarts_total{pod=~"student-crud-api-.*"}

# Pod status
kube_pod_status_phase{pod=~"student-crud-api-.*"}
```

---

## Step 8: Test Alerts

### 8.1 Apply Alert Rules

```bash
# Apply Prometheus alert rules
kubectl apply -f deliverables/prometheus-alerts/student-api-alerts.yaml -n monitoring

# Verify alerts are loaded
kubectl get prometheusrule -n monitoring
```

**Expected Output**:
```
NAME                AGE
student-api-alerts  10s
```

### 8.2 View Alerts in Prometheus

```bash
# Access Prometheus (if not already port-forwarded)
# If you already have port-forward running, skip this
kubectl port-forward svc/observability-kube-prometheus-stack-prometheus 9090:9090 -n monitoring &
```

1. Open browser to http://localhost:9090
2. Navigate to **Alerts** tab in Prometheus UI
3. Look for alerts with `app=student-api` label
4. Verify alert rules are loaded

**Verify alerts are loaded**:
```bash
# Check PrometheusRule resource
kubectl get prometheusrule -n monitoring student-api-alerts -o yaml

# Check if Prometheus has loaded the rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="student-api-alerts")'
```

### 8.3 Trigger Test Alert (Optional)

Use the test script to trigger a CrashLoopBackOff alert:

```bash
# Enable faulty config again
cd deliverables/scripts
./test-frontend-failure.sh enable

# Wait for alert to trigger (check Prometheus UI)
# Then fix it
./test-frontend-failure.sh disable
```

### 8.4 View Alertmanager (Optional)

```bash
# Port-forward Alertmanager (run in background)
kubectl port-forward svc/observability-kube-prometheus-stack-alertmanager 9093:9093 -n monitoring &
ALERTMANAGER_PID=$!

# Wait a moment
sleep 2
```

**Access Alertmanager**: Open browser to http://localhost:9093

**Note**: Keep the port-forward running. To stop it later: `kill $ALERTMANAGER_PID`

**Check Alertmanager status**:
```bash
# Verify Alertmanager is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager

# Check Alertmanager logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=20
```

**Alertmanager UI to Review**:
- Active alerts (if any)
- Alert groups
- Alert routing configuration

### 8.5 Alert Rules Overview

**Configured Alerts** (in `deliverables/prometheus-alerts/student-api-alerts.yaml`):

1. **PodCrashLoopBackOff** - Triggers when pod enters CrashLoopBackOff
2. **HighPodMemoryUsage** - Triggers when memory > 85%
3. **HighPodCPUUsage** - Triggers when CPU > 80%
4. **HighPodRestartCount** - Triggers when restarts > 5 in 1 hour
5. **ServiceEndpointsDown** - Triggers when service has no endpoints
6. **HighHTTPErrorRate** - Triggers when error rate > 0.1 errors/sec
7. **HighP90Latency** - Triggers when p90 latency > 1s
8. **HighP95Latency** - Triggers when p95 latency > 2s
9. **HighP99Latency** - Triggers when p99 latency > 5s
10. **DatabaseErrors** - Triggers when DB error rate > 0.05 errors/sec

---

## Root Cause Summary

### Issue 1: Pod CrashLoopBackOff ✅ FIXED

**Root Cause**: 
- Frontend container configured with incorrect API URL (`http://wrong-backend-url:3000/api/v1`)
- `failOnApiUnreachable: true` caused container to exit when API was unreachable
- Container kept restarting in a loop

**Evidence**:
- Pod logs showed: `API is NOT reachable at http://wrong-backend-url:3000/api/v1`
- Container exit code: 1
- Pod events showed: `Error: container exited with code 1`

**Fix Applied**:
- Set `apiUrl: ""` (empty, uses Kubernetes service DNS: `student-crud-api-api:3000`)
- Set `checkApiConnectivity: false`
- Set `failOnApiUnreachable: false`

**Verification**:
```bash
kubectl get pods -n student-api
# ✅ All pods Running, no CrashLoopBackOff
```

---

### Issue 2: Service Discovery/DNS Issues ✅ FIXED

**Root Cause**:
- Frontend was configured to use non-existent hostname (`wrong-backend-url`)
- Should use Kubernetes service DNS name: `student-crud-api-api.student-api.svc.cluster.local` or short form `student-crud-api-api:3000`

**Evidence**:
- ConfigMap showed incorrect `API_BASE_URL`
- DNS resolution failed for `wrong-backend-url`
- Service `student-crud-api-api` had valid endpoints

**Fix Applied**:
- Removed incorrect API URL
- Frontend now uses correct Kubernetes service DNS (`student-crud-api-api:3000`)

**Verification**:
```bash
# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api $FRONTEND_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

kubectl exec -n student-api $FRONTEND_POD -- sh -c 'wget -qO- http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health 2>/dev/null || curl -s http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health'
# ✅ Returns healthy status
```

---

### Issue 3: Out of Memory (OOM) Situation ✅ DEMONSTRATED & FIXED

**Root Cause**:
- Pods can exceed memory limits, causing OOMKilled status
- Memory limits are set but can be exceeded under load or memory leaks

**Demonstration - Trigger OOM**:

1. **Check current memory limits**:
```bash
# Check API pod memory limits
API_POD=$(kubectl get pods -n student-api -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}')
kubectl get pod -n student-api $API_POD -o jsonpath='{.spec.containers[0].resources}' | jq
# Should show: memory limit: 512Mi
```

2. **Trigger OOM using test endpoint**:
```bash
# Port-forward to API service
kubectl port-forward svc/student-crud-api-api 3000:3000 -n student-api &
PORT_FORWARD_PID=$!

# Wait a moment
sleep 2

# Trigger OOM by allocating memory beyond the limit
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=oom"

# Stop port-forward
kill $PORT_FORWARD_PID 2>/dev/null || true
```

3. **Observe OOMKilled status**:
```bash
# Watch pod status
kubectl get pods -n student-api -w
```

**Expected Output** (after OOM trigger):
```
NAME                                    READY   STATUS      RESTARTS   AGE
student-crud-api-api-xxx                0/1     OOMKilled   1          5m
```

4. **Check pod events**:
```bash
kubectl describe pod -n student-api $API_POD | grep -A 10 Events
```

**Expected Events**:
```
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Warning  OOMKilled  30s (x1 over 1m)   kubelet            Container killed due to memory limit
```

5. **Check pod logs** (if available before OOM):
```bash
kubectl logs -n student-api $API_POD --previous
```

**Fix Applied**:
- Increase memory limits in `charts/crud-api/values.yaml`:
```yaml
api:
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "1024Mi"  # Increased from 512Mi to 1024Mi
      cpu: "500m"
```

- Apply the fix:
```bash
# Edit values.yaml to increase memory limit
vim charts/crud-api/values.yaml

# Upgrade the release
helm upgrade student-crud-api ./charts/crud-api -n student-api --wait
```

**Verification**:
```bash
# Check new memory limits
kubectl get pod -n student-api $API_POD -o jsonpath='{.spec.containers[0].resources}' | jq

# Check pod status (should be Running)
kubectl get pods -n student-api
# ✅ Pod should be Running, not OOMKilled

# Monitor memory usage
kubectl top pods -n student-api
# ✅ Pod operating within new limits
```

---

### Issue 4: Network Policy Blocking API and DB Connection ✅ DEMONSTRATED

**Root Cause**:
- Network policies can block pod-to-pod communication if not configured correctly
- Default deny-all policy blocks all traffic unless explicitly allowed

**Demonstration - Block API and DB Connection**:

1. **Verify current connectivity** (before network policy):
```bash
# Get API pod name
API_POD=$(kubectl get pods -n student-api -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}')

# Install wget and curl if not available
kubectl exec -n student-api $API_POD -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

# Test API can reach database (should work)
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || curl -s http://localhost:3000/api/v1/health'
# ✅ Should return healthy status
```

2. **Apply blocking network policy**:
```bash
# Apply the blocking network policy from the demo file
kubectl apply -f deliverables/network-policy-demo/block-api-db.yaml

# Or create it manually:
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-api-db-connection
  namespace: student-api
spec:
  podSelector:
    matchLabels:
      app: student-crud-api-api
  policyTypes:
  - Egress
  egress:
  # Only allow DNS, but NOT database connection
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Explicitly deny database connection (no rule for port 5432)
EOF
```

3. **Observe connection failure**:
```bash
# Wait a moment for policy to take effect
sleep 5

# Test API health endpoint (should fail or timeout)
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || curl -s http://localhost:3000/api/v1/health'
# ❌ Should fail or timeout (API cannot reach database)

# Check pod logs for connection errors
kubectl logs -n student-api $API_POD --tail=20
# Should show database connection errors
```

4. **Check network policy**:
```bash
kubectl get networkpolicies -n student-api
kubectl describe networkpolicy -n student-api block-api-db-connection
```

**Fix Applied**:
- Remove the blocking network policy or apply the allowing policy:
```bash
# Option 1: Delete the blocking policy
kubectl delete networkpolicy -n student-api block-api-db-connection

# Option 2: Apply the allowing policy from the demo file
# The allow-api-db-connection policy is in deliverables/network-policy-demo/block-api-db.yaml
# First delete the blocking one, then apply the allowing one:
kubectl delete networkpolicy -n student-api block-api-db-connection
kubectl apply -f deliverables/network-policy-demo/block-api-db.yaml
# This will create the allow-api-db-connection policy

# Or create it manually:
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-db-connection
  namespace: student-api
spec:
  podSelector:
    matchLabels:
      app: student-crud-api-api
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Allow database connection
  - to:
    - podSelector:
        matchLabels:
          app.name: student-api-student-crud-api-api-db
    ports:
    - protocol: TCP
      port: 5432
EOF
```

**Verification**:
```bash
# Wait for policy to take effect
sleep 5

# Test API health endpoint (should work now)
kubectl exec -n student-api $API_POD -- sh -c 'wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || curl -s http://localhost:3000/api/v1/health'
# ✅ Should return healthy status

# Check network policies
kubectl get networkpolicies -n student-api
# ✅ Policy should allow DB connection
```

**Note**: The existing network policy template in `charts/crud-api/templates/network-policy.yaml` is properly configured to allow API-to-DB connections when enabled. This demonstration shows what happens when network policies are misconfigured.

---

## Configuration Changes

### Summary of Changes

#### Before (Faulty Configuration)

**File**: `charts/crud-api/values.yaml`

```yaml
frontend:
  apiUrl: "http://wrong-backend-url:3000/api/v1"  # ❌ Wrong URL
  checkApiConnectivity: true                       # ❌ Enabled
  failOnApiUnreachable: true                      # ❌ Causes CrashLoopBackOff
```

#### After (Fixed Configuration)

**File**: `charts/crud-api/values.yaml`

```yaml
frontend:
  apiUrl: ""                    # ✅ Empty = use Kubernetes service DNS (student-crud-api-api:3000)
  checkApiConnectivity: false   # ✅ Disabled
  failOnApiUnreachable: false  # ✅ Prevents CrashLoopBackOff
```

### Files Modified

1. **`charts/crud-api/values.yaml`**
   - Fixed frontend API URL configuration
   - Disabled connectivity checks that cause crashes

2. **`charts/crud-api/templates/frontend-deployment.yaml`**
   - Uses ConfigMap for API URL configuration
   - Resources configured (requests and limits)

3. **`charts/crud-api/templates/api-deployment.yaml`**
   - Health probes configured (liveness and readiness)
   - Resources configured (requests and limits)

4. **`charts/crud-api/templates/api-db-statefulset.yaml`**
   - Health probes configured (liveness and readiness)
   - Resources configured (requests and limits)

### Files Created

1. **`deliverables/prometheus-alerts/student-api-alerts.yaml`**
   - Prometheus alert rules for all identified issues

2. **`deliverables/grafana-dashboards/dashboard.json`**
   - Grafana dashboard for monitoring

3. **`deliverables/scripts/test-frontend-failure.sh`**
   - Script to reproduce and fix CrashLoopBackOff scenario

---

## Quick Reference Commands

### Check Pod Status
```bash
kubectl get pods -n student-api
kubectl get pods -n student-api -w  # Watch mode
```

### Check Service Endpoints
```bash
kubectl get svc,endpoints -n student-api
```

### View Pod Logs
```bash
kubectl logs -n student-api <pod-name>
kubectl logs -n student-api <pod-name> --previous  # Previous container
```

### Describe Pod
```bash
kubectl describe pod -n student-api <pod-name>
```

### Check Resource Usage
```bash
kubectl top pods -n student-api
kubectl top nodes
```

### Test DNS Resolution
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -n student-api -- nslookup student-crud-api-api
```

### Test Connectivity
```bash
# From frontend pod to API
# Install wget and curl if not available (Alpine-based images)
kubectl exec -n student-api <frontend-pod> -- sh -c 'apk add --no-cache wget curl 2>/dev/null || true'

kubectl exec -n student-api <frontend-pod> -- sh -c 'wget -qO- http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health 2>/dev/null || curl -s http://student-crud-api-api.student-api.svc.cluster.local:3000/api/v1/health'
```

### Access Services

**Using kubectl port-forward** (recommended for service access):

```bash
# Grafana
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring

# Prometheus
kubectl port-forward svc/observability-kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# API
kubectl port-forward svc/student-crud-api-api 3000:3000 -n student-api

# Frontend
kubectl port-forward svc/student-crud-api-frontend 8080:8080 -n student-api
```

**Note**: 
- **Recommended**: Use `kubectl port-forward` for direct service access (Grafana, Prometheus, API, Frontend)
- **Alternative**: If you have a domain name configured, you can use Ingress by setting `ingress.enabled: true` in `charts/crud-api/values.yaml` and configuring `ingress.appHost` and `ingress.api` with your domain names
- All access uses `localhost` - **no /etc/hosts modifications or root privileges needed**
- For this demo, `kubectl port-forward` is sufficient for all testing

### Test Failure Scenario
```bash
cd deliverables/scripts
./test-frontend-failure.sh enable   # Trigger CrashLoopBackOff
./test-frontend-failure.sh disable  # Fix the issue
./test-frontend-failure.sh status   # Check current state
```

---

## Monitoring Dashboards and Alerts

### Grafana Dashboards

Review the following in Grafana:
- Memory usage graphs (before/after)
- Pod restart count (should be 0 after fixes)
- CPU usage trends
- All pods in healthy state

### Prometheus Alerts

Review the following in Prometheus/Alertmanager:
- Alert rules loaded
- Active alerts (if any)
- Alert history

---

## Troubleshooting

### Pod Still in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n student-api <pod-name> --previous

# Check ConfigMap
kubectl get configmap -n student-api student-crud-api-frontend-config -o yaml

# Restart deployment
kubectl rollout restart deployment/student-crud-api-frontend -n student-api
```

### Service Has No Endpoints

```bash
# Check service selector
kubectl describe service -n student-api student-crud-api-frontend

# Check pod labels
kubectl get pods -n student-api --show-labels

# Verify labels match
```

### DNS Resolution Failing

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system <coredns-pod>
```

### Cannot Access Grafana

```bash
# Check Grafana pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Get Grafana password
kubectl get secret -n monitoring observability-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Conclusion

This guide demonstrated:

1. ✅ **Reproducing the Issue**: Using `test-frontend-failure.sh` to trigger CrashLoopBackOff
2. ✅ **Diagnosing the Problem**: Using kubectl commands to identify root causes
3. ✅ **Applying Fixes**: Correcting configuration to resolve issues
4. ✅ **Verifying Solutions**: Comprehensive verification steps
5. ✅ **Monitoring Setup**: Grafana dashboards and Prometheus alerts
6. ✅ **Testing Alerts**: Alert rules for proactive monitoring

**All issues have been identified, diagnosed, and resolved.**

The application is now healthy with:
- All pods running and ready
- Services with active endpoints
- DNS resolution working
- Resource usage within limits
- Monitoring and alerting configured

---

