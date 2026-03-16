# ACR-to-ACR Cache Rule with Managed Identity Authentication

This guide walks through deploying an Azure Container Registry (ACR) cache rule that uses a User-Assigned Managed Identity (UAMI) to authenticate against an upstream (source) ACR registry.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and up to date
- Contributor or Owner permissions on the Azure subscription
- Two Azure Container Registries: a **source** (upstream) registry and a **target** (downstream) registry

---

## Step 1 — Set Environment Variables

Set these variables in your shell. They are referenced throughout the subsequent steps.

```bash
export SUBSCRIPTION="<your-subscription-id>"
export RESOURCE_GROUP="<your-resource-group>"
export SOURCE_REGISTRY="<source-registry-name>.azurecr.io"
export TARGET_REGISTRY="<target-registry-name>"
export SOURCE_REPO="<source-registry-name>.azurecr.io/hello-world"
export TARGET_REPO="hello-world"
export UAMI_NAME="<managed-identity-name>"
export CACHE_RULE_NAME="cacherule-acr-to-acr-mi"
```

---

## Step 2 — Log in to Azure

Authenticate with Azure CLI and set the active subscription context.

```bash
az login
az account set --subscription $SUBSCRIPTION
```

Verify the correct subscription is active:

```bash
az account show --query "{name:name, id:id}" --output table
```

---

## Step 3 — Register the Feature Flag

The cache rule managed identity authentication capability is in preview and must be explicitly registered on the subscription before use.

```bash
az feature register \
    --namespace Microsoft.ContainerRegistry \
    --name ArtifactCacheManagedIdentityAuthentication \
    --subscription $SUBSCRIPTION
```

Wait for the registration to complete (this can take a few minutes). Check the status with:

```bash
az feature show \
    --namespace Microsoft.ContainerRegistry \
    --name ArtifactCacheManagedIdentityAuthentication \
    --subscription $SUBSCRIPTION \
    --query "properties.state" \
    --output tsv
```

Proceed only when the output shows `Registered`.

After the feature is registered, propagate it to the resource provider:

```bash
az provider register \
    --namespace Microsoft.ContainerRegistry \
    --subscription $SUBSCRIPTION
```

---

## Step 4 — Create a User-Assigned Managed Identity

```bash
az identity create \
    --name $UAMI_NAME \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION
```

Capture the resource ID and principal ID for later steps:

```bash
export UAMI_RESOURCE_ID=$(az identity show \
    --name $UAMI_NAME \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --query "id" \
    --output tsv)

export UAMI_PRINCIPAL_ID=$(az identity show \
    --name $UAMI_NAME \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --query "principalId" \
    --output tsv)
```

---

## Step 5 — Grant the Identity Read Access on the Source Registry

The managed identity needs two roles on the source registry to read images and list the repository catalog:

```bash
SOURCE_REGISTRY_ID=$(az acr show \
    --name ${SOURCE_REGISTRY%%.*} \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --query "id" \
    --output tsv)

az role assignment create \
    --assignee $UAMI_PRINCIPAL_ID \
    --role "Container Registry Repository Reader" \
    --scope $SOURCE_REGISTRY_ID \
    --subscription $SUBSCRIPTION

az role assignment create \
    --assignee $UAMI_PRINCIPAL_ID \
    --role "Container Registry Repository Catalog Lister" \
    --scope $SOURCE_REGISTRY_ID \
    --subscription $SUBSCRIPTION
```

> **Note:** If the source registry is in a different resource group or subscription, update `--resource-group` and `--subscription` accordingly.

---

## Step 6 — Assign the Identity to the Source Registry

The managed identity must be associated with the upstream (source) registry so that the registry trusts and recognises it as a valid authentication principal.

```bash
az acr identity assign \
    --name ${SOURCE_REGISTRY%%.*} \
    --identities $UAMI_RESOURCE_ID \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION
```

> **Note:** If the source registry is in a different resource group or subscription, update `--resource-group` and `--subscription` accordingly.

---

## Step 7 — Assign the Identity to the Target Registry

The managed identity must also be associated with the target (downstream) registry so ACR can use it when executing cache pulls.

```bash
TARGET_REGISTRY_ID=$(az acr show \
    --name $TARGET_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --query "id" \
    --output tsv)

az acr identity assign \
    --name $TARGET_REGISTRY \
    --identities $UAMI_RESOURCE_ID \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION
```

---

## Step 8 — Deploy the Bicep Module

Deploy [cache-rule.bicep](cache-rule.bicep) to create the cache rule on the target registry.

```bash
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --template-file cache-rule.bicep \
    --parameters \
        registryName="$TARGET_REGISTRY" \
        cacheRuleName="$CACHE_RULE_NAME" \
        sourceRepo="$SOURCE_REPO" \
        targetRepo="$TARGET_REPO" \
        managedIdentityResourceId="$UAMI_RESOURCE_ID"
```

### Bicep Parameters Reference

| Parameter | Required | Default | Description |
|---|---|---|---|
| `registryName` | Yes | — | Name of the target (downstream) ACR registry |
| `cacheRuleName` | No | `cacherule-acr-to-acr-mi` | Name for the cache rule resource |
| `sourceRepo` | Yes | — | Fully qualified source repository (e.g. `registry.azurecr.io/hello-world`) |
| `targetRepo` | No | `hello-world` | Target repository name in the downstream registry |
| `managedIdentityResourceId` | Yes | — | Full resource ID of the User-Assigned Managed Identity |

---

## Step 9 — Verify the Cache Rule

Confirm the cache rule was created successfully:

```bash
az acr cache show \
    --name $CACHE_RULE_NAME \
    --registry $TARGET_REGISTRY \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION
```

---

## Step 10 — Test the Cache

Pull an image through the target registry. ACR will transparently fetch it from the source registry using the managed identity.

```bash
docker pull ${TARGET_REGISTRY}.azurecr.io/${TARGET_REPO}:latest
```

You can also verify the cached image appears in the target registry:

```bash
az acr repository show-tags \
    --name $TARGET_REGISTRY \
    --repository $TARGET_REPO \
    --subscription $SUBSCRIPTION
```

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Deployment fails with `FeatureNotEnabled` | Feature flag not yet `Registered` | Re-check Step 3; wait for `Registered` state |
| `AuthorizationFailed` on cache rule create | Identity not assigned to the target registry | Complete Step 7 before deploying |
| Pull through cache returns `unauthorized` | Identity missing required roles on source registry | Verify the role assignments from Step 5 |
| Feature registration stuck in `Registering` | Normal for preview features | Wait up to 15 minutes; re-run the `az feature show` check |

---

## References

- [ACR Artifact Cache overview](https://learn.microsoft.com/en-us/azure/container-registry/artifact-cache-overview)
- [Managed identities for Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity)
- [Bicep resource: `Microsoft.ContainerRegistry/registries/cacheRules`](https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries/cacherules)
