param ($TenantID,
        $Appid,
        $SubscriptionID,
        $Secret, 
        $ResourceGroup, 
        [switch]$Online, 
        [switch]$Debug, 
        [switch]$SkipMetrics, 
        [switch]$SkipConsumption, 
        [switch]$Help,
        [switch]$DeviceLogin,
        [switch]$EnableLogs,
        $ConcurrencyLimit = 6,
        $AzureEnvironment,
        $ReportName = 'ResourcesReport', 
        $OutputDirectory)


if ($Debug.IsPresent) {$DebugPreference = 'Continue'}

if ($Debug.IsPresent) {$ErrorActionPreference = "Continue" }Else {$ErrorActionPreference = "silentlycontinue" }

Write-Debug ('Debbuging Mode: On. ErrorActionPreference was set to "Continue", every error will be presented.')

Function Write-Log([string]$Message, [string]$Severity)
{
   $DateTime = "[{0:dd-MM-yyyy} {0:HH:mm:ss}]" -f (Get-Date)

   if($EnableLogs.IsPresent)
   {
        $Global:Logging.Logs.Add([PSCustomObject]@{ Date = $DateTime; Message = $Message; Severity = $Severity })
   }

   switch ($Severity) 
   {
        "Info"    { Write-Host $Message -ForegroundColor Cyan }
        "Warning" { Write-Host $Message -ForegroundColor Yellow }
        "Error"   { Write-Host $Message -ForegroundColor Red }
        "Success"   { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

function GetLocalVersion() {
    $versionJsonPath = "./Version.json"
    if (Test-Path $versionJsonPath) 
    {
        $localVersionJson = Get-Content $versionJsonPath | ConvertFrom-Json
        return ('{0}.{1}.{2}' -f $localVersionJson.MajorVersion, $localVersionJson.MinorVersion, $localVersionJson.BuildVersion)
    } 
    else 
    {
        Write-Host "Local Version.json not found. Clone the repo and execute the script from the root. Exiting." -ForegroundColor Red
        Exit
    }
}

function Variables 
{
    $Global:ResourceContainers = @()
    $Global:Resources = @()
    $Global:Subscriptions = ''
    $Global:ReportName = $ReportName   
    $Global:Version = GetLocalVersion

    $Global:Logging = New-Object PSObject
    $Global:Logging | Add-Member -MemberType NoteProperty -Name Logs -Value NotSet
    $Global:Logging.Logs = [System.Collections.Generic.List[object]]::new()

    if ($Online.IsPresent) { $Global:RunOnline = $true }else { $Global:RunOnline = $false }

    $Global:Repo = 'https://api.github.com/repos/stefoy/AriPlus/git/trees/main?recursive=1'
    $Global:RawRepo = 'https://raw.githubusercontent.com/stefoy/AriPlus/main'

    $Global:TableStyle = "Medium15"

    Write-Debug ('Checking if -Online parameter will have to be forced.')

    if(!$Online.IsPresent)
    {
        if($PSScriptRoot -like '*\*')
        {
            $LocalFilesValidation = New-Object System.IO.StreamReader($PSScriptRoot + '\Extension\Metrics.ps1')
        }
        else
        {
            $LocalFilesValidation = New-Object System.IO.StreamReader($PSScriptRoot + '/Extension/Metrics.ps1')
        } 

        if([string]::IsNullOrEmpty($LocalFilesValidation))
        {
            Write-Debug ('[Info] - Using -Online by force.')
            $Global:RunOnline = $true
        }
        else
        {
            $Global:RunOnline = $false
        }
    }
}

Function RunInventorySetup()
{
    function CheckAriVersion()
    {
        Write-Log -Message ('Checking ARI Plus Version') -Severity 'Info'
        Write-Log -Message ('ARI Plus Version: {0}' -f $Global:Version) -Severity 'Info'
        
        $versionJson = (New-Object System.Net.WebClient).DownloadString($RawRepo + '/Version.json') | ConvertFrom-Json
        $versionNumber = ('{0}.{1}.{2}' -f $versionJson.MajorVersion, $versionJson.MinorVersion, $versionJson.BuildVersion)

        if($versionNumber -ne $Global:Version)
        {
            Write-Log -Message ('New Version Available: {0}.{1}.{2}' -f $versionJson.MajorVersion, $versionJson.MinorVersion, $versionJson.BuildVersion) -Severity 'Warning'
            Write-Log -Message ('Download or Clone the latest version and run again: https://github.com/stefoy/AriPlus/tree/main') -Severity 'Error'
            Exit
        }
    }

    function CheckCliRequirements() 
    {        
        Write-Log -Message ('Verifying Azure CLI is installed...') -Severity 'Info'

        $azCliVersion = az --version

        Write-Log -Message ('CLI Version: {0}' -f $azCliVersion[0]) -Severity 'Success'
    
        if ($null -eq $azCliVersion) 
        {
            Read-Host "Azure CLI Not Found. Please install to and run the script again, press <Enter> to exit." -ForegroundColor Red
            Exit
        }

        Write-Log -Message ('Verifying Azure CLI Extension...') -Severity 'Info'

        $azCliExtension = az extension list --output json | ConvertFrom-Json
        $azCliExtension = $azCliExtension | Where-Object {$_.name -eq 'resource-graph'}

        Write-Log -Message ('Current Resource-Graph Extension Version: {0}' -f $azCliExtension.Version) -Severity 'Success'
        
        $azCliExtensionVersion = $azcliExt | Where-Object {$_.name -eq 'resource-graph'}
    
        if (!$azCliExtensionVersion) 
        {
            Write-Log -Message ('Azure CLI Extension not found') -Severity 'Warning'
            Write-Log -Message ('Installing Azure CLI Extension...') -Severity 'Info'
            az extension add --name resource-graph
        }

        Write-Log -Message ('Checking Azure PowerShell Module...') -Severity 'Info'

        $VarAzPs = Get-InstalledModule -Name Az -ErrorAction silentlycontinue

        Write-Log -Message ('Azure PowerShell Module Version: {0}.{1}.{2}' -f [string]$VarAzPs.Version.Major,  [string]$VarAzPs.Version.Minor, [string]$VarAzPs.Version.Build) -Severity 'Success'

        IF($null -eq $VarAzPs)
        {
            Write-Log -Message ('Trying to install Azure PowerShell Module...') -Severity 'Warning'
            Install-Module -Name Az -Repository PSGallery -Force
        }

        $VarAzPs = Get-InstalledModule -Name Az -ErrorAction silentlycontinue

        if ($null -eq $VarAzPs) 
        {
            Write-Log -Message ('Admininstrator rights required to install Azure PowerShell Module. Press <Enter> to finish script') -Severity 'Error'
            Read-Host ''
            Exit
        }
        

        Write-Log -Message ('Checking ImportExcel Module...') -Severity 'Info'
    
        $VarExcel = Get-InstalledModule -Name ImportExcel -ErrorAction silentlycontinue
    
        Write-Log -Message ('ImportExcel Module Version: {0}.{1}.{2}' -f [string]$VarExcel.Version.Major,  [string]$VarExcel.Version.Minor, [string]$VarExcel.Version.Build) -Severity 'Success'
    
        if ($null -eq $VarExcel) 
        {
            Write-Log -Message ('Trying to install ImportExcel Module...') -Severity 'Warning'
            Install-Module -Name ImportExcel -Force
        }
    
        $VarExcel = Get-InstalledModule -Name ImportExcel -ErrorAction silentlycontinue
    
        if ($null -eq $VarExcel) 
        {
            Write-Log -Message ('Admininstrator rights required to install ImportExcel Module. Press <Enter> to finish script') -Severity 'Error'
            Read-Host ''
            Exit
        }
    }
    
    function CheckPowerShell() 
    {
        Write-Log -Message ('Checking PowerShell...') -Severity 'Info'
    
        $Global:PlatformOS = 'PowerShell Desktop'
        $cloudShell = try{Get-CloudDrive}catch{}

        $Global:CurrentDateTime = (get-date -Format "yyyyMMddHHmm")
        $Global:FolderName = $Global:ReportName + $CurrentDateTime
        
        if ($cloudShell) 
        {
            Write-Log -Message ('Identified Environment as Azure CloudShell') -Severity 'Success'
            $Global:PlatformOS = 'Azure CloudShell'
            $defaultOutputDir = "$HOME/AriPlusReports/" + $Global:FolderName + "/"
        }
        elseif ($PSVersionTable.Platform -eq 'Unix') 
        {
            Write-Log -Message ('Identified Environment as PowerShell Unix') -Severity 'Success'
            $Global:PlatformOS = 'PowerShell Unix'
            $defaultOutputDir = "$HOME/AriPlusReports/" + $Global:FolderName + "/"
        }
        else 
        {
            Write-Log -Message ('Identified Environment as PowerShell Desktop') -Severity 'Success'
            $Global:PlatformOS= 'PowerShell Desktop'
            $defaultOutputDir = "C:\AriPlusReports\" + $Global:FolderName + "\"

            $psVersion = $PSVersionTable.PSVersion.Major
            Write-Log -Message ("PowerShell Version {0}" -f $psVersion) -Severity 'Info'
        
            if ($PSVersionTable.PSVersion.Major -lt 7) 
            {
                Write-Log -Message ("You must use Powershell 7 to run the AriPlus.") -Severity 'Error'
                Write-Log -Message ("https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.3") -Severity 'Error'
                Exit
            }
        }
    
        if ($OutputDirectory) 
        {
            try 
            {
                $OutputDirectory = Join-Path (Resolve-Path $OutputDirectory -ErrorAction Stop) ('/' -or '\')
            }
            catch 
            {
                Write-Log -Message ("Wrong OutputDirectory Path! OutputDirectory Parameter must contain the full path.") -Severity 'Error'
                Exit
            }
        }
    
        $Global:DefaultPath = if($OutputDirectory) {$OutputDirectory} else {$defaultOutputDir}
    
        if ($platformOS -eq 'Azure CloudShell') 
        {
            $Global:Subscriptions = @(az account list --output json --only-show-errors | ConvertFrom-Json)
        }
        elseif ($platformOS -eq 'PowerShell Unix' -or $platformOS -eq 'PowerShell Desktop') 
        {
            LoginSession
        }
    }
    
  function LoginSession() 
    {    
        if(![string]::IsNullOrEmpty($AzureEnvironment))
        {
            az cloud set --name $AzureEnvironment
        }
    
        $CloudEnv = az cloud list | ConvertFrom-Json
        Write-Host "Azure Cloud Environment: " -NoNewline
    
        $CurrentCloudEnvName = $CloudEnv | Where-Object {$_.isActive -eq 'True'}
        Write-Host $CurrentCloudEnvName.name -ForegroundColor Green
    
        if (!$TenantID) 
        {
            Write-Log -Message ('Tenant ID not specified. Use -TenantID parameter if you want to specify directly.') -Severity 'Warning'
            Write-Log -Message ('Authenticating Azure') -Severity 'Info'
    
            Write-Log -Message ('Clearing account cache') -Severity 'Info'
            az account clear | Out-Null
            Write-Log -Message ('Calling Login, the browser will open and prompt you to login.') -Severity 'Info'

            $DebugPreference = "SilentlyContinue"
    
            if($DeviceLogin.IsPresent)
            {
                Write-Log -Message ('Using device login') -Severity 'Info'
                az login --use-device-code
                Connect-AzAccount -UseDeviceAuthentication | Out-Null
            }
            else 
            {
                Write-Log -Message ('Using device login') -Severity 'Info'
                az login --only-show-errors | Out-Null
                Connect-AzAccount | Out-Null
            }

            $DebugPreference = "Continue"
    
            $Tenants = az account list --query [].homeTenantId -o tsv --only-show-errors | Sort-Object -Unique

            Write-Log -Message ('Checking number of Tenants') -Severity 'Info'
    
            if ($Tenants.Count -eq 1) 
            {
                Write-Log -Message ('You have privileges only in One Tenant') -Severity 'Success'
                $TenantID = $Tenants
            }
            else 
            {
                Write-Log -Message ('Select the the Azure Tenant ID that you want to connect: ') -Severity 'Warning'
    
                $SequenceID = 1
                foreach ($TenantID in $Tenants) 
                {
                    write-host "$SequenceID)  $TenantID"
                    $SequenceID ++
                }
    
                [int]$SelectTenant = read-host "Select Tenant (Default 1)"
                $defaultTenant = --$SelectTenant
                $TenantID = $Tenants[$defaultTenant]
    
                if($DeviceLogin.IsPresent)
                {
                    az login --use-device-code -t $TenantID
                    Connect-AzAccount -UseDeviceAuthentication -Tenant $TenantID | Out-Null
                }
                else 
                {
                    az login -t $TenantID --only-show-errors | Out-Null
                    Connect-AzAccount -Tenant $TenantID | Out-Null
                }
            }
    
            Write-Log -Message ("Extracting from Tenant $TenantID") -Severity 'Info'
            Write-Log -Message ("Extracting Subscriptions") -Severity 'Info'
    
            $Global:Subscriptions = @(az account list --output json --only-show-errors | ConvertFrom-Json)
            $Global:Subscriptions = @($Subscriptions | Where-Object { $_.tenantID -eq $TenantID })
        }
        else 
        {
            az account clear | Out-Null
    
            if (!$Appid) 
            {
                if($DeviceLogin.IsPresent)
                {
                    az login --use-device-code -t $TenantID
                    Connect-AzAccount -UseDeviceAuthentication -Tenant $TenantID | Out-Null
                }
                else 
                {
                    az login -t $TenantID --only-show-errors | Out-Null
                    Connect-AzAccount -Tenant $TenantID | Out-Null
                }
            }
            elseif ($Appid -and $Secret -and $tenantid) 
            {
                Write-Log -Message ("Using Service Principal Authentication Method") -Severity 'Success'
                az login --service-principal -u $appid -p $secret -t $TenantID | Out-Null
            }
            else
            {
                Write-Log -Message ("You are trying to use Service Principal Authentication Method in a wrong way.") -Severity 'Error'
                Write-Log -Message ("It's Mandatory to specify Application ID, Secret and Tenant ID in Azure Resource Inventory") -Severity 'Error'
                Write-Log -Message (".\ResourceInventory.ps1 -appid <SP AppID> -secret <SP Secret> -tenant <TenantID>") -Severity 'Error'
                Exit
            }
    
            $Global:Subscriptions = @(az account list --output json --only-show-errors | ConvertFrom-Json)
            $Global:Subscriptions = @($Subscriptions | Where-Object { $_.tenantID -eq $TenantID })
        }
    }
    
    function GetSubscriptionsData()
    {    
        $SubscriptionCount = $Subscriptions.Count
        
        Write-Log -Message ("Number of Subscriptions Found: {0}" -f $SubscriptionCount) -Severity 'Info'
        Write-Log -Message ("Checking report folder: {0}" -f $DefaultPath) -Severity 'Info'
        
        if ((Test-Path -Path $DefaultPath -PathType Container) -eq $false) 
        {
            New-Item -Type Directory -Force -Path $DefaultPath | Out-Null
        }
    }
    
    function ResourceInventoryLoop()
    {
        if(![string]::IsNullOrEmpty($ResourceGroup) -and [string]::IsNullOrEmpty($SubscriptionID))
        {
            Write-Log -Message ("Resource Group Name present, but missing Subscription ID.") -Severity 'Error'
            Write-Log -Message ("If using ResourceGroup parameter you must also put SubscriptionId") -Severity 'Error'
            Exit
        }

        if(![string]::IsNullOrEmpty($ResourceGroup) -and ![string]::IsNullOrEmpty($SubscriptionID))
        {
            Write-Log -Message ('Extracting Resources from Subscription: ' + $SubscriptionID + '. And from Resource Group: ' + $ResourceGroup) -Severity 'Success'

            $Subscri = $SubscriptionID

            $GraphQuery = "resources | where resourceGroup == '$ResourceGroup' and strlen(properties.definition.actions) < 123000 | summarize count()"
            $EnvSize = az graph query -q $GraphQuery --subscriptions $Subscri --output json --only-show-errors | ConvertFrom-Json
            $EnvSizeNum = $EnvSize.data.'count_'

            if ($EnvSizeNum -ge 1) {
                $Loop = $EnvSizeNum / 1000
                $Loop = [math]::ceiling($Loop)
                $Looper = 0
                $Limit = 0

                while ($Looper -lt $Loop) {
                    $GraphQuery = "resources | where resourceGroup == '$ResourceGroup' and strlen(properties.definition.actions) < 123000 | project id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation$($GraphQueryTags) | order by id asc"
                    $Resource = (az graph query -q $GraphQuery --subscriptions $Subscri --skip $Limit --first 1000 --output json --only-show-errors).tolower() | ConvertFrom-Json

                    $Global:Resources += $Resource.data
                    Start-Sleep 2
                    $Looper ++
                    $Limit = $Limit + 1000
                }
            }
        }
        elseif([string]::IsNullOrEmpty($ResourceGroup) -and ![string]::IsNullOrEmpty($SubscriptionID))
        {
            Write-Log -Message ('Extracting Resources from Subscription: ' + $SubscriptionID) -Severity 'Success'

            $GraphQuery = "resources | where strlen(properties.definition.actions) < 123000 | summarize count()"
            $EnvSize = az graph query -q $GraphQuery  --output json --subscriptions $SubscriptionID --only-show-errors | ConvertFrom-Json
            $EnvSizeNum = $EnvSize.data.'count_'

            if ($EnvSizeNum -ge 1) {
                $Loop = $EnvSizeNum / 1000
                $Loop = [math]::ceiling($Loop)
                $Looper = 0
                $Limit = 0

                while ($Looper -lt $Loop) {
                    $GraphQuery = "resources | where strlen(properties.definition.actions) < 123000 | project id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation$($GraphQueryTags) | order by id asc"
                    $Resource = (az graph query -q $GraphQuery --subscriptions $SubscriptionID --skip $Limit --first 1000 --output json --only-show-errors).tolower() | ConvertFrom-Json

                    $Global:Resources += $Resource.data
                    Start-Sleep 2
                    $Looper ++
                    $Limit = $Limit + 1000
                }
            }
        } 
        else 
        {
            $GraphQuery = "resources | where strlen(properties.definition.actions) < 123000 | summarize count()"
            $EnvSize = az graph query -q  $GraphQuery --output json --only-show-errors | ConvertFrom-Json
            $EnvSizeCount = $EnvSize.Data.'count_'
            
            Write-Log -Message ("Resources Output: {0} Resources Identified" -f $EnvSizeCount) -Severity 'Success'
            
            if ($EnvSizeCount -ge 1) 
            {
                $Loop = $EnvSizeCount / 1000
                $Loop = [math]::Ceiling($Loop)
                $Looper = 0
                $Limit = 0
            
                while ($Looper -lt $Loop) 
                {
                    $GraphQuery = "resources | where strlen(properties.definition.actions) < 123000 | project id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation | order by id asc"
                    $Resource = (az graph query -q $GraphQuery --skip $Limit --first 1000 --output json --only-show-errors).tolower() | ConvertFrom-Json
                    
                    $Global:Resources += $Resource.Data
                    Start-Sleep 2
                    $Looper++
                    $Limit = $Limit + 1000
                }
            }
        }
    }
    
    function ResourceInventoryAvd()
    {    
        $AVDSize = az graph query -q "desktopvirtualizationresources | summarize count()" --output json --only-show-errors | ConvertFrom-Json
        $AVDSizeCount = $AVDSize.data.'count_'
    
        Write-Host ("AVD Resources Output: {0} AVD Resources Identified" -f $AVDSizeCount) -BackgroundColor Black -ForegroundColor Green
    
        if ($AVDSizeCount -ge 1) 
        {
            $Loop = $AVDSizeCount / 1000
            $Loop = [math]::ceiling($Loop)
            $Looper = 0
            $Limit = 0
    
            while ($Looper -lt $Loop) 
            {
                $GraphQuery = "desktopvirtualizationresources | project id,name,type,tenantId,kind,location,resourceGroup,subscriptionId,managedBy,sku,plan,properties,identity,zones,extendedLocation$($GraphQueryTags) | order by id asc"
                $AVD = (az graph query -q $GraphQuery --skip $Limit --first 1000 --output json --only-show-errors).tolower() | ConvertFrom-Json
    
                $Global:Resources += $AVD.data
                Start-Sleep 2
                $Looper++
                $Limit = $Limit + 1000
            }
        } 
    }

    CheckAriVersion
    CheckCliRequirements
    CheckPowerShell
    GetSubscriptionsData
    ResourceInventoryLoop
    ResourceInventoryAvd
}

function ExecuteInventoryProcessing()
{
    function InitializeInventoryProcessing()
    {   
        $Global:ZipOutputFile = ($DefaultPath + $Global:ReportName + "_" + $CurrentDateTime + ".zip")
        $Global:File = ($DefaultPath + $Global:ReportName + "_" + $CurrentDateTime + ".xlsx")
        $Global:AllResourceFile = ($DefaultPath + "Full_" + $Global:ReportName + "_" + $CurrentDateTime + ".json")
        $Global:JsonFile = ($DefaultPath + "Inventory_"+ $Global:ReportName + "_" + $CurrentDateTime + ".json")
        $Global:MetricsJsonFile = ($DefaultPath + "Metrics_"+ $Global:ReportName + "_" + $CurrentDateTime + ".json")
        $Global:ConsumptionFile = ($DefaultPath + "Consumption_"+ $Global:ReportName + "_" + $CurrentDateTime + ".json")
        $Global:ConsumptionFileCsv = ($DefaultPath + "Consumption_"+ $Global:ReportName + "_" + $CurrentDateTime + ".csv")

        $Global:LogFile = ($DefaultPath + "Logs_"+ $Global:ReportName + "_" + $CurrentDateTime + ".json")
    

        Write-Log -Message ('Report Excel File: {0}' -f $File) -Severity 'Info'
    }

    function CreateMetricsJob()
    {
        Write-Log -Message ('Checking if Metrics Job Should be Run.') -Severity 'Info'

        if (!$SkipMetrics.IsPresent) 
        {
            Write-Log -Message ('Running Metrics Jobs') -Severity 'Success'

            If ($RunOnline -eq $true) 
            {
                Write-Log -Message ('Looking for the following file: '+ $RawRepo + '/Extension/Metrics.ps1') -Severity 'Info'
                $ModuSeq = (New-Object System.Net.WebClient).DownloadString($RawRepo + '/Extension/Metrics.ps1')

                Write-Log -Message ($PSScriptRoot + '\Extension\Metrics.ps1') -Severity 'Info'

                if($PSScriptRoot -like '*\*')
                {
                    if (!(Test-Path -Path ($PSScriptRoot + '\Extension\')))
                    {
                        New-Item -Path ($PSScriptRoot + '\Extension\') -ItemType Directory
                    }
                    
                    $ModuSeq | Out-File ($PSScriptRoot + '\Extension\Metrics.ps1') 
                }
                else
                {
                    if (!(Test-Path -Path ($PSScriptRoot + '/Extension/')))
                    {
                        New-Item -Path ($PSScriptRoot + '/Extension/') -ItemType Directory
                    }
                    
                    $ModuSeq | Out-File ($PSScriptRoot + '/Extension/Metrics.ps1')
                }
            }

            if($PSScriptRoot -like '*\*')
            {
                $MetricPath = Get-ChildItem -Path ($PSScriptRoot + '\Extension\Metrics.ps1') -Recurse
            }
            else
            {
                $MetricPath = Get-ChildItem -Path ($PSScriptRoot + '/Extension/Metrics.ps1') -Recurse
            }

            $metricsFilePath = ($DefaultPath + "Metrics_"+ $Global:ReportName + "_" + $CurrentDateTime + "_")
            
            $Global:AzMetrics = New-Object PSObject
            $Global:AzMetrics | Add-Member -MemberType NoteProperty -Name Metrics -Value NotSet
            $Global:AzMetrics.Metrics = & $MetricPath -Subscriptions $Subscriptions -Resources $Resources -Task "Processing" -File $file -Metrics $null -TableStyle $null -ConcurrencyLimit $ConcurrencyLimit -FilePath $metricsFilePath
        }
    }

    function ProcessMetricsResult()
    {
        if (!$SkipMetrics.IsPresent) 
        {
            $([System.GC]::GetTotalMemory($false))
            $([System.GC]::Collect())
            $([System.GC]::GetTotalMemory($true))
        }
    }

    function GetServiceName($moduleUrl)
    {    
        if ($moduleUrl -like '*Services/Analytics*')
        {
            $directoryService = 'Analytics'
        }

        if ($moduleUrl -like '*Services/Compute*')
        {
            $directoryService = 'Compute'
        }

        if ($moduleUrl -like '*Services/Containers*')
        {
            $directoryService = 'Containers'
        }

        if ($moduleUrl -like '*Services/Data*')
        {
            $directoryService = 'Data'
        }

        if ($moduleUrl -like '*Services/Infrastructure*')
        {
            $directoryService = 'Infrastructure'
        }

        if ($moduleUrl -like '*Services/Integration*')
        {
            $directoryService = 'Integration'
        }

        if ($moduleUrl -like '*Services/Networking*')
        {
            $directoryService = 'Networking'
        }

        if ($moduleUrl -like '*Services/Storage*')
        {
            $directoryService = 'Storage'
        }

        return $directoryService
    }

    function CreateResourceJobs()
    {
        $Global:SmaResources = New-Object PSObject

        Write-Log -Message ('Starting Service Processing Jobs.') -Severity 'Info'
        

        If ($RunOnline -eq $true) 
        {
            Write-Log -Message ('Running Online Checking for Services Modules at: ' + $RawRepo) -Severity 'Info'

            $OnlineRepo = Invoke-WebRequest -Uri $Repo
            $RepoContent = $OnlineRepo | ConvertFrom-Json
            $ModuleUrls = ($RepoContent.tree | Where-Object {$_.path -like '*.ps1' -and $_.path -notlike 'Extension/*' -and $_.path -ne 'ResourceInventory.ps1'}).path      

            if($PSScriptRoot -like '*\*')
            {
                if (!(Test-Path -Path ($PSScriptRoot + '\Services\')))
                {
                    New-Item -Path ($PSScriptRoot + '\Services\') -ItemType Directory
                }
            }
            else
            {
                if (!(Test-Path -Path ($PSScriptRoot + '/Services/')))
                {
                    New-Item -Path ($PSScriptRoot + '/Services/') -ItemType Directory
                }
            }

            foreach ($moduleUrl in $moduleUrls)
            {
                $ModuleContent = (New-Object System.Net.WebClient).DownloadString($RawRepo + '/' + $moduleUrl)
                $ModuleFileName = [System.IO.Path]::GetFileName($moduleUrl)

                $servicePath = GetServiceName($moduleUrl)

                if($PSScriptRoot -like '*\*')
                {
                    if (!(Test-Path -Path ($PSScriptRoot + '\Services\' + $servicePath + '\')))
                    {
                        New-Item -Path ($PSScriptRoot + '\Services\' + $servicePath + '\') -ItemType Directory
                    }
                }
                else
                {
                    if (!(Test-Path -Path ($PSScriptRoot + '/Services/' + $servicePath + '/')))
                    {
                        New-Item -Path ($PSScriptRoot + '/Services/' + $servicePath + '/') -ItemType Directory
                    }
                }

                if($PSScriptRoot -like '*\*')
                {
                    $ModuleContent | Out-File ($PSScriptRoot + '\Services\' + $servicePath + '\' + $ModuleFileName) 
                }
                else
                {
                    $ModuleContent | Out-File ($PSScriptRoot + '/Services/'+ $servicePath + '/' + $ModuleFileName) 
                }
            }
        }

        if($PSScriptRoot -like '*\*')
        {
            $Modules = Get-ChildItem -Path ($PSScriptRoot +  '\Services\*.ps1') -Recurse
        }
        else
        {
            $Modules = Get-ChildItem -Path ($PSScriptRoot +  '/Services/*.ps1') -Recurse
        }

        $Resource = $Resources | Select-Object -First $Resources.count
        $Resource = ($Resource | ConvertTo-Json -Depth 50)

        foreach ($Module in $Modules) 
        {
            $ModName = $Module.Name.Substring(0, $Module.Name.length - ".ps1".length)
            
            Write-Log -Message ("Service Processing: {0}" -f $ModName) -Severity 'Success'

            $result = & $Module -SCPath $SCPath -Sub $Subscriptions -Resources ($Resource | ConvertFrom-Json) -Task "Processing" -File $file -SmaResources $null -TableStyle $null -Metrics $Global:AzMetrics
            $Global:SmaResources | Add-Member -MemberType NoteProperty -Name $ModName -Value NotSet
            $Global:SmaResources.$ModName = $result

            $result = $null
            [System.GC]::Collect()
        }
    }

    function ProcessResourceResult()
    {
        Write-Log -Message ("Starting Reporting Phase.") -Severity 'Info'

        $Services = @()

        if($PSScriptRoot -like '*\*')
        {
            $Services = Get-ChildItem -Path ($PSScriptRoot + '\Services\*.ps1') -Recurse
        }
        else
        {
            $Services = Get-ChildItem -Path ($PSScriptRoot + '/Services/*.ps1') -Recurse
        }

        Write-Log -Message ('Services Found: ' + $Services.Count) -Severity 'Info'
        $Lops = $Services.count
        $ReportCounter = 0

        foreach ($Service in $Services) 
        {
            $c = (($ReportCounter / $Lops) * 100)
            $c = [math]::Round($c)
            
            Write-Log -Message ("Running Services: $Service") -Severity 'Info'
            $ProcessResults = & $Service.FullName -SCPath $PSScriptRoot -Sub $null -Resources $null -Task "Reporting" -File $file -SmaResources $Global:SmaResources -TableStyle $Global:TableStyle -Metrics $null

            $ReportCounter++
        }

        $Global:SmaResources | Add-Member -MemberType NoteProperty -Name 'Version' -Value NotSet
        $Global:SmaResources.Version = $Global:Version

        $Global:SmaResources | ConvertTo-Json -depth 100 -compress | Out-File $Global:JsonFile
        #$Global:Resources | ConvertTo-Json -depth 100 -compress | Out-File $Global:AllResourceFile
        
        Write-Log -Message ('Resource Reporting Phase Done.') -Severity 'Info'
    }

    function Get-AzureUsage 
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [datetime]$FromTime,
     
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [datetime]$ToTime,
     
            [Parameter()]
            [ValidateNotNullOrEmpty()]
            [ValidateSet('Hourly', 'Daily')]
            [string]$Interval = 'Daily'
        )
        
        Write-Log -Message ("Querying usage data [$($FromTime) - $($ToTime)]...") -Severity 'Info'

        $usageData = $null

        foreach($sub in $Global:Subscriptions)
        {
            Set-AzContext -Subscription $sub.id | Out-Null
            Write-Log -Message ("Gathering Consumption for: {0}" -f $sub.Name) -Severity 'Info'

            do 
            {    
                $params = @{
                    ReportedStartTime      = $FromTime
                    ReportedEndTime        = $ToTime
                    AggregationGranularity = $Interval
                    ShowDetails            = $true
                }
    
                if ((Get-Variable -Name usageData -ErrorAction Ignore) -and $usageData) 
                {
                    Write-Log -Message ("Querying Next Page") -Severity 'Info'
                    $params.ContinuationToken = $usageData.ContinuationToken
                }
    
                $usageData = Get-UsageAggregates @params
                $usageData.UsageAggregations | Select-Object -ExpandProperty Properties

                Write-Log -Message ("Records found: $($usageData.UsageAggregations.Count)...") -Severity 'Info'
                
            } while ('ContinuationToken' -in $usageData.psobject.properties.name -and $usageData.ContinuationToken)
        }
    }

    function ProcessResourceConsumption()
    {
        $DebugPreference = "SilentlyContinue"

        #Force the culture here...
        [System.Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"; 
        [System.Threading.Thread]::CurrentThread.CurrentCulture = "en-US";

        $reportedStartTime = (Get-Date).AddDays(-30).Date.AddHours(0).AddMinutes(0).AddSeconds(0).DateTime
        $reportedEndTime = (Get-Date).AddDays(-1).Date.AddHours(0).AddMinutes(0).AddSeconds(0).DateTime

        $consumptionData = Get-AzureUsage -FromTime $reportedStartTime -ToTime $reportedEndTime -Interval Daily -Verbose

        for($item = 0; $item -lt $consumptionData.Count; $item++) 
        {
            $instanceInfo = ($consumptionData[$item].InstanceData.tolower() | ConvertFrom-Json)

            $consumptionData[$item] | Add-Member -MemberType NoteProperty -Name ResourceId -Value NotSet
            $consumptionData[$item] | Add-Member -MemberType NoteProperty -Name ResourceLocation -Value NotSet

            $consumptionData[$item].ResourceId = $instanceInfo.'Microsoft.Resources'.resourceUri
            $consumptionData[$item].ResourceLocation = $instanceInfo.'Microsoft.Resources'.location
        }

        $consumptionData | Export-Csv $Global:ConsumptionFileCsv -Encoding utf-8

        Write-Log -Message ("Consumption Entries: {0}" -f $consumptionData.Count) -Severity 'Info'

        $aggregatedResult = @()

        # Group by ResourceId
        $groupedDataByResource = $consumptionData | Group-Object ResourceId

        foreach ($resourceGroup in $groupedDataByResource) 
        {
            $resourceId = $resourceGroup.Name
            $resourceItems = $resourceGroup.Group

            $tmpMeters = [System.Collections.Generic.List[psobject]]::new()

            $aggregatedMeters = $resourceItems | Group-Object MeterId | ForEach-Object {
                $meterId = $_.Name
                $usageAggregates = $_.Group | Measure-Object -Property Quantity -Sum
                $unit = $_.Group[0].Unit
                $meterCategory = $_.Group[0].MeterCategory
                $meterName = $_.Group[0].MeterName
                $meterRegion = $_.Group[0].MeterRegion
                $meterSubCategory = $_.Group[0].MeterSubCategory
                $meterInstance = ($_.Group[0].InstanceData | ConvertFrom-Json -depth 100)
                $additionalInfo = $meterInstance.'Microsoft.Resources'.additionalInfo
                $meterInfo = $meterInstance.'Microsoft.Resources'.meterInfo
                $meterCount = $_.Group.Count

                $MeterObject =[PSCustomObject]@{
                    MeterId = $meterId
                    TotalUsage = $usageAggregates.Sum.ToString("0.#########")
                    MeterCategory = $meterCategory
                    Unit = $unit
                    MeterName = $meterName
                    MeterRegion = $meterRegion
                    MeterSubCategory = $meterSubCategory
                    InstanceInfo = $meterInstance
                    AdditionalInfo = $additionalInfo
                    MeterInfo = $meterInfo
                    MeterCount = $meterCount
                }

                $tmpMeters.Add($MeterObject)
            }

            $aggregatedResult += [PSCustomObject]@{
                ResourceId = $resourceId
                Meters = $tmpMeters
            }    
        }

        $ConsumptionOutput = New-Object PSObject
        $ConsumptionOutput | Add-Member -MemberType NoteProperty -Name StartDate -Value NotSet
        $ConsumptionOutput | Add-Member -MemberType NoteProperty -Name EndDate -Value NotSet
        $ConsumptionOutput | Add-Member -MemberType NoteProperty -Name Resources -Value NotSet

        $ConsumptionOutput.StartDate = $reportedStartTime
        $ConsumptionOutput.EndDate = $reportedEndTime
        $ConsumptionOutput.Resources = $aggregatedResult

        $ConsumptionOutput | ConvertTo-Json -depth 100 -compress | Out-File $Global:ConsumptionFile

        $DebugPreference = "Continue"  
    }

    InitializeInventoryProcessing
    CreateMetricsJob
    CreateResourceJobs   
    ProcessMetricsResult
    ProcessResourceResult

    if($SkipConsumption.IsPresent)
    {
       ProcessResourceConsumption
    }
}

function FinalizeOutputs
{
    function ProcessSummary()
    {
        Write-Log -Message ('Creating Summary Report') -Severity 'Info'
        Write-Log -Message ('Starting Summary Report Processing Job.') -Severity 'Info'

        If ($RunOnline -eq $true) 
        {
            Write-Log -Message ('Looking for the following file: '+$RawRepo + '/Extension/Summary.ps1') -Severity 'Info'
            $ModuSeq = (New-Object System.Net.WebClient).DownloadString($RawRepo + '/Extension/Summary.ps1')

            Write-Log -Message ($PSScriptRoot + '\Extension\Summary.ps1') -Severity 'Info'

            if($PSScriptRoot -like '*\*')
            {
                $ModuSeq | Out-File ($PSScriptRoot + '\Extension\Summary.ps1') 
            }
            else
            {
                $ModuSeq | Out-File ($PSScriptRoot + '/Extension/Summary.ps1')
            }
        }

        if($PSScriptRoot -like '*\*')
        {
            $SummaryPath = Get-ChildItem -Path ($PSScriptRoot + '\Extension\Summary.ps1') -Recurse
        }
        else
        {
            $SummaryPath = Get-ChildItem -Path ($PSScriptRoot + '/Extension/Summary.ps1') -Recurse
        }

        $ChartsRun = & $SummaryPath -File $file -TableStyle $TableStyle -PlatOS $PlatformOS -Subscriptions $Subscriptions -Resources $Resources -ExtractionRunTime $Runtime -ReportingRunTime $ReportingRunTime -RunLite $false -Version $Global:Version
    }

    ProcessSummary
}

# Setup and Inventory Gathering
$Global:Runtime = Measure-Command -Expression {
    Variables
    RunInventorySetup
}

$Global:PowerShellTranscriptFile = ($DefaultPath + "Transcript_Log_"+ $Global:ReportName + "_" + $CurrentDateTime + ".txt")
Start-Transcript -Path $Global:PowerShellTranscriptFile -UseMinimalHeader

# Execution and processing of inventory
$Global:ReportingRunTime = Measure-Command -Expression {
    ExecuteInventoryProcessing
}

Stop-Transcript

# Prepare the summary and outputs
FinalizeOutputs

Write-Log -Message ("Compressing Resources Output: {0}" -f $Global:ZipOutputFile) -Severity 'Info'

if($EnableLogs.IsPresent)
{
    $Global:Logging | ConvertTo-Json -depth 5 -compress | Out-File $Global:LogFile
} 

if($SkipMetrics.IsPresent)
{
    "Metrics Not Gathered" | ConvertTo-Json -depth 5 -compress | Out-File $Global:MetricsJsonFile 
}

$jsonWildCard = $DefaultPath + "*.json"

$compressionOutput = @{
    Path = $Global:File, $Global:ConsumptionFileCsv, $Global:PowerShellTranscriptFile, $jsonWildCard
    CompressionLevel = 'Fastest'
    DestinationPath = $Global:ZipOutputFile
}

try 
{
    Compress-Archive @compressionOutput
}
catch 
{
    $_ | Format-List -Force
    Write-Error ("Error Compressing Output File: {0}." -f $Global:ZipOutputFile)
    Write-Error ("Please zip the output files manually.")
}

Write-Log -Message ("Execution Time: {0}" -f $Runtime) -Severity 'Success'
Write-Log -Message ("Reporting Time: {0}" -f $ReportingRunTime) -Severity 'Success'
Write-Log -Message ("Reporting Data File: {0}" -f $Global:ZipOutputFile) -Severity 'Success'
