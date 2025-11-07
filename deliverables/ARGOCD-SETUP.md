# ArgoCD CI/CD Setup Guide

This guide explains how to set up ArgoCD for automated continuous deployment of the Student API.

## Overview

ArgoCD provides GitOps-based continuous deployment. When you push code changes to the repository:
1. GitHub Actions builds a new Docker image
2. The image tag is updated in `charts/crud-api/values.yaml`
3. ArgoCD detects the Git change
4. ArgoCD automatically syncs and deploys the new version

## Prerequisites

- Kubernetes cluster running
- Helm 3.x installed
- Git repository with push access
- Docker registry credentials configured in GitHub Secrets

## Quick Setup

Run the automated setup script:

```bash
./deliverables/scripts/setup-argocd.sh
```

This will:
- Install ArgoCD in the `argocd` namespace
- Create the Student API application
- Configure automatic syncing

## Manual Setup

### 1. Install ArgoCD

```bash
helm upgrade --install argocd charts/argocd \
  --namespace argocd \
  --create-namespace \
  -f charts/argocd/values.yaml
```

### 2. Wait for ArgoCD to be Ready

```bash
kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/argocd-server \
  -n argocd

kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/argocd-application-controller \
  -n argocd
```

### 3. Get ArgoCD Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 4. Apply ArgoCD Application

```bash
kubectl apply -f charts/argocd/applications/crud-api.yaml
```

## Accessing ArgoCD

### Via Port-Forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Then open: http://localhost:8080
- Username: `admin`
- Password: (from step 3 above)

### Via ArgoCD CLI

```bash
# Install ArgoCD CLI
brew install argocd  # macOS
# or
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login
argocd login localhost:8080 --username admin --password <password>
```

## How It Works

### CI/CD Flow

1. **Developer pushes code** to `sre-implementation` branch
2. **GitHub Actions triggers** (`.github/workflows/cd-pipeline.yaml`)
3. **Docker image is built** with tag: `YYYYMMDD-<commit-sha>`
4. **Image is pushed** to Docker Hub
5. **Helm values updated** with new image tag
6. **Changes committed and pushed** to Git
7. **ArgoCD detects change** in Git repository
8. **ArgoCD syncs automatically** (due to `syncPolicy.automated`)
9. **New pods are deployed** with the new image

### ArgoCD Application Configuration

The application is configured in `charts/argocd/applications/crud-api.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/akshat5302/one2n-sre-bootcamp.git
    targetRevision: sre-implementation  # Watches this branch
    path: charts/crud-api
  syncPolicy:
    automated:
      prune: true      # Remove resources not in Git
      selfHeal: true   # Revert manual changes
```

## Manual Operations

### Sync Application Manually

```bash
# Via CLI
argocd app sync student-crud-api

# Via kubectl
kubectl patch application student-crud-api -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

### Check Application Status

```bash
# Via CLI
argocd app get student-crud-api

# Via kubectl
kubectl get application student-crud-api -n argocd
kubectl describe application student-crud-api -n argocd
```

### View Application Logs

```bash
argocd app logs student-crud-api --tail=100
```

### Rollback to Previous Version

```bash
# List sync history
argocd app history student-crud-api

# Rollback to specific revision
argocd app rollback student-crud-api <revision-id>
```

## Troubleshooting

### Application Not Syncing

1. **Check Git repository access:**
   ```bash
   kubectl logs -n argocd deployment/argocd-repo-server
   ```

2. **Verify application configuration:**
   ```bash
   kubectl get application student-crud-api -n argocd -o yaml
   ```

3. **Check for sync errors:**
   ```bash
   kubectl describe application student-crud-api -n argocd
   ```

### Application Out of Sync

If ArgoCD shows "OutOfSync":

```bash
# Force sync
argocd app sync student-crud-api --force

# Or via UI: Click "Sync" button
```

### Image Pull Errors

If pods fail with image pull errors:

1. **Check image tag in values.yaml:**
   ```bash
   grep "tag:" charts/crud-api/values.yaml
   ```

2. **Verify image exists:**
   ```bash
   docker pull akshat5302/student-crud-api:<tag>
   ```

3. **Check image pull policy:**
   ```bash
   kubectl get deployment student-crud-api-api -n student-api -o yaml | grep imagePullPolicy
   ```

## Best Practices

1. **Always commit image tag changes** - ArgoCD syncs from Git, not from manual kubectl commands
2. **Use semantic versioning** or timestamp-based tags for images
3. **Test in staging** before promoting to production
4. **Monitor ArgoCD sync status** regularly
5. **Use ArgoCD Projects** to organize applications
6. **Enable RBAC** for production environments
7. **Set up notifications** for sync failures

## Advanced Configuration

### Multiple Environments

Create separate applications for different environments:

```yaml
# charts/argocd/applications/crud-api-staging.yaml
spec:
  source:
    targetRevision: staging
  destination:
    namespace: student-api-staging

# charts/argocd/applications/crud-api-prod.yaml
spec:
  source:
    targetRevision: main
  destination:
    namespace: student-api-prod
```

### Image Updater (Optional)

For automatic image updates based on tags:

```yaml
# Install ArgoCD Image Updater
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd
```

## Integration with GitHub Actions

The CI/CD pipeline (`.github/workflows/cd-pipeline.yaml`) automatically:

1. Builds Docker image on code push
2. Updates Helm values with new image tag
3. Commits and pushes changes
4. ArgoCD detects and syncs automatically

No manual intervention needed!

## Security Considerations

1. **Use private Git repositories** with SSH keys or tokens
2. **Enable RBAC** in ArgoCD for access control
3. **Use sealed secrets** or external-secrets-operator for sensitive data
4. **Enable audit logging** for compliance
5. **Restrict ArgoCD server access** via network policies

## Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [GitOps Principles](https://www.gitops.tech/)

