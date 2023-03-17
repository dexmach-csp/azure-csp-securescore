<#
.DESCRIPTION
Data retrieval script for the Mission 65 project. This script will retrieve all data necessary for the secure score dashboard.
More information on the process can be found in the readme of this repository at [https://github.com/dexmach-csp/azure-csp-securescore].
Powershell 7 is required for this script.
#>
[cmdletbinding()]
param()
$ErrorActionPreference = 'Stop'

#region General functions
function Install-RequiredModules {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Array of custom module objects expected. Two mandatory properties: 'ModuleName' and 'RequiredVersion' for each object.")]
        [array]$RequiredModulesList
    )
    Write-Output "[Configuration] Making sure the environment contains the required modules."
    foreach ($module in $RequiredModulesList) {
        try {
            Write-Verbose " > A required version of [$($module.RequiredVersion)] was specified for module [$($module.ModuleName)]."
            $ModuleCheck = Get-Module -Name $module.ModuleName -ListAvailable -Verbose:$false | Where-Object { $_.Version.ToString() -eq $module.RequiredVersion }
            if (-not $ModuleCheck) {
                Write-Verbose " > The required version of the module [$($module.ModuleName)] is not available locally. Installing from the gallery.."
                Install-Module -Name $module.ModuleName -RequiredVersion $module.RequiredVersion -Scope CurrentUser -Repository 'psgallery' -Force -AllowClobber -Verbose:$false
            }
            Write-Verbose " > Importing the module [$($module.ModuleName)] with version [$($module.RequiredVersion)].."
            Import-Module -Name $module.ModuleName -RequiredVersion $module.RequiredVersion -Verbose:$false
        }
        catch {
            throw "An issue occured during the session module prerequisite phase for module [$($module.ModuleName)] with version [$($module.RequiredVersion)]. We recommend to execute the process again in a new session. If the issue persists please contact the maintainer. The retrieved error was: $_"
        }
    }
}
#endregion

#region Processes
function Start-CSPSecureScorePrerequisitesProcess {
    #region Local environment configuration
    Write-Host "`n>> Local environment configuration <<" -ForegroundColor Cyan
    $RequiredModules = @(
        @{
            ModuleName      = 'Microsoft.Graph.Authentication'
            RequiredVersion = '1.15.0'
        },
        @{
            ModuleName      = 'Microsoft.Graph.Applications'
            RequiredVersion = '1.15.0'
        }
    )
    Install-RequiredModules -RequiredModulesList $RequiredModules
    #endregion

    #region Azure graph connection
    Write-Host "`n>> Azure graph connection <<" -ForegroundColor Cyan
    $CSPApplicationDisplayName = 'DexMach CSP Secure Score dashboard'
    do {
        $TenantId = (Read-Host -Prompt "Provide the tenant id of your Azure tenant in which you want to create the multi-tenant application").TrimEnd().TrimStart()
        if (-not $TenantId) {
            Write-Output "No input was provided. Please try again."
        }
    }
    while (-not $TenantId)
    try {
        $null = Connect-MgGraph -Scopes 'Application.ReadWrite.All' -TenantId $TenantId
    }
    catch {
        throw "An issue occured during the Azure graph connection phase. Connecting to Azure graph failed with error: $_"
    }
    #endregion

    #region App registration creation
    Write-Host "`n>> Application creation <<" -ForegroundColor Cyan
    try {
        $CSPApplication = Get-MgApplication -Filter "DisplayName eq '$CSPApplicationDisplayName'"
        if ($CSPApplication) {
            Write-Output "The application with display name [$CSPApplicationDisplayName] already exists."
            Write-Output "No reconfiguration of the existing application will be executed. If you need to correct a misconfiguration. Please remove the existing application completely and rerun the process."
        }
        else {
            $RequiredResourceAccess = @(
                @{
                    ResourceAppId  = '797f4846-ba00-4fd7-ba43-dac1f8f63013' # Microsoft Azure Management
                    ResourceAccess = @(
                        @{
                            Id   = '41094075-9dad-400e-a0bd-54e686782033'
                            Type = 'Scope'
                        }
                    )
                },
                @{
                    ResourceAppId  = 'fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd' # Microsoft Partner
                    ResourceAccess = @(
                        @{
                            Id   = '1cebfa2a-fb4d-419e-b5f9-839b4383e05a'
                            Type = 'Scope'
                        }
                    )
                }
            )
            $CSPApplication = New-MgApplication -DisplayName $CSPApplicationDisplayName -RequiredResourceAccess $RequiredResourceAccess -SignInAudience AzureADMultipleOrgs -Web @{RedirectUris = @('http://localhost:4200') }
        }
    }
    catch {
        throw "An issue occured during the application creation phase. The returned error was: $_ "
    }
    #endregion

    #region Output
    Write-Output "Created application details are:`n    > Application id: $($CSPApplication.Id)`n    > DisplayName: $($CSPApplication.DisplayName)"
    #endregion

    Write-Output "`nIn order to use your new application in the data retrieval flow please create an application secret in the Azure portal. For more information on how to do this see [https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#option-2-create-a-new-application-secret] or our documentation at [https://github.com/dexmach/azure-csp-securescore]."
    Write-Host "`n>> The prerequisites flow has finished <<" -ForegroundColor Green
}

function Start-CSPSecureScoreDataProcess {
    #region Local environment configuration
    Write-Host "`n>> Local environment configuration <<" -ForegroundColor Cyan

    $RequiredModules = @(
        @{
            ModuleName      = 'PartnerCenter'
            RequiredVersion = '3.0.10'
        }
    )
    Install-RequiredModules -RequiredModulesList $RequiredModules

    Write-Output "[Configuration] Initializing process variables."
    $CSP_Partner_TenantId = "common" # You can use 'common' to support any CSP partner tenant by having AAD default to the authenticated user's home tenant.
    do {
        $CSP_Partner_SpnId = (Read-Host -Prompt "Provide the application id of your Azure AD multi-tenant application that you wish to use for the data retrieval process. Please use flow 1 to create this application or refer to the documentation for the required permissions").TrimEnd().TrimStart()
        if (-not $CSP_Partner_SpnId) {
            Write-Host "No input was provided. Please try again."
        }
    }
    while (-not $CSP_Partner_SpnId)
    Write-Output "[Configuration] Requesting CSP partner SPN secret from the user.."
    # The SPN used must have delegated (user permissions) for the provided scope
    $CSP_Partner_SpnSecret = Read-Host -Prompt "Provide the secret for the service principal with id [$CSP_Partner_SpnId] and press 'Enter'." -AsSecureString
    $CSP_Partner_Credential = [PSCredential]::new($CSP_Partner_SpnId, $CSP_Partner_SpnSecret)
    if (-not ($CSP_Partner_Credential.GetNetworkCredential().Password)) {
        throw "No value was provided in the prompt for the CSP partner SPN secret. Please execute the process again with a valid prompt input."
    }
    #endregion

    #region Partner center connection
    Write-Host "`n>> Partner center connection <<" -ForegroundColor Cyan
    Write-Output "[Token] Requesting the user to log in with their CSP user account.. Authenticate through the pop-up window to proceed with the process."
    # An interactive window will pop up and you will be requested to log in. Do so with an account that has the required access as described in the repository readme. (AdminAgent or HelpDeskAgent)
    #   The token retrieved from this process can now be used to authenticate to the partner center API and to fetch additional tokens for other Microsoft services like ARM
    try {
        $PartnerTokenObject = @{
            ApplicationId        = $CSP_Partner_SpnId
            Credential           = $CSP_Partner_Credential
            Scopes               = "https://api.partnercenter.microsoft.com/user_impersonation"
            ServicePrincipal     = $true
            TenantId             = $CSP_Partner_TenantId
            UseAuthorizationCode = $true
        }
        $PartnerToken = New-PartnerAccessToken @PartnerTokenObject -ErrorAction 'Stop' -WarningAction 'SilentlyContinue'

        $CSPTokenObject = @{
            Method      = 'Post'
            Uri         = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
            Body        = @{
                client_id     = $PartnerTokenObject.ApplicationId
                client_info   = '1'
                client_secret = $PartnerTokenObject.Credential.GetNetworkCredential().Password
                scope         = "https://api.partnercenter.microsoft.com/user_impersonation"
                grant_type    = "refresh_token"
                refresh_token = $PartnerToken.RefreshToken
            }
            ContentType = 'application/x-www-form-urlencoded'
            Headers     = @{
                Accept = 'application/json'
            }
        }
        $CSPToken = Invoke-RestMethod @CSPTokenObject -ErrorAction 'Stop'
    }
    catch {
        throw "An issue occured during the partner center connection phase. The retrieved error of the attempted partner token retrieval was: $_"
    }

    Write-Output "[Partner center] Connecting to partner center."
    try {
        $PartnerCenterObject = @{
            ApplicationId = $CSP_Partner_SpnId
            Credential    = $CSP_Partner_Credential
            RefreshToken  = $PartnerToken.RefreshToken
        }
        $null = Connect-PartnerCenter @PartnerCenterObject
    }
    catch {
        throw "An issue occured during the partner center connection phase. The retrieved error of the attempted connection was: $_"
    }

    Write-Output "[Partner center] Retrieving partner customers.."
    try {
        $CustomerList = Get-PartnerCustomer
    }
    catch {
        throw "An issue occured during the partner center connection phase. The retrieved error of the attempted retrieval of customers was: $_"
    }
    Write-Output "[Partner center] A total of [$($CustomerList.Count)] customers have been found on partner center."
    #endregion

    #region Retrieving Azure customers
    Write-Host "`n>> Getting all Azure Customers <<" -ForegroundColor Cyan
    Write-Output "[Azure Customers] Getting all the Azure Customers from the Partner Customers.."

    $CustomerSubscriptionList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $DataRetrievalPrerequisitesIssueList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $CustomerList | ForEach-Object -ThrottleLimit 50 -Parallel {
        $CustomerObject = @{
            CustomerId = $_.CustomerId
            Domain     = $_.Domain
        }
        $IssueDict = $using:DataRetrievalPrerequisitesIssueList
        try {
            $Uri = "https://api.partnercenter.microsoft.com/v1/customers/$($_.CustomerId)/subscriptions"
            $Token = $using:PartnerToken.AccessToken
            $CustomerSubscriptionDict = $using:CustomerSubscriptionList
            $SubscriptionsResult = (Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token (ConvertTo-SecureString -AsPlainText -Force -String $Token)).items
            foreach ($subscription in $SubscriptionsResult) {
                $subscription | Add-Member -NotePropertyName 'CustomerId' -NotePropertyValue $_.CustomerId
                $null = $CustomerSubscriptionDict.TryAdd($subscription.id, $subscription)
            }
        }
        catch {
            $null = $IssueDict.TryAdd("$($CustomerObject.CustomerId)_CustomerSubscription", @(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'CustomerSubscriptionRetrieval'
                        Issue      = "An issue occured during the check if customers are azure customers phase for one of the customers. The retrieval of the subscriptions of customer with id [$($CustomerObject.CustomerId)] and domain [$($CustomerObject.Domain)] failed with error: $_"
                    }))
        }
    }
    $CustomerSubscriptionList = $CustomerSubscriptionList.Values
    # Create a list of Azure customers by checking if the customer id is present in one of the customer subscriptions
    $AzureCustomerList = $CustomerList | Where-Object { $_.CustomerId -in $($CustomerSubscriptionList | Where-Object { $_.OfferName -like '*azure*' }).CustomerId }
    $AzureCustomerListCount = $AzureCustomerList.count
    Write-Output "[Azure Customers] A total of [$AzureCustomerListCount] Azure customers have been found on partner center."
    #endregion

    #region Deploy SPN to partner customers who are Azure Customers
    Write-Host "`n>> SPN consent on partner customers <<" -ForegroundColor Cyan
    Write-Output "[SPN consent] Granting admin consent for multi-tenant SPN for all [$AzureCustomerListCount] Azure customers.."

    $AzureCustomerList | ForEach-Object -ThrottleLimit 50 -Parallel {
        $CustomerObject = @{
            CustomerId = $_.CustomerId
            Domain     = $_.Domain
        }
        $IssueDict = $using:DataRetrievalPrerequisitesIssueList
        try {
            $Body = @{
                ApplicationGrants = @(
                    @{
                        EnterpriseApplicationId = '797f4846-ba00-4fd7-ba43-dac1f8f63013' # Microsoft Azure Management
                        Scope                   = 'user_impersonation'
                    }
                )
                ApplicationId     = $using:CSP_Partner_SpnId
                DisplayName       = 'DexMach CSP Secure Score dashboard'
            }
            $Uri = "https://api.partnercenter.microsoft.com/v1/customers/$($_.CustomerId)/applicationconsents"
            $null = Invoke-RestMethod -Method 'Post' -Uri $Uri -Body ($Body | ConvertTo-Json) -Authentication 'Bearer' -Token (ConvertTo-SecureString -AsPlainText -Force -String $using:CSPToken.access_token) -ContentType 'application/json' -ErrorAction 'Stop'
        }
        catch {
            if ($_ -match 'Permission entry already exists') {
                Write-Verbose " > The application consent for application id [$using:CSP_Partner_SpnId] and customer id [$($CustomerObject.CustomerId)] already exists. This is the target so process continues.."
            }
            else {
                $null = $IssueDict.TryAdd("$($CustomerObject.CustomerId)_Consent", @(@{
                            CustomerId = $CustomerObject.CustomerId
                            Domain     = $CustomerObject.Domain
                            Category   = 'ApplicationConsent'
                            Issue      = "An issue occured during the SPN consent phase. The automated call to consent the mission 65 application to the customer tenant with id [$($CustomerObject.CustomerId)] and domain [$($CustomerObject.Domain)] failed with error: $_"
                        }))
            }
        }
    }
    #endregion

    #region Retrieving more detailed partner center customer information
    Write-Host "`n>> Partner center customer details <<" -ForegroundColor Cyan
    Write-Output "[Customer details] Retrieving partner center customer details.."

    $DetailedCustomerList = [System.Collections.ArrayList]@()
    $DetailedCustomerList = $AzureCustomerList | ForEach-Object -ThrottleLimit 50 -Parallel {
        $CustomerObject = @{
            CustomerId = $_.CustomerId
            Domain     = $_.Domain
        }
        $IssueDict = $using:DataRetrievalPrerequisitesIssueList
        try {
            $Uri = "https://api.partnercenter.microsoft.com/v1/customers/$($_.CustomerId)"
            Invoke-RestMethod -Method 'Get' -Uri $Uri -Authentication 'Bearer' -Token (ConvertTo-SecureString -AsPlainText -Force -String $using:PartnerToken.AccessToken) -ErrorAction 'Stop'
        }
        catch {
            $null = $IssueDict.TryAdd("$($CustomerObject.CustomerId)_CustomerDetail", @(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'CustomerDetailRetrieval'
                        Issue      = "An issue occured during the partner center customer details phase. The retrieval of the detailed information of customer with id [$($CustomerObject.CustomerId)] and domain [$($CustomerObject.Domain)] failed with error: $_"
                    }))
        }
    }
    $DataRetrievalPrerequisitesIssueList = $DataRetrievalPrerequisitesIssueList.Values
    #endregion

    #region Retrieving Azure information
    Write-Host "`n>> Azure data retrieval <<" -ForegroundColor Cyan
    $AzureSubscriptionList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $SecureScoreList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $SecureScoreControlList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $DataRetrievalIssueList = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    Write-Output "[Azure data] Retrieving Azure data."
    $AzureCustomerList | ForEach-Object -ThrottleLimit 50 -Parallel {
        $CustomerObject = @{
            CustomerId         = $_.CustomerId
            Domain             = $_.Domain
            SubscriptionIssues = [System.Collections.ArrayList]@()
        }
        $SecureScoreDict = $using:SecureScoreList
        $SecureScoreControlDict = $using:SecureScoreControlList
        $AzureSubscriptionDict = $using:AzureSubscriptionList
        $IssueDict = $using:DataRetrievalIssueList
        try {
            $CSP_Partner_Credential = $using:CSP_Partner_Credential
            $Body = @{
                grant_type    = 'refresh_token'
                client_id     = $using:CSP_Partner_SpnId
                client_secret = $CSP_Partner_Credential.GetNetworkCredential().Password
                refresh_token = $using:PartnerToken.RefreshToken
                scope         = 'https://management.azure.com/user_impersonation'
            }
            $CustomerARMToken = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($CustomerObject.CustomerId)/oauth2/v2.0/token" -Method 'Post' -Body $Body -ErrorAction 'Stop'
            if ($null -eq $CustomerARMToken.Access_Token) {
                $null = $IssueDict.TryAdd($CustomerObject.CustomerId, @(@{
                            CustomerId = $CustomerObject.CustomerId
                            Domain     = $CustomerObject.Domain
                            Category   = 'EmptyARMToken'
                            Issue      = "Skipping the customer with domain name [$($CustomerObject.Domain)] due to the inability to retrieve a partner access token scoped on the ARM API. No token was retrieved from the attempted call."
                        }))
                continue
            }
            $Headers = @{
                Authorization = "Bearer $($CustomerARMToken.Access_Token)"
            }
        }
        catch {
            $null = $IssueDict.TryAdd($CustomerObject.CustomerId, @(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'FailedARMTokenRetrieval'
                        Issue      = "An issue occured during the Azure data retrieval phase. The retrieved error of the attempted partner token retrieval for customer with domain [$($CustomerObject.Domain)] and id [$($CustomerObject.CustomerId)] for ARM scope was: $_"
                    }))
            continue
        }
        try {
            $CustomerAzureSubscriptionList = Invoke-RestMethod -Headers $Headers -Method GET -UseBasicParsing -Uri 'https://management.azure.com/subscriptions?api-version=2020-01-01' -ContentType "application/json" -Verbose:$false
        }
        catch {
            $null = $IssueDict.TryAdd($CustomerObject.CustomerId, @(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'SubscriptionListRetrieval'
                        Issue      = "An issue occured during the Azure data retrieval phase. Retrieving a list of Azure subscriptions for customer with domain [$($customer.Domain)] did not succeed. The returned error was: $_"
                    }))
            continue
        }
        foreach ($subscription in $CustomerAzureSubscriptionList.value) {
            $null = $AzureSubscriptionDict.TryAdd($subscription.id, $subscription)
            try {
                $SecureScore = Invoke-RestMethod -Headers $Headers -Method GET -UseBasicParsing -Uri "https://management.azure.com/subscriptions/$($subscription.SubscriptionId)/providers/Microsoft.Security/secureScores?api-version=2020-01-01-preview" -ContentType "application/json" -Verbose:$false
                if ($SecureScore.value.count -gt 0) {
                    $null = $SecureScoreDict.TryAdd($SecureScore.value[0].id, $secureScore.value[0])
                }
            }
            catch {
                $null = $CustomerObject.SubscriptionIssues.Add(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'SecureScoreRetrieval'
                        Issue      = "An issue occured during the Azure data retrieval phase. Retrieving the secure score of subscription [$($subscription.SubscriptionId)] for customer with domain [$($customer.Domain)] did not succeed. The returned error was: $_"
                    })
            }
            try {
                $SecureScoreControls = Invoke-RestMethod -Headers $Headers -Method GET -UseBasicParsing -Uri "https://management.azure.com/subscriptions/$($subscription.SubscriptionId)/providers/Microsoft.Security/secureScoreControls?api-version=2020-01-01" -ContentType "application/json" -Verbose:$false
                foreach ($secureScoreControl in $SecureScoreControls.value) {
                    $null = $SecureScoreControlDict.TryAdd($secureScoreControl.id, $secureScoreControl)
                }
            }
            catch {
                $null = $CustomerObject.SubscriptionIssues.Add(@{
                        CustomerId = $CustomerObject.CustomerId
                        Domain     = $CustomerObject.Domain
                        Category   = 'SecureScoreControlRetrieval'
                        Issue      = "An issue occured during the Azure data retrieval phase. Retrieving the secure score controls of subscription [$($subscription.SubscriptionId)] for customer with domain [$($customer.Domain)] did not succeed. The returned error was: $_"
                    })
            }
            if ($CustomerObject.SubscriptionIssues) {
                $null = $IssueDict.TryAdd($CustomerObject.CustomerId, $CustomerObject.SubscriptionIssues)
            }
        }
    }
    $AzureSubscriptionList = $AzureSubscriptionList.Values
    $SecureScoreList = $SecureScoreList.Values
    $SecureScoreControlList = $SecureScoreControlList.Values
    $DataRetrievalIssueList = $DataRetrievalIssueList.Values
    #endregion

    #region Output
    Write-Host "`n>> Data output <<" -ForegroundColor Cyan
    Write-Output "[Output] Writing the required files to disk in the directory this script is executed.."
    function Write-CSPObjectToFile {
        [cmdletbinding()]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [array]$InputObjectList,

            [Parameter(Mandatory = $true)]
            [string]$OutputFolderName,

            [Parameter(Mandatory = $true)]
            [string]$OutputFileName
        )
        try {
            $null = New-Item -Path "./data" -ItemType Directory -Force
            $null = New-Item -Path "./data/$OutputFolderName" -ItemType Directory -Force
            if ($InputObjectList.Count -gt 0) {
                ConvertTo-Json -InputObject $InputObjectList -Depth 100 | Out-File "data/$OutputFolderName/$OutputFileName" -Force
            }
            else {
                "File [$OutputFileName] was empty"
            }
        }
        catch {
            throw "An issue occured during the data output phase. The output of the requested file with name [$OutputFileName] has failed with error: $_"
        }
    }
    $DateTimeFolderName = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
    Write-CSPObjectToFile -InputObjectList $CustomerList -OutputFolderName $DateTimeFolderName -OutputFileName 'Customers.json'
    Write-CSPObjectToFile -InputObjectList $DetailedCustomerList -OutputFolderName $DateTimeFolderName -OutputFileName 'Customerdetails.json'
    Write-CSPObjectToFile -InputObjectList $CustomerSubscriptionList -OutputFolderName $DateTimeFolderName -OutputFileName 'CustomerSubscriptions.json'
    Write-CSPObjectToFile -InputObjectList $AzureSubscriptionList -OutputFolderName $DateTimeFolderName -OutputFileName 'AzureSubscriptions.json'
    Write-CSPObjectToFile -InputObjectList $SecureScoreList -OutputFolderName $DateTimeFolderName -OutputFileName 'SecureScores.json'
    Write-CSPObjectToFile -InputObjectList $SecureScoreControlList -OutputFolderName $DateTimeFolderName -OutputFileName 'SecureScoreControls.json'
    if ($DataRetrievalPrerequisitesIssueList) {
        Write-CSPObjectToFile -InputObjectList $DataRetrievalPrerequisitesIssueList -OutputFolderName "$DateTimeFolderName/issues" -OutputFileName 'DataRetrievalPrerequisitesIssues.json'
    }
    if ($DataRetrievalIssueList) {
        Write-CSPObjectToFile -InputObjectList $DataRetrievalIssueList -OutputFolderName "$DateTimeFolderName/issues" -OutputFileName 'DataRetrievalIssues.json'
    }
    #endregion

    Write-Host "`n>> The CSP data retrieval process has finished <<" -ForegroundColor Green
    Write-Output "Find your files in the 'data' folder under the directory from which you executed this script."
    Write-Output "For feedback or questions go to [https://github.com/dexmach-csp/azure-csp-securescore/issues]."
}

function Start-CSPSecureScoreDataUpload {
    #region Local environment configuration
    Write-Host "`n>> Local environment configuration <<" -ForegroundColor Cyan
    $RequiredModules = @(
        @{
            ModuleName      = 'Az.Accounts'
            RequiredVersion = '2.11.0'
        },
        @{
            ModuleName      = 'Az.Storage'
            RequiredVersion = '5.3.0'
        },
        @{
            ModuleName      = 'Az.Resources'
            RequiredVersion = '6.5.1'
        }
    )
    Install-RequiredModules -RequiredModulesList $RequiredModules
    #endregion

    #region Storage account processes
    function Start-StorageAccountDefaultProcess {
        #region Azure connection
        Write-Host "`n>> Azure connection <<" -ForegroundColor Cyan
        do {
            $TenantId = (Read-Host -Prompt "Provide the tenant id of your Azure tenant in which you want to upload your files").TrimEnd().TrimStart()
            if (-not $TenantId) {
                Write-Host "No input was provided. Please try again."
            }
        }
        while (-not $TenantId)
        do {
            $SubscriptionId = (Read-Host -Prompt "Provide the subscription id of your Azure subscription in which you want to upload your files").TrimEnd().TrimStart()
            if (-not $SubscriptionId) {
                Write-Host "No input was provided. Please try again."
            }
        }
        while (-not $SubscriptionId)
        try {
            $null = Connect-AzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId
        }
        catch {
            throw "An issue occured during the Azure connection phase. Connecting to Azure failed with error: $_"
        }
        #endregion

        #region User prompts
        Write-Host "`n>> User prompts <<" -ForegroundColor Cyan
        do {
            $ResourceGroupName = (Read-Host -Prompt "Provide the resource group name in which you want to create the storage account").TrimEnd().TrimStart()
            if (-not $ResourceGroupName) {
                Write-Host "No input was provided. Please try again."
            }
        }
        while (-not $ResourceGroupName)
        do {
            $StorageAccountName = (Read-Host -Prompt "Provide the name of the storage account that you wish to create. Maximum 24 characters are allowed").TrimEnd().TrimStart()
            if (-not $StorageAccountName) {
                Write-Host "No input was provided. Please try again."
            }
            elseif ($StorageAccountName.Length -gt 24) {
                Write-Host "Input was invalid. More than 24 characters were provided. Please try again with another name."
                $StorageAccountName = $null
            }
        }
        while (-not $StorageAccountName)
        do {
            $DataFolderPath = (Read-Host -Prompt "Provide the full folder path of the data folder from which you want to upload your data. This folder is created by the data retrieval process").TrimEnd().TrimStart()
            if (-not $DataFolderPath) {
                Write-Host "No input was provided. Please try again."
            }
            elseif (-not (Resolve-Path -Path $DataFolderPath -ErrorAction 'SilentlyContinue')) {
                Write-Host "Input was invalid. The provided path could not be resolved. Please try again with a correct folder path."
                $DataFolderPath = $null
            }
            elseif (-not (Get-ChildItem -Path $DataFolderPath -Recurse -File -Filter '*.json')) {
                Write-Host "Input was invalid. No json files were found under the provided path. Please try again with a correct folder path."
                $DataFolderPath = $null
            }
        }
        while (-not $DataFolderPath)
        Write-Host "`nProvided inputs:`n    > Resource group name [$ResourceGroupName]`n    > Storage account name [$StorageAccountName]`n    > Data folder path [$DataFolderPath]`n      All files in this folder will be uploaded for visualization"
        #endregion
        @{
            ResourceGroupName  = $ResourceGroupName
            StorageAccountName = $StorageAccountName
            DataFolderPath     = $DataFolderPath
        }
    }
    function Start-StorageAccountCreationProcess {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$StorageAccountName
        )
        #region Storage account creation
        Write-Host "`n>> Storage account creation <<" -ForegroundColor Cyan
        try {
            $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction 'SilentlyContinue'
            if (-not $ResourceGroup) {
                Write-Output "The provided resource group [$ResourceGroupName] did not exist yet. Creating.."
                $null = New-AzResourceGroup -Name $ResourceGroupName -Location 'westeurope'
            }
            else {
                Write-Output "The provided resource group [$ResourceGroupName] already exists. Using this resource group for the next steps."
            }
        }
        catch {
            throw "An issue occured during the resource group creation step for the provided name [$ResourceGroupName]. The returned error was: $_"
        }
        try {
            $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction 'SilentlyContinue'
            if (-not $StorageAccount) {
                Write-Output "The provided storage account [$StorageAccountName] did not exist yet. Creating.."
                $StorageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName 'Standard_LRS' -Location 'westeurope'
            }
            else {
                Write-Output "The provided storage account [$StorageAccountName] already exists. Using this resource for the next steps."
            }
        }
        catch {
            throw "An issue occured during the storage account creation step for the provided name [$StorageAccountName] within resource group [$ResourceGroupName]. The returned error was: $_"
        }
        #endregion
    }
    function Start-StorageAccountUploadProcess {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$StorageAccountName,

            [Parameter(Mandatory = $true)]
            [ValidateScript({ Resolve-Path -Path $_ })]
            [string]$DataFolderPath
        )
        Write-Host "`n>> CSP data upload <<" -ForegroundColor Cyan
        try {
            Write-Output "Retrieving the storage account key.."
            $StorageAccountKey = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
            if (-not $StorageAccountKey) {
                throw "No storage account key was able to be retrieved."
            }
            Write-Output "Creating storage context.."
            $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey ($StorageAccountKey)[0].Value
            try {
                $ContainerName = 'azure-csp-securescore'
                Write-Output "Creating storage container [$ContainerName].."
                $null = New-AzStorageContainer -Name $ContainerName -Permission Off -Context $StorageContext
                Write-Output "Pushing your data.."
            }
            catch {
                if ($_.Exception.Message -match "Container '$ContainerName' already exists") {
                    Write-Output "Container [$ContainerName] already exists. Pushing your data.."
                }
                else {
                    throw $_
                }
            }
            foreach ($folder in (Get-ChildItem -Path $DataFolderPath -Directory)) {
                foreach ($file in (Get-ChildItem -Path $folder.FullName -Filter '*.json')) {
                    try {
                        $null = Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Blob "$($folder.Name)\$($file.Name)" -Context $StorageContext -Force
                        Write-Output "  > File [$($folder.Name)\$($file.Name)] was uploaded."
                    }
                    catch {
                        throw "File on location [$($file.FullName)] could not be uploaded. Azure returned the following error: $_"
                    }
                }
            }
        }
        catch {
            throw "Uploading your data files did not succeed. The returned error was: $_"
        }
    }
    #endregion

    #region Storage account process selection
    $StorageAccountFlowMenu = @"
`nPlease choose one of the options for uploading data to an Azure storage account. For help and more detailed info during the process refer to the documentation at [https://github.com/dexmach/azure-csp-securescore].
After process execution, reinitiate the script if you want to execute other processes.

1 - Upload to an existing storage account.
        You will be prompted for details of an existing storage account. Your files will be published to a CSP secure score container.
2 - Create a new storage account and upload your data.
        Contributor access to an Azure subscription is needed. After providing resource details the storage account will be created for you with your latest data.
q - Quit the process
`n
"@
    Write-Host "`n>> Storage account flow menu <<" -ForegroundColor Cyan
    Write-Host $StorageAccountFlowMenu

    $ValidatedInput = $false
    do {
        $UserInput = Read-Host "Enter your process choice [1 - 2 - q]"
        switch ($UserInput) {
            1 {
                Write-Output " > Starting process [$UserInput. Upload to an existing storage account]"
                $StorageDetailsObject = Start-StorageAccountDefaultProcess
                Start-StorageAccountUploadProcess -ResourceGroupName $StorageDetailsObject.ResourceGroupName -StorageAccountName $StorageDetailsObject.StorageAccountName -DataFolderPath $StorageDetailsObject.DataFolderPath
                Write-Output "Your files are now located in the storage account that you provided. Link this storage account to the requested parameters of the Power BI dashboard to view your data."
                $ValidatedInput = $true
            }
            2 {
                Write-Output " > Starting process [$UserInput. Create a new storage account and upload your data]"
                $StorageDetailsObject = Start-StorageAccountDefaultProcess
                Start-StorageAccountCreationProcess -ResourceGroupName $StorageDetailsObject.ResourceGroupName -StorageAccountName $StorageDetailsObject.StorageAccountName
                Start-StorageAccountUploadProcess -ResourceGroupName $StorageDetailsObject.ResourceGroupName -StorageAccountName $StorageDetailsObject.StorageAccountName -DataFolderPath $StorageDetailsObject.DataFolderPath
                Write-Output "Your files are now located in the storage account that you provided. Link this storage account to the requested parameters of the Power BI dashboard to view your data."
                $ValidatedInput = $true
            }
            'q' {
                Write-Output "You chose to quit the process. Until next time."
                $ValidatedInput = $true
            }
            default {
                Write-Output "Invalid input, Please try again"
            }
        }
    }
    while ($ValidatedInput -eq $false)
    #endregion

    Write-Host "`n>> The upload data flow has finished <<" -ForegroundColor Green
}
#endregion

#region Menu functionality and execution
$Banner = @"
 ____            __  __            _
|  _ \  _____  _|  \/  | __ _  ___| |__
| | | |/ _ \ \/ / |\/| |/ _`` |/ __| '_ \
| |_| |  __/>  <| |  | | (_| | (__| | | |
|____/ \___/_/\_\_|  |_|\__,_|\___|_| |_|

Welcome to the DexMach CSP secure score data retrieval project!
"@

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "Running PowerShell version 7 or later is a requirement for this script. The current version [$($PSVersionTable.PSVersion.ToString())] does not support functionalities that is used later in this script. Please open a PowerShell 7 runtime and execute again."
}
if ((Get-ExecutionPolicy) -ne 'Unrestricted') {
    write-Warning "Run this script under execution policy 'Unrestricted' to allow uninterrupted module installation. For more information to set this see [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.3]."
}

Write-Host $Banner -ForegroundColor Green

$Menu = @"
`nPlease choose the process that you want to initiate. For help and more detailed info during the process refer to the documentation at [https://github.com/dexmach-csp/azure-csp-securescore].
After process execution, reinitiate the script if you want to execute again.

1 - Start prerequisites flow.
        An Azure AD multi-tenant application will be created in your authenticated tenant. This application can be used in the data retrieval process.
2 - Start data retrieval flow.
        Provide credentials for a multi-tenant app and log in with a CSP portal administrator. The process will do the rest and provide you with data files to link to our Power BI insights.
3 - Upload local data for visualization
        Send your local files to an Azure storage account from where your files can be used by the PowerBI dashboard.
q - Quit the process
`n
"@
Write-Host $Menu

$ValidatedInput = $false
do {
    $UserInput = Read-Host "Enter your process choice [1 - 2 - 3 - q]"
    switch ($UserInput) {
        1 {
            Write-Output " > Starting process [$UserInput. Prerequisites flow]"
            Start-CSPSecureScorePrerequisitesProcess
            $ValidatedInput = $true
        }
        2 {
            Write-Output " > Starting process [$UserInput. Data retrieval flow]"
            Start-CSPSecureScoreDataProcess
            $ValidatedInput = $true
        }
        3 {
            Write-Output " > Starting process [$UserInput. Upload local data for visualization]"
            Start-CSPSecureScoreDataUpload
            $ValidatedInput = $true
        }
        'q' {
            Write-Output "You chose to quit the process. Until next time."
            $ValidatedInput = $true
        }
        default {
            Write-Output "Invalid input, Please try again"
        }
    }
}
while ($ValidatedInput -eq $false)
#endregion
