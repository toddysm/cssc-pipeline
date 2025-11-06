# KubeCon NA 2025 Demo Commands - Executed

This document contains all the commands executed during the Azure Container Registry with AKS and ABAC demo.

## 1. Azure Authentication

```bash
az login
```

## 2. Create Resource Group

```bash
az group create --name rg-kubecon-na-2025-demo --location westus2
```

## 3. Create Azure Container Registry (Premium)

```bash
az acr create --name acrkubeconna2025demo --resource-group rg-kubecon-na-2025-demo --location westus2 --sku Premium
```

## 4. Enable ABAC on Registry

```bash
az acr update --name acrkubeconna2025demo --resource-group rg-kubecon-na-2025-demo --role-assignment-mode rbac-abac
```

## 5. Assign Container Registry Repository Catalog Lister Role (No Conditions)

```bash
az role assignment create --assignee memladen@microsoft.com --role "Container Registry Repository Catalog Lister" --scope /subscriptions/98cde175-db82-410f-a5d1-e73410a293cf/resourceGroups/rg-kubecon-na-2025-demo/providers/Microsoft.ContainerRegistry/registries/acrkubeconna2025demo
```

## 6. Assign Container Registry Repository Writer Role with ABAC Condition

```bash
export ASSIGNEE="memladen@microsoft.com"
export ROLE="Container Registry Repository Writer"
export SCOPE="/subscriptions/98cde175-db82-410f-a5d1-e73410a293cf/resourceGroups/rg-kubecon-na-2025-demo/providers/Microsoft.ContainerRegistry/registries/acrkubeconna2025demo"
export CONDITION='( ( !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/content/read'\''}) AND !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/content/write'\''}) AND !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/metadata/read'\''}) AND !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/metadata/write'\''}) ) OR ( @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '\''allowed/'\'' OR @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '\''blocked/'\'' ) )'

az role assignment create --assignee "$ASSIGNEE" --role "$ROLE" --scope "$SCOPE" --condition "$CONDITION" --condition-version "2.0" --output json
```

**Condition Explanation**: Allows read/write access to content and metadata only for repositories starting with `allowed/` or `blocked/`.

## 7. Copy nginx Image to allowed/nginx Repository

```bash
az acr login --name acrkubeconna2025demo

oras copy docker.io/library/nginx:1.25-alpine acrkubeconna2025demo.azurecr.io/allowed/nginx:1.25-alpine
```

## 8. Copy nginx Image to blocked/nginx Repository

```bash
oras copy docker.io/library/nginx:1.25-alpine acrkubeconna2025demo.azurecr.io/blocked/nginx:1.25-alpine
```

## 9. Create AKS Cluster

```bash
az aks create --name aks-kubecon-na-2025-demo --resource-group rg-kubecon-na-2025-demo --location westus2 --node-count 1 --enable-aad --enable-managed-identity --generate-ssh-keys
```

## 10. Get AKS Managed Identity

```bash
export AKS_IDENTITY=$(az aks show --name aks-kubecon-na-2025-demo --resource-group rg-kubecon-na-2025-demo --query identityProfile.kubeletidentity.objectId -o tsv)
echo "AKS Managed Identity: $AKS_IDENTITY"
```

## 11. Assign Container Registry Repository Reader Role to AKS Managed Identity with ABAC Condition

```bash
export ASSIGNEE="$AKS_IDENTITY"
export ROLE="Container Registry Repository Reader"
export SCOPE="/subscriptions/98cde175-db82-410f-a5d1-e73410a293cf/resourceGroups/rg-kubecon-na-2025-demo/providers/Microsoft.ContainerRegistry/registries/acrkubeconna2025demo"
export CONDITION='( ( !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/content/read'\''}) AND !(ActionMatches{'\''Microsoft.ContainerRegistry/registries/repositories/metadata/read'\''}) ) OR ( @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '\''allowed/'\'' ) )'

az role assignment create --assignee "$ASSIGNEE" --role "$ROLE" --scope "$SCOPE" --condition "$CONDITION" --condition-version "2.0" --output json
```

**Condition Explanation**: Allows read access to content and metadata **only** for repositories starting with `allowed/`.

## 12. Assign AKS Cluster Admin Role to User

```bash
az role assignment create --assignee memladen@microsoft.com --role "Azure Kubernetes Service Cluster Admin Role" --scope /subscriptions/98cde175-db82-410f-a5d1-e73410a293cf/resourceGroups/rg-kubecon-na-2025-demo/providers/Microsoft.ContainerService/managedClusters/aks-kubecon-na-2025-demo
```

## 13. Get AKS Credentials

```bash
az aks get-credentials --name aks-kubecon-na-2025-demo --resource-group rg-kubecon-na-2025-demo --admin
```

## 14. Deploy nginx from allowed/nginx Repository (SUCCESS)

```bash
kubectl create deployment nginx-allowed --image=acrkubeconna2025demo.azurecr.io/allowed/nginx:1.25-alpine

# Check deployment status
kubectl get pods -l app=nginx-allowed
kubectl describe pods -l app=nginx-allowed
```

**Result**: ✅ Pod successfully pulled image and started running

## 15. Expose nginx-allowed via LoadBalancer

```bash
kubectl expose deployment nginx-allowed --type=LoadBalancer --port=80 --target-port=80

# Get service details
kubectl get service nginx-allowed

# Open in browser
export NGINX_IP=$(kubectl get service nginx-allowed -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Opening browser to http://$NGINX_IP"
open "http://$NGINX_IP"
```

**Result**: Service exposed at http://4.155.179.247

## 16. Deploy nginx from blocked/nginx Repository (FAILED)

```bash
kubectl create deployment nginx-blocked --image=acrkubeconna2025demo.azurecr.io/blocked/nginx:1.25-alpine

# Check deployment status
kubectl get pods -l app=nginx-blocked
kubectl describe pods -l app=nginx-blocked
```

**Result**: ❌ Pod failed to pull image with error:
```
pull access denied, repository does not exist or may require authorization: 
server message: insufficient_scope: authorization failed
```

## Summary

### Successful Operations
- ✅ Image pull from `allowed/nginx` - ABAC condition permitted access
- ✅ Deployment and service exposure working correctly

### Failed Operations
- ❌ Image pull from `blocked/nginx` - ABAC condition denied access
- Error: `401 Unauthorized - insufficient_scope: authorization failed`

This demonstrates that ABAC policies successfully enforce fine-grained access control at the repository namespace level.
