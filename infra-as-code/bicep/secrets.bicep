/*
  Deploy a Key Vault with a private endpoint and DNS zone
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string
param sqlConnectionString string

// existing resource name params 
param vnetName string
param privateEndpointsSubnetName string

//variables
var keyVaultName = 'kv-${baseName}'
var keyVaultPrivateEndpointName = 'pep-${keyVaultName}'
var keyVaultDnsGroupName = '${keyVaultPrivateEndpointName}/default'
var keyVaultDnsZoneName = 'privatelink.vaultcore.azure.net' //Cannot use 'privatelink${environment().suffixes.keyvaultDns}', per https://github.com/Azure/bicep/issues/9708

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }  
}

// ---- Key Vault resources ----
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices' // Required for AppGW communication
    }
  }
  resource kvsGatewayPublicCert 'secrets' = {
    name: 'gateway-public-cert'
    properties: {
      value: appGatewayListenerCertificate
      contentType: 'application/x-pkcs12'
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: keyVaultPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: keyVaultPrivateEndpointName
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: keyVaultDnsZoneName
  location: 'global'
  properties: {}
}

resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: '${keyVaultDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  name: keyVaultDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: keyVaultDnsZoneName
        properties: {
          privateDnsZoneId: keyVaultDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    keyVaultPrivateEndpoint
  ]
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'adWorksConnString'
  properties: {
    value: sqlConnectionString
  }
}

@description('The name of the key vault account.')
output keyVaultName string= keyVault.name

@description('Uri to the secret holding the cert.')
output gatewayCertSecretUri string = keyVault::kvsGatewayPublicCert.properties.secretUri
