/*
  Deploy storage account with private endpoint and private DNS zone
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

// existing resource name params 
param vnetName string
param privateEndpointsSubnetName string

// variables
var storageName = 'st${baseName}'
var storageSkuName = 'Standard_LRS'
var storageDnsGroupName = '${storagePrivateEndpointName}/default'
var storagePrivateEndpointName = 'pep-${storageName}'
var blobStorageDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }  
}

// ---- Storage resources ----
resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageName
  location: location
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: storagePrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: storagePrivateEndpointName
        properties: {
          groupIds: [
            'blob'
          ]
          privateLinkServiceId: storage.id
        }
      }
    ]
  }
}

resource storageDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: blobStorageDnsZoneName
  location: 'global'
  properties: {}
}

resource storageDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageDnsZone
  name: '${blobStorageDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  name: storageDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: blobStorageDnsZoneName
        properties: {
          privateDnsZoneId: storageDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    storagePrivateEndpoint
  ]
}

@description('The name of the storage account.')
output storageName string = storage.name
