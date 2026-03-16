#!/usr/bin/env bash
# setup-cache-rule.sh
# Provisions the ACR-to-ACR cache rule infrastructure with managed identity
# authentication, then verifies the setup end-to-end.
# Resources are created idempotently: the script is safe to re-run.
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
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
info()  { echo -e "${YELLOW}[INFO]${NC} $*"; }
# run  — print + execute a provisioning command (stdout goes to terminal)
run()   { echo -e "${CYAN}[CMD]${NC} $*" > /dev/tty; "$@"; }
# query — print + execute a query command whose stdout is captured via $(...)
#          writes to /dev/tty so the [CMD] line is never suppressed by 2>/dev/null
query() { echo -e "${CYAN}[CMD]${NC} $*" > /dev/tty; "$@"; }

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
info "=== ACR Cache Rule — Infrastructure Setup & Verification ==="
echo ""

# ── Azure authentication ──────────────────────────────────────────────────────
info "Checking Azure CLI authentication..."
if ! query az account show &>/dev/null; then
  info "Not logged in. Running 'az login'..."
  run az login
fi

info "Setting subscription context to '$SUBSCRIPTION'..."
run az account set --subscription "$SUBSCRIPTION"
ACTIVE_SUB=$(query az account show --query "name" --output tsv 2>/dev/null || echo "unknown")
pass "Authenticated — active subscription: $ACTIVE_SUB"

info "Logging in to target ACR registry '$TARGET_REGISTRY'..."
run az acr login --name "$TARGET_REGISTRY" --subscription "$SUBSCRIPTION"
pass "Logged in to target registry"

echo ""

# ── Step 1: Feature flag is registered ──────────────────────────────────────
info "Step 1: Feature flag ArtifactCacheManagedIdentityAuthentication is Registered"
FEATURE_STATE=$(query az feature show \
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

# ── Step 2: UAMI (create if missing) ────────────────────────────────────────
info "Step 2: User-Assigned Managed Identity '$UAMI_NAME'"
UAMI_ID=$(query az identity show \
  --name "$UAMI_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "id" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "$UAMI_ID" ]]; then
  info "  UAMI not found — creating '$UAMI_NAME' in '$RESOURCE_GROUP'..."
  run az identity create \
    --name "$UAMI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --output none
  UAMI_ID=$(query az identity show \
    --name "$UAMI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --query "id" \
    --output tsv)
  pass "UAMI created: $UAMI_ID"
else
  pass "UAMI found: $UAMI_ID"
fi

UAMI_PRINCIPAL_ID=$(query az identity show \
  --name "$UAMI_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "principalId" \
  --output tsv 2>/dev/null || echo "")

# ── Step 3: Enable ABAC on source registry (if not already set) ────────────────
info "Step 3: ABAC enabled on source registry '$SOURCE_REGISTRY_NAME'"
ABAC_MODE=$(query az acr show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "roleAssignmentMode" \
  --output tsv 2>/dev/null || echo "")

if [[ "$ABAC_MODE" == "rbac-abac" ]]; then
  pass "ABAC already enabled on source registry (roleAssignmentMode: $ABAC_MODE)"
else
  info "  Enabling ABAC (rbac-abac) on source registry..."
  run az acr update \
    --name "$SOURCE_REGISTRY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --role-assignment-mode rbac-abac \
    --output none
  pass "ABAC enabled on source registry"
fi

# ── Step 4: Fine-grained read roles on source registry (assign if missing) ───
info "Step 4: UAMI role assignments on source registry '$SOURCE_REGISTRY_NAME'"
SOURCE_REGISTRY_SCOPE=$(query az acr show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "id" \
  --output tsv 2>/dev/null || echo "")

if [[ -z "$SOURCE_REGISTRY_SCOPE" ]]; then
  fail "Source registry '$SOURCE_REGISTRY_NAME' not found — cannot assign roles"
else
  READER_COUNT=$(query az role assignment list \
    --assignee "$UAMI_PRINCIPAL_ID" \
    --role "Container Registry Repository Reader" \
    --scope "$SOURCE_REGISTRY_SCOPE" \
    --subscription "$SUBSCRIPTION" \
    --query "length(@)" \
    --output tsv 2>/dev/null || echo "0")
  if [[ "$READER_COUNT" -ge 1 ]]; then
    pass "'Container Registry Repository Reader' already assigned on source registry"
  else
    info "  Assigning 'Container Registry Repository Reader' to UAMI on source registry..."
    run az role assignment create \
      --assignee "$UAMI_PRINCIPAL_ID" \
      --role "Container Registry Repository Reader" \
      --scope "$SOURCE_REGISTRY_SCOPE" \
      --subscription "$SUBSCRIPTION" \
      --output none
    pass "'Container Registry Repository Reader' assigned on source registry"
  fi

fi

# ── Step 5: UAMI assigned to source registry (assign if missing) ─────────────
info "Step 5: UAMI assigned to source registry '$SOURCE_REGISTRY_NAME'"
SOURCE_IDENTITIES=$(query az acr identity show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "userAssignedIdentities" \
  --output json 2>/dev/null || echo "{}")

if [[ -n "$UAMI_ID" ]] && echo "$SOURCE_IDENTITIES" | grep -qi "$(basename "$UAMI_ID")"; then
  pass "UAMI already assigned to source registry"
else
  info "  Assigning UAMI to source registry..."
  run az acr identity assign \
    --name "$SOURCE_REGISTRY_NAME" \
    --identities "$UAMI_ID" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --output none
  pass "UAMI assigned to source registry"
fi

# ── Step 6: UAMI assigned to target registry (assign if missing) ─────────────
info "Step 6: UAMI assigned to target registry '$TARGET_REGISTRY'"
TARGET_IDENTITIES=$(query az acr identity show \
  --name "$TARGET_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "userAssignedIdentities" \
  --output json 2>/dev/null || echo "{}")

if [[ -n "$UAMI_ID" ]] && echo "$TARGET_IDENTITIES" | grep -qi "$(basename "$UAMI_ID")"; then
  pass "UAMI already assigned to target registry"
else
  info "  Assigning UAMI to target registry..."
  run az acr identity assign \
    --name "$TARGET_REGISTRY" \
    --identities "$UAMI_ID" \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION" \
    --output none
  pass "UAMI assigned to target registry"
fi

# ── Step 7: Cache rule (deploy via Bicep if missing) ─────────────────────────
info "Step 7: Cache rule '$CACHE_RULE_NAME' on target registry '$TARGET_REGISTRY'"
CACHE_RULE_JSON=$(query az acr cache show \
  --name "$CACHE_RULE_NAME" \
  --registry "$TARGET_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --output json 2>/dev/null || echo "")

if [[ -n "$CACHE_RULE_JSON" ]]; then
  pass "Cache rule already exists"
  PROVISIONING=$(echo "$CACHE_RULE_JSON" | grep -o '"provisioningState":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
  info "  Provisioning state: $PROVISIONING"
else
  BICEP_FILE="$(dirname "$0")/../cache-rule.bicep"
  if [[ ! -f "$BICEP_FILE" ]]; then
    fail "Bicep template not found at '$BICEP_FILE' — cannot deploy cache rule"
  else
    info "  Deploying cache rule via Bicep..."
    run az deployment group create \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$SUBSCRIPTION" \
      --template-file "$BICEP_FILE" \
      --parameters \
          registryName="$TARGET_REGISTRY" \
          cacheRuleName="$CACHE_RULE_NAME" \
          sourceRepo="$SOURCE_REPO" \
          targetRepo="$TARGET_REPO" \
          managedIdentityResourceId="$UAMI_ID" \
      --output none
    pass "Cache rule deployed"
  fi
fi

# ── Test 1: Pull image through cache ─────────────────────────────────────────
info "Test 1: Pull image through the target registry cache"
IMAGE="${TARGET_REGISTRY}.azurecr.io/${TARGET_REPO}:latest"

info "  Pulling $IMAGE ..."
if run docker pull "$IMAGE" > /dev/null 2>&1; then
  pass "Image pulled successfully: $IMAGE"
else
  fail "Failed to pull image: $IMAGE"
fi

# ── Test 2: Image visible in target registry ─────────────────────────────────
info "Test 2: Image tag visible in target registry repository"
TAG_COUNT=$(query az acr repository show-tags \
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

# ── Show cache rule ───────────────────────────────────────────────────────────
echo ""
info "=== Cache Rule Details ==="
run az acr cache show \
  --name "$CACHE_RULE_NAME" \
  --registry "$TARGET_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --output json 2>/dev/null || true

# ── Show UAMI role assignments on source registry ─────────────────────────────
echo ""
info "=== UAMI Role Assignments on Source Registry '$SOURCE_REGISTRY_NAME' ==="
SOURCE_REGISTRY_SCOPE=$(query az acr show \
  --name "$SOURCE_REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  --query "id" \
  --output tsv 2>/dev/null || echo "")
run az role assignment list \
  --assignee "$UAMI_PRINCIPAL_ID" \
  --scope "$SOURCE_REGISTRY_SCOPE" \
  --subscription "$SUBSCRIPTION" \
  --query "[].{Role:roleDefinitionName, PrincipalType:principalType, Scope:scope}" \
  --output table 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "=== Summary ==="
if [[ "$FAILURES" -eq 0 ]]; then
  echo -e "${GREEN}All tests passed.${NC}"
else
  echo -e "${RED}$FAILURES test(s) failed.${NC}"
  exit 1
fi
