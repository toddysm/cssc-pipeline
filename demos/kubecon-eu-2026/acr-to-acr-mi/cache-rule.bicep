@description('Name of the registry to create the cache rule in')
param registryName string

@description('Name of the cache rule')
param cacheRuleName string = 'cacherule-acr-to-acr-mi'

@description('Source registry and repository (e.g., upstreamregistry.azurecr.io/hello-world)')
param sourceRepo string

@description('Target repository in the downstream registry')
param targetRepo string = 'hello-world'

@description('Resource ID of the user-assigned managed identity for authentication')
param managedIdentityResourceId string

resource cacheRule 'Microsoft.ContainerRegistry/registries/cacheRules@2026-01-01-preview' = {
  name: '${registryName}/${cacheRuleName}'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    sourceRepository: sourceRepo
    targetRepository: targetRepo
  }
}

output cacheRuleId string = cacheRule.id
output cacheRuleName string = cacheRule.name
