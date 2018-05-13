# Azure Cloud Intelligence Solution
Deploy Cloud intelligence solution using Solution Authoring .

## Commands
 - Run following command to solution authoring console to get connection string.

    `echo %CUSTOMCONNSTR_SolutionStorageConnectionString%`

 - `Login-AzureRmAccount`

- `Select-AzureRmSubscription -SubscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- Run following command into the powershell.

  `.\deploy.ps1 -template 001-helloworld@user -resourceGroup saw01 -location eastus -solutionStorageConnectionString DefaultEndpointsProtocol="xxxxx-xxx-xx-xx-x-x-x-xxxxxxxx"`

