/*
  Deploy a SQL server with a sample database, a private endpoint and a private DNS zone
*/
@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The administrator username of the SQL server')
param sqlAdministratorLogin string

@description('The administrator password of the SQL server.')
@secure()
param sqlAdministratorLoginPassword string

@description('The name of the virtual network to deploy the private endpoint into')
param vnetName string

@description('The name of the subnet to deploy the private endpoint into')
param privateEndpointsSubnetName string

// variables
var sqlServerName = 'sql-${baseName}'
var sampleSqlDatabaseName = 'sqldb-adventureworks'
var sqlPrivateEndpointName = 'pep-${sqlServerName}'
var sqlDnsGroupName = '${sqlPrivateEndpointName}/default'
var sqlDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'
var sqlConnectionString = 'Server=tcp:${sqlServerName}${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sampleSqlDatabaseName};Persist Security Info=False;User ID=${sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2024-10-01' existing =  {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }  
}

// ---- Sql resources ----

// sql server
resource sqlServer 'Microsoft.Sql/servers@2024-11-01-preview' = {
  name: sqlServerName
  location: location
  tags: {
    displayName: sqlServerName
  }
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    version: '12.0'
    publicNetworkAccess: 'Disabled'
  }
}

//database
resource slqDatabase 'Microsoft.Sql/servers/databases@2024-11-01-preview' = {
  name: sampleSqlDatabaseName
  parent: sqlServer
  location: location

  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  tags: {
    displayName: sampleSqlDatabaseName
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 104857600
    sampleName: 'AdventureWorksLT'
  }
}

resource sqlServerPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-10-01' = {
  name: sqlPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: sqlPrivateEndpointName
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

resource sqlServerDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: sqlServerDnsZone
  name: '${sqlDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource sqlServerDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: sqlDnsZoneName
  location: 'global'
  properties: {}
}

resource sqlServerDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-10-01' = {
  name: sqlDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: sqlDnsZoneName
        properties: {
          privateDnsZoneId: sqlServerDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    sqlServerPrivateEndpoint
  ]
}

@description('The connection string to the sample database.')
output sqlConnectionString string = sqlConnectionString
