param (
    [Parameter(Mandatory = $true)]
    [string]$template,
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$location,
    [string]$endpoint = "https://ciqs-api-westus.azurewebsites.net/",
    [string]$solutionStorageConnectionString,
    [string]$inputParametersFile
)

$ErrorActionPreference = 'Stop'

function Get-AccessToken($tenantId) {
    if(-not (Get-Module AzureRm.Profile)) {
        Import-Module AzureRm.Profile
      }
      $azureRmProfileModuleVersion = (Get-Module AzureRm.Profile).Version
      # refactoring performed in AzureRm.Profile v3.0 or later
      if($azureRmProfileModuleVersion.Major -ge 3) {
        $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Accounts.Count) {
          Write-Error "Ensure you have logged in before calling this function."    
        }
      } else {
        # AzureRm.Profile < v3.0
        $azureRmProfile = [Microsoft.WindowsAzure.Commands.Common.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Context.Account.Count) {
          Write-Error "Ensure you have logged in before calling this function."    
        }
      }
  
      $currentAzureContext = Get-AzureRmContext
      $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
      Write-Debug ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
      $tokenAD = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)
      return $tokenAD.AccessToken
}

#function Get-AccessToken($tenantId) {
#    $cache = [Microsoft.IdentityModel.Clients.ActiveDirectory.TokenCache]::DefaultShared
#    $cacheItem = $cache.ReadItems() | Where {$_.TenantId -eq $tenantId} | Select-Object -First 1
#    if ($cacheItem -eq $null) {
#        $cacheItem = $cache.ReadItems() | Select-Object -First 1
#    }
#    return $cacheItem.AccessToken
#}

function WaitForDeployment {
    param
    (
        [Parameter(Mandatory = $true)]
        $Subscrption,

        [Parameter(Mandatory = $true)]
        $UniqueId
    )

    do
    {
        Start-Sleep -m 1000
        $deploymentDetails = Invoke-RestMethod "${endpoint}api/deployments/${Subscription}/${UniqueId}" -Headers $header -Method GET -ContentType "application/json"
        $deployment = $deploymentDetails.deployment
        $provisioningSteps = $deploymentDetails.provisioningSteps
        $status = $deployment.status


        if ($provisioningSteps -ne $null) {
            $currentProvisioningStep = $provisioningSteps[$deployment.currentProvisioningStep]
            $message = $currentProvisioningStep.Title
            if ($status -notlike 'ready') {
                $message = "$message..."
            } else {
                $message = "$message!"
            }
        } else {
            $message = "Deployment is being created..."
        }

        if ($oldMessage -ne $message) {
            Write-Host $message
        }

        $oldMessage = $message
    }
    while ($status -notlike 'failed' -and $status -notlike 'actionRequired' -and $status -notlike 'ready')

    return $deploymentDetails
}

$tenantId = (Get-AzureRmContext).Tenant.TenantId
$subscription = (Get-AzureRmContext).Subscription.SubscriptionId
$token = Get-AccessToken $tenantId

$header = @{
    'Content-Type'  = 'application\json'
    'Authorization' = "Bearer $token"
}

$payload = @{
    Location = $location
    Name = $resourceGroup
    Subscription = $subscription
    TemplateId = $template
}

if ($solutionStorageConnectionString) {
    $payload.SolutionStorageConnectionString = $solutionStorageConnectionString
}

Write-Host "Creating new CIQS deployment of ${template} into ${resourceGroup}..."

$body = $payload | ConvertTo-Json
$deployment = Invoke-RestMethod "${endpoint}api/deployments" -Headers $header -Method POST -Body $body -ContentType "application/json"

Write-Host "New deployment:"
$deployment

$uniqueId = $deployment.uniqueId

do {
    $deploymentDetails = WaitForDeployment -Subscrption $subscription -UniqueId $uniqueId
    $status = $deploymentDetails.deployment.status

    if ($status -like 'actionRequired') {
        Write-Host "Submitting intput parameters..."

        $body = Get-Content -Raw -Path $inputParametersFile
        $ignore = Invoke-RestMethod "${endpoint}api/deployments/${subscription}/${uniqueId}" -Headers $header -Method PUT -Body $body -ContentType "application/json"
        Write-Host "Continuing provisioning..."
    }
}
while ($status -notlike 'failed' -and $status -notlike 'ready')

if ($status -notlike 'ready')
{
    throw "Deployment failed."
}

Write-Host "Final output:"
$deploymentDetails.provisioningSteps[-1].instructions.data