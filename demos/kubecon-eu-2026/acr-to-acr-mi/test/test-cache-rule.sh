#!/usr/bin/env bash
# test-cache-rule.sh
# End-to-end test for the ACR-to-ACR cache rule with managed identity authentication.
# Run this script AFTER completing all steps in the README.
#
# Usage:
#   export SUBSCRIPTION="..."
#   export RESOURCE_GROUP="..."
#   export SOURCE_REGISTRY="<name>.azurecr.io"
#   export TARGET_REGISTRY="<name>"
#   export SOURCE_REPO="<name>.azurecr.io/hello-world"
#   export TARGET_REPO="hello-world"
#   export UAMI_NAME="..."
#   export CACHE_RULE_NAME="cacherule-acr-to-acr-mi"
#   bash test/test-cache-rule.sh

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

FAILURES=0

# ── Required variables ────────────────────────────────────────────────────────
REQUIRED_VARS=(SUBSCRIPTION RESOURCE_GROUP SOURCE_REGISTRY TARGET_REGISTRY
               SOURCE_REPO TARGET_REPO UAMI_NAME CACHE_RULE_NAME)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo -e "${RED}[ERROR]${NC} Required environment variable \$$var is not set."
    exit 1
  fi
done

SOURCE_REGISTRY_NAME="${SOURCE_REGISTRY%%.*}"

echo ""
info "=== ACR Cache Rule — End-to-End Test ==="
echo ""

# ── Azure authentication ──────────────────────────────────────────────────────
info "Checking Azure CLI authentication..."
if ! az account show &>/dev/null; then
  info "Not logged in. Running 'az login'..."
  az login
fi

info "Setting subscription context to '$SUBSCRIPTION'..."
az account set --subscription "$SUBSCRIPTION"
ACTIVE_SUB=$(az account show --query "name" --output tsv 2>/dev/null || echo "unknown")
pass "Authenticated — active subscription: $ACTIVE_SUB"

info "Logging in to target ACR registry '$TARGET_REGISTRY'..."
az acr login --name "$TARGET_REGISTRY" --subscription "$SUBSCRIPTION"
pass "Logged in to target registry"

echo ""

# ── Test 1: Feature flag is registered ───────────────────────────────────────
info "Test 1: Feature flag ArtifactCacheManagedIdentityAuthentication is Registered"
FEATURE_STATE=$(az feature show \
  --namespace Microsoft.ContainerRegistry \
  --name ArtifactCacheManagedIdentityAuthentication \
  --subscription "$SUBSCRIPTION" \
  --query "properties.state" \
  --output tsv 2>/dev/null || echo "NotFound")

if [[ "$FEATURE_STATE" == "Registered" ]]; then
  pass "Feature flag state: $FEATURE_STATE"
else
  fail "Feature flag state: $FEATURE_STATE (expected Registered)"
fi

# ── Test 2: UAMI exists (create if missing) ───────────────────────────────────
info "Test 2: User-Assigned Managed Identity '$UAMI_NAME' exists"
UAMI_ID=$(az identity show \
  --name "$UAMI_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "id" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "$UAMI_ID" ]]; then
  info "  UAMI not found — creating '$UAMI_NAME' in '$RESOURCE_GROUP'..."
  az identity create \
    --name "$UAMI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --output none
  UAMI_ID=$(az identity show \
    --name "$UAMI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --query "id" \
    --output tsv)
  pass "UAMI created: $UAMI_ID"
else
  pass "UAMI found: $UAMI_ID"
fi

UAMI_PRINCIPAL_ID=$(az identity show \
  --name "$UAMI_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "principalId" \
  --output tsv 2>/dev/null || echo "")

# ── Test 3: Fine-grained read roles on source registry ───────────────────────
info "Test 3: UAMI has required roles on source registry '$SOURCE_REGISTRY_NAME'"
SOURCE_REGISTRY_SCOPE=$(az acr show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "id" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "$SOURCE_REGISTRY_SCOPE" ]]; then
  fail "Source registry '$SOURCE_REGISTRY_NAME' not found"
else
  READER_COUNT=$(az role assignment list \
    --assignee "$UAMI_PRINCIPAL_ID" \
    --role "Container Registry Repository Reader" \
    --scope "$SOURCE_REGISTRY_SCOPE" \
    --subscription "$SUBSCRIPTION" \
    --query "length(@)" \
    --output tsv 2>/dev/null || echo "0")
  if [[ "$READER_COUNT" -ge 1 ]]; then
    pass "'Container Registry Repository Reader' role assignment found on source registry"
  else
    fail "'Container Registry Repository Reader' role assignment NOT found on source registry"
  fi

  LISTER_COUNT=$(az role assignment list \
    --assignee "$UAMI_PRINCIPAL_ID" \
    --role "Container Registry Repository Catalog Lister" \
    --scope "$SOURCE_REGISTRY_SCOPE" \
    --subscription "$SUBSCRIPTION" \
    --query "length(@)" \
    --output tsv 2>/dev/null || echo "0")
  if [[ "$LISTER_COUNT" -ge 1 ]]; then
    pass "'Container Registry Repository Catalog Lister' role assignment found on source registry"
  else
    fail "'Container Registry Repository Catalog Lister' role assignment NOT found on source registry"
  fi
fi

# ── Test 4: UAMI assigned to source registry ─────────────────────────────────
info "Test 4: UAMI is assigned to source registry '$SOURCE_REGISTRY_NAME'"
SOURCE_IDENTITIES=$(az acr identity show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "userAssignedIdentities" \
  --output json 2>/dev/null || echo "{}")

if echo "$SOURCE_IDENTITIES" | grep -qi "${UAMI_NAME}"; then
  pass "UAMI is assigned to source registry"
else
  # Fall back to matching by resource ID substring
  if [[ -n "$UAMI_ID" ]] && echo "$SOURCE_IDENTITIES" | grep -qi "$(basename "$UAMI_ID")"; then
    pass "UAMI is assigned to source registry (matched by resource ID)"
  else
    fail "UAMI does NOT appear to be assigned to source registry"
  fi
fi

# ── Test 5: UAMI assigned to target registry ─────────────────────────────────
info "Test 5: UAMI is assigned to target registry '$TARGET_REGISTRY'"
TARGET_IDENTITIES=$(az acr identity show \
  --name "$TARGET_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "userAssignedIdentities" \
  --output json 2>/dev/null || echo "{}")

if [[ -n "$UAMI_ID" ]] && echo "$TARGET_IDENTITIES" | grep -qi "$(basename "$UAMI_ID")"; then
  pass "UAMI is assigned to target registry"
else
  fail "UAMI does NOT appear to be assigned to target registry"
fi

# ── Test 6: Cache rule exists ─────────────────────────────────────────────────
info "Test 6: Cache rule '$CACHE_RULE_NAME' exists on target registry"
CACHE_RULE_JSON=$(az acr cache show \
  --name "$CACHE_RULE_NAME" \
  --registry "$TARGET_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --output json 2>/dev/null || echo "")

if [[ -n "$CACHE_RULE_JSON" ]]; then
  pass "Cache rule found"
  PROVISIONING=$(echo "$CACHE_RULE_JSON" | grep -o '"provisioningState":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  info "  Provisioning state: $PROVISIONING"
else
  fail "Cache rule '$CACHE_RULE_NAME' not found"
fi

# ── Test 7: Pull image through cache ─────────────────────────────────────────
info "Test 7: Pull image through the target registry cache"
IMAGE="${TARGET_REGISTRY}.azurecr.io/${TARGET_REPO}:latest"

info "  Pulling $IMAGE ..."
if docker pull "$IMAGE" > /dev/null 2>&1; then
  pass "Image pulled successfully: $IMAGE"
else
  fail "Failed to pull image: $IMAGE"
fi

# ── Test 8: Image visible in target registry ──────────────────────────────────
info "Test 8: Image tag visible in target registry repository"
TAG_COUNT=$(az acr repository show-tags \
  --name "$TARGET_REGISTRY" \
  --repository "$TARGET_REPO" \
  --subscription "$SUBSCRIPTION" \
  --query "length(@)" \
  --output tsv 2>/dev/null || echo "0")

if [[ "$TAG_COUNT" -ge 1 ]]; then
  pass "Repository '$TARGET_REPO' has $TAG_COUNT tag(s) in target registry"
else
  fail "No tags found in '$TARGET_REPO' on target registry"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "=== Test Summary ==="
if [[ "$FAILURES" -eq 0 ]]; then
  echo -e "${GREEN}All tests passed.${NC}"
else
  echo -e "${RED}$FAILURES test(s) failed.${NC}"
  exit 1
fi
