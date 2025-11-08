# Grafana Dashboard for Student API

## Dashboard File

**File:** `dashboard.json`

This dashboard provides comprehensive monitoring for the Student API application including:
- CPU Usage (Cores and Percentage)
- Memory Usage (Bytes and Percentage)
- Pod Restart Count
- Application Logs (via Loki)
- Error Logs
- Log Volume

## Features

### Configurable Namespace
- The dashboard includes a **Namespace** variable that can be selected from a dropdown
- Default namespace: `student-api`
- Automatically filters all metrics and logs by the selected namespace

### Pod Selection
- Multi-select pod variable to filter by specific pods
- "All" option to show all pods in the namespace

### Alert Integration
- Dashboard can be linked from AlertManager alerts
- Link format: `http://localhost:3000/d/student-api-resources-logs?var-namespace={namespace}&var-pod={pod}`
- Alerts automatically include a dashboard link in Slack notifications

## Installation

### Option 1: Upload via Grafana UI

1. Access Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/observability-grafana 3000:80
   ```
   Open: http://localhost:3000

2. Login (default credentials):
   - Username: `admin`
   - Password: Check with: `kubectl get secret -n monitoring observability-grafana -o jsonpath='{.data.admin-password}' | base64 -d`

3. Import Dashboard:
   - Go to **Dashboards** → **Import**
   - Click **Upload JSON file**
   - Select `dashboard.json`
   - Click **Load**
   - Set the **Folder** (optional)
   - Click **Import**

### Option 2: Via ConfigMap (Automatic)

The dashboard is automatically loaded if you use the Helm template approach. However, for manual upload, use Option 1.

## Dashboard Link in Alerts

AlertManager is configured to include dashboard links in Slack notifications. The link format:

```
http://localhost:3000/d/student-api-resources-logs?var-namespace={namespace}&var-pod={pod}
```

**Note:** Replace `localhost:3000` with your actual Grafana URL if accessing remotely.

## Dashboard Variables

1. **namespace**: Dropdown to select namespace (default: `student-api`)
2. **pod**: Multi-select to filter by specific pods (default: All)

## Data Sources Required

1. **Prometheus**: For CPU, Memory, and Pod metrics
   - Automatically configured by kube-prometheus-stack

2. **Loki**: For application logs
   - URL: `http://observability-loki:3100`
   - Configured in Grafana additional datasources

## Accessing the Dashboard

After importing:

1. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/observability-grafana 3000:80
   ```

2. Open Grafana: http://localhost:3000

3. Navigate to: **Dashboards** → **Student API - Resources & Logs**

4. Select namespace and pods from the dropdowns at the top

## Customization

You can customize the dashboard by:
1. Editing the JSON file
2. Re-importing it to Grafana
3. Or editing directly in Grafana UI and exporting the updated JSON

## Troubleshooting

### Dashboard not showing data

1. **Check namespace variable**: Ensure the correct namespace is selected
2. **Verify pod labels**: Pods must have labels matching `student-crud-api-.*`
3. **Check Prometheus metrics**: Verify metrics are being scraped:
   ```bash
   kubectl port-forward -n monitoring svc/observability-kube-prometheus-stack-prometheus 9090:9090
   # Query: container_cpu_usage_seconds_total{namespace="student-api"}
   ```

### Logs not showing

1. **Verify Loki datasource**: Check if Loki datasource is configured in Grafana
2. **Check Promtail**: Ensure Promtail is collecting logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=promtail
   ```
3. **Verify log labels**: Logs must have `namespace` and `app` labels

### Alert links not working

1. **Check Grafana URL**: Ensure the URL in AlertManager config matches your Grafana access URL
2. **Verify dashboard UID**: The dashboard UID is `student-api-resources-logs`
3. **Test link manually**: Copy the link from Slack and test in browser

