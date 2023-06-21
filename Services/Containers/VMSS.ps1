﻿param($SCPath, $Sub, $Resources, $Task ,$File, $SmaResources, $TableStyle)

If ($Task -eq 'Processing')
{
    <######### Insert the resource extraction here ########>

        $vmss = $Resources | Where-Object {$_.TYPE -eq 'microsoft.compute/virtualmachinescalesets'}
        $AutoScale = $Resources | Where-Object {$_.TYPE -eq "microsoft.insights/autoscalesettings" -and $_.Properties.enabled -eq 'true'} 
        $AKS = $Resources | Where-Object {$_.TYPE -eq 'microsoft.containerservice/managedclusters'}
        $SFC = $Resources | Where-Object {$_.TYPE -eq 'microsoft.servicefabric/clusters'}

    <######### Insert the resource Process here ########>

    if($vmss)
        {
            $tmp = @()

            foreach ($1 in $vmss) {
                $ResUCount = 1
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                $data = $1.PROPERTIES
                $OS = $data.virtualMachineProfile.storageProfile.osDisk.osType
                $RelatedAKS = ($AKS | Where-Object {$_.properties.nodeResourceGroup -eq $1.resourceGroup}).Name
                if([string]::IsNullOrEmpty($RelatedAKS)){$Related = ($SFC | Where-Object {$_.Properties.clusterEndpoint -in $1.properties.virtualMachineProfile.extensionProfile.extensions.properties.settings.clusterEndpoint}).Name}else{$Related = $RelatedAKS}
                $Scaling = ($AutoScale | Where-Object {$_.Properties.targetResourceUri -eq $1.id})
                if([string]::IsNullOrEmpty($Scaling)){$AutoSc = $false}else{$AutoSc = $true}
                $Diag = if($data.virtualMachineProfile.diagnosticsProfile){'Enabled'}else{'Disabled'}
                if($OS -eq 'Linux'){$disablePwd = $data.virtualMachineProfile.osProfile.linuxConfiguration.disablePasswordAuthentication}Else{$disablePwd = 'N/A'}
                $timecreated = $data.timeCreated
                $timecreated = [datetime]$timecreated
                $timecreated = $timecreated.ToString("yyyy-MM-dd HH:mm")
                $Subnet = $data.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.ipConfigurations.properties.subnet.id | Select-Object -Unique
                $VNET = $subnet.split('/')[8]
                $Subnet = $Subnet.split('/')[10]
                $ext = @()
                $ext = foreach ($ex in $1.Properties.virtualMachineProfile.extensionProfile.extensions.name) 
                                {
                                    $ex + ', '
                                }
                $NSG = $data.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.networkSecurityGroup.id.split('/')[8] 
                
                $obj = @{
                    'ID'                            = $1.id;
                    'Subscription'                  = $sub1.Name;
                    'Resource Group'                = $1.RESOURCEGROUP;
                    'AKS / SFC'                     = $Related;
                    'Name'                          = $1.NAME;
                    'Location'                      = $1.LOCATION;
                    'SKU Tier'                      = $1.sku.tier;
                    'Fault Domain'                  = $data.platformFaultDomainCount;
                    'Upgrade Policy'                = $data.upgradePolicy.mode;                                    
                    'Diagnostics'                   = $Diag;
                    'VM Size'                       = $1.sku.name;
                    'Instances'                     = $1.sku.capacity;
                    'Autoscale Enabled'             = $AutoSc;
                    'VM OS'                         = $OS;
                    'OS Image'                      = $data.virtualMachineProfile.storageProfile.imageReference.offer;
                    'Image Version'                 = $data.virtualMachineProfile.storageProfile.imageReference.sku;                            
                    'VM OS Disk Size (GB)'          = $data.virtualMachineProfile.storageProfile.osDisk.diskSizeGB;
                    'Disk Storage Account Type'     = $data.virtualMachineProfile.storageProfile.osDisk.managedDisk.storageAccountType;
                    'Disable Password Authentication'= $disablePwd;
                    'Custom DNS Servers'            = [string]$data.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.dnsSettings.dnsServers;
                    'Virtual Network'               = $VNET;
                    'Subnet'                        = $Subnet;
                    'Accelerated Networking Enabled'= $data.virtualMachineProfile.networkProfile.networkInterfaceConfigurations.properties.enableAcceleratedNetworking; 
                    'Network Security Group'        = $NSG;
                    'Extensions'                    = [string]$ext;
                    'Admin Username'                = $data.virtualMachineProfile.osProfile.adminUsername;
                    'VM Name Prefix'                = $data.virtualMachineProfile.osProfile.computerNamePrefix;
                    'Created Time'                  = $timecreated;
                    'Resource U'                    = $ResUCount;
                }
                $tmp += $obj
                if ($ResUCount -eq 1) { $ResUCount = 0 } 
            }
            $tmp
        }
}

<######## Resource Excel Reporting Begins Here ########>

Else
{
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if($SmaResources.VMSS)
    {

        $TableName = ('VMSSTable_'+($SmaResources.VMSS.id | Select-Object -Unique).count)
        $Style = @()        
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0' -Range A:W
        $Style += New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat '0.0' -Range Y:AA
        $Style += New-ExcelStyle -HorizontalAlignment Left -Range W:W -Width 60 -WrapText

        $condtxt = @()
        $condtxt += New-ConditionalText FALSE -Range L:L
        $condtxt += New-ConditionalText FALSO -Range L:L
        $condtxt += New-ConditionalText Disabled -Range I:I
        $condtxt += New-ConditionalText FALSE -Range V:V
        $condtxt += New-ConditionalText FALSO -Range V:V


        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('AKS / SFC')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('SKU Tier')
        $Exc.Add('Fault Domain')
        $Exc.Add('Upgrade Policy')                                   
        $Exc.Add('Diagnostics')
        $Exc.Add('VM Size')
        $Exc.Add('Instances')
        $Exc.Add('Autoscale Enabled')
        $Exc.Add('VM OS')
        $Exc.Add('OS Image')
        $Exc.Add('Image Version')                        
        $Exc.Add('VM OS Disk Size (GB)')
        $Exc.Add('Disk Storage Account Type')
        $Exc.Add('Disable Password Authentication')
        $Exc.Add('Custom DNS Servers')
        $Exc.Add('Virtual Network')
        $Exc.Add('Subnet')
        $Exc.Add('Accelerated Networking Enabled')
        $Exc.Add('Network Security Group')
        $Exc.Add('Extensions')
        $Exc.Add('Admin Username')
        $Exc.Add('VM Name Prefix')
        $Exc.Add('Created Time')

        $ExcelVar = $SmaResources.VMSS 

        $ExcelVar | 
        ForEach-Object { [PSCustomObject]$_ } | Select-Object -Unique $Exc | 
        Export-Excel -Path $File -WorksheetName 'VM Scale Sets' -AutoSize -MaxAutoSizeRows 50 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style

    }
}