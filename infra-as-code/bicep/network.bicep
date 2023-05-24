/*
  Deploy vnet with subnets and NSGs
*/

param baseName string
param location string = resourceGroup().location
param developmentEnvironment bool

// variables
var vnetName = 'vnet-${baseName}'
var ddosPlanName = 'ddos-${baseName}'

var vnetAddressPrefix = '10.0.0.0/16'
var appGatewaySubnetPrefix = '10.0.1.0/24'
var appServicesSubnetPrefix = '10.0.0.0/24'
var privateEndpointsSubnetPrefix = '10.0.2.0/27'

//Temp disable DDoS protection
var enableDdosProtection = !developmentEnvironment && false

// ---- Networking resources ----

// DDoS Protection Plan
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2022-07-01' = if (enableDdosProtection) {
  name: ddosPlanName
  location: location
  properties: {}
}

//vnet and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: vnetName
  location: location
  properties: {
    enableDdosProtection: enableDdosProtection
    ddosProtectionPlan: enableDdosProtection ? { id: ddosProtectionPlan.id } : null
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        //App services plan subnet
        name: 'snet-appServicePlan'
        properties: {
          addressPrefix: appServicesSubnetPrefix
          networkSecurityGroup: {
            id: appServiceSubnetNsg.id
          }
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        //App Gateway subnet
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: appGatewaySubnetNsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        //Private endpoints subnet
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: {
            id: privateEnpointsSubnetNsg.id
          }
        }

      }
    ]
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: 'snet-appGateway'
  }

  resource appServiceSubnet 'subnets' existing = {
    name: 'snet-appServicePlan'
  }

  resource privateEnpointsSubnet 'subnets' existing = {
    name: 'snet-privateEndpoints'
  }
}

//App Gateway subnet NSG
resource appGatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: 'nsg-appGatewaySubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppGw.In.Allow.ControlPlane'
        properties: {
          description: 'Allow inbound Control Plane (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow443.Internet'
        properties: {
          description: 'Allow ALL inbound web traffic on port 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appGatewaySubnetPrefix
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.Out.Allow.AppServices'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to the App services subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: appServicesSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppGw.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 101
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to Azure Monitor'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 206
          direction: 'Outbound'
        }
      }
    ]
  }
}

//App service subnet nsg
resource appServiceSubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: 'nsg-appServicesSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppPlan.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the private endpoints subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 201
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from App service to the AzureMonitor ServiceTag.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 206
          direction: 'Outbound'
        }
      }
    ]
  }
}

//Private endpoints subnets NSG
resource privateEnpointsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: 'nsg-privateEndpointsSubnet'
  location: location
  properties: {}
}

output vnetNName string = vnet.name
output appServicesSubnetName string = vnet::appServiceSubnet.name
output appGatewaySubnetName string = vnet::appGatewaySubnet.name
output privateEndpointsSubnetName string = vnet::privateEnpointsSubnet.name
