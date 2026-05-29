// ─────────────────────────────────────────────────────────────────────────────
// infra/container-app.bicep
//
// Deploys:
//   - Azure Container Registry (to host the Docker image)
//   - Azure Container Apps Environment (shared infra)
//   - Azure Container App (codegraph-org MCP server)
//   - Azure File Share (persistent graph.db via volume mount)
//
// Deploy:
//   az group create -n rg-codegraph -l westeurope
//   az deployment group create \
//     --resource-group rg-codegraph \
//     --template-file infra/container-app.bicep \
//     --parameters githubPat=<PAT> githubOrg=my-org githubRepos="repo-auth repo-payments"
// ─────────────────────────────────────────────────────────────────────────────

@description('GitHub PAT for cloning private repos')
@secure()
param githubPat string

@description('GitHub org name')
param githubOrg string = 'my-org'

@description('Space-separated list of repos to index')
param githubRepos string = 'repo-auth repo-payments repo-gateway'

@description('CodeGraph MCP tool profile')
@allowed(['all', 'core', 'graph', 'memory'])
param codegraphProfile string = 'graph'

@description('Container image (override after first push to ACR)')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Azure region')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'codegraph'

// ── Storage account for persistent graph.db ──────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${baseName}${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/codegraph-data'
}

// ── Log Analytics workspace ───────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${baseName}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Container Apps Environment ────────────────────────────────────────────────
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${baseName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Mount the Azure File Share for graph.db persistence
resource storageMount 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: environment
  name: 'codegraph-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: 'codegraph-data'
      accessMode: 'ReadWrite'
    }
  }
}

// ── Container App ─────────────────────────────────────────────────────────────
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${baseName}-server'
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedHeaders: ['*']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
        }
      }
      secrets: [
        { name: 'gh-pat', value: githubPat }
      ]
    }
    template: {
      containers: [
        {
          name: 'codegraph-server'
          image: containerImage
          env: [
            { name: 'GH_PAT',            secretRef: 'gh-pat' }
            { name: 'CODEGRAPH_ORG',     value: githubOrg }
            { name: 'CODEGRAPH_REPOS',   value: githubRepos }
            { name: 'CODEGRAPH_PROFILE', value: codegraphProfile }
            { name: 'PORT',              value: '3000' }
          ]
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
          volumeMounts: [
            {
              volumeName: 'codegraph-data'
              mountPath: '/root/.codegraph'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 3000 }
              initialDelaySeconds: 120
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 3000 }
              initialDelaySeconds: 30
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1   // Always at least 1 running (persistent graph)
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: { metadata: { concurrentRequests: '20' } }
          }
        ]
      }
      volumes: [
        {
          name: 'codegraph-data'
          storageType: 'AzureFile'
          storageName: 'codegraph-storage'
        }
      ]
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name
output environmentName string = environment.name
output storageAccountName string = storageAccount.name
