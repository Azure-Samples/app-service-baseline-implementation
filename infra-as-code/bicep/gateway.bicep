/*
  Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
*/

param baseName string
param location string = resourceGroup().location
param developmentEnvironment bool

param availabilityZones array
param customDomainName string

param gatewayCertSecretUri string

// existing resource name params 
param vnetName string
param appGatewaySubnetName string
param appName string
param keyVaultName string
param logWorkspaceName string

//variables
var appGateWayName = 'agw-${baseName}'
var appGatewayManagedIdentityName = 'id-${appGateWayName}'
var appGatewayPublicIpName = 'pip-${baseName}'
var appGateWayFqdn = 'fe-${baseName}'
var wafPolicyName= 'waf-${baseName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing =  {
  name: vnetName
  
  resource appGatewaySubnet 'subnets' existing = {
    name: appGatewaySubnetName
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-04-01-preview' existing =  {
  name: keyVaultName
}

resource webApp 'Microsoft.Web/sites@2021-01-01' existing = {
  name: appName
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  name: logWorkspaceName
}

// Built-in Azure RBAC role that is applied to a Key Vault to grant with secrets content read privileges. Granted to both Key Vault and our workload's identity.
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

// ---- App Gateway resources ----

// Managed Identity for App Gateway. 
resource appGatewayManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: appGatewayManagedIdentityName
  location: location
}

// Grant the Azure Application Gateway managed identity with key vault secrets role permissions; this allows pulling certificates.
resource appGatewayManagedIdentitySecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: keyVault
  name: guid(resourceGroup().id, appGatewayManagedIdentityName, keyVaultSecretsUserRole.id)
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: appGatewayManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//External IP for App Gateway
resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: appGatewayPublicIpName
  location: location
  zones: !developmentEnvironment ? availabilityZones : null
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: appGateWayFqdn
    }
  }
}

//WAF policy definition
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-05-01' = {
  name: wafPolicyName
  location: location
  properties: {
    policySettings: {
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '0.1'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

//App Gateway
resource appGateWay 'Microsoft.Network/applicationGateways@2021-05-01' = {
  name: appGateWayName
  location: location
  zones: !developmentEnvironment ? availabilityZones : null
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGatewayManagedIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    sslPolicy: {
      policyType: 'Custom'
      cipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
      minProtocolVersion: 'TLSv1_2'
    }

    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: vnet::appGatewaySubnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    probes: [
      {
        name: 'probe-web${baseName}'
        properties: {
          protocol: 'Https'
          path: '/favicon.ico'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
              '401'
              '403'
            ]
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
    enableHttp2: false
    sslCertificates: [
      {
        name: '${appGateWayName}-ssl-certificate'
        properties: {
          keyVaultSecretId: gatewayCertSecretUri
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'pool-${appName}'
        properties: {
          backendAddresses: [
            {
              fqdn: webApp.properties.defaultHostName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'WebAppBackendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGateWayName, 'probe-web${baseName}')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'WebAppListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGateWayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGateWayName, 'port-443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGateWayName, '${appGateWayName}-ssl-certificate')
          }
          hostName: 'www.${customDomainName}'
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'WebAppRoutingRule'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGateWayName, 'WebAppListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGateWayName, 'pool-${appName}')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGateWayName, 'WebAppBackendHttpSettings')
          }
        }
      }
    ]
    autoscaleConfiguration: {
      minCapacity: developmentEnvironment ? 2 : 3
      maxCapacity: developmentEnvironment ? 3 : 5
    }
  }
  dependsOn: [
    appGatewayManagedIdentitySecretsUserRoleAssignment
  ]
}


// App Gateway diagnostics
resource appGatewayDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appGateWay
  name: appGateWay.name
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 7
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output appGateWayName string = appGateWay.name


