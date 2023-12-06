using './main.bicep'

param baseName = ''
param sqlAdministratorLogin = ''
param sqlAdministratorLoginPassword = ''
param location = 'westus3' 
param customDomainName = 'contoso.com'
param appGatewayListenerCertificate = ''
param developmentEnvironment = false
param publishFileName = 'SimpleWebApp.zip'

