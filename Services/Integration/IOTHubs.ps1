param($SCPath, $Sub, $Resources, $Task , $File, $SmaResources, $TableStyle)

If ($Task -eq 'Processing') {

    <######### Insert the resource extraction here ########>

    $IOTHubs = $Resources | Where-Object { $_.TYPE -eq 'microsoft.devices/iothubs' }

    if($IOTHubs)
        {
            $tmp = @()
            foreach ($1 in $IOTHubs) {
                $ResUCount = 1
                $sub1 = $SUB | Where-Object { $_.id -eq $1.subscriptionId }
                $data = $1.PROPERTIES
                $IpFilter = $data.ipFilterRules.count
                
                foreach ($Tag in $Tags) {
                    $obj = @{
                        'ID'                                = $1.id;
                        'Subscription'                      = $sub1.Name;
                        'Resource Group'                    = $1.RESOURCEGROUP;
                        'Name'                              = $1.NAME;                                    
                        'SKU'                               = $data.sku.name;
                        'SKU Tier'                          = $data.sku.tier;
                        'Location'                          = $loc.location;
                        'Role'                              = $loc.role;
                        'State'                             = $data.state;
                        'Event Retention Time In Days'      = [string]$data.eventHubEndpoints.events.retentionTimeInDays;
                        'Event Partition Count'             = [string]$data.eventHubEndpoints.events.partitionCount;
                        'Events Path'                       = [string]$data.eventHubEndpoints.events.path;
                        'Max Delivery Count'                = [string]$data.cloudToDevice.maxDeliveryCount;
                        'Host Name'                         = $data.hostName;
                    }
                    $tmp += $obj
                    if ($ResUCount -eq 1) { $ResUCount = 0 } 
                }              
            }
            $tmp
        }
}
<######## Resource Excel Reporting Begins Here ########>

Else {
    <######## $SmaResources.IOTHubs ##########>

    if ($SmaResources.IOTHubs) {

        $TableName = ('IOTHubsTable_'+($SmaResources.IOTHubs.id | Select-Object -Unique).count)
        $Style = New-ExcelStyle -HorizontalAlignment Center -AutoSize -NumberFormat 0
        
        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('Resource Group')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('SKU')
        $Exc.Add('SKU Tier')
        $Exc.Add('Location')
        $Exc.Add('Role')
        $Exc.Add('State')
        $Exc.Add('Event Retention Time In Days')
        $Exc.Add('Event Partition Count')
        $Exc.Add('Events Path')
        $Exc.Add('Max Delivery Count')
        $Exc.Add('Host Name')

        $ExcelVar = $SmaResources.IOTHubs 

        $ExcelVar | 
        ForEach-Object { [PSCustomObject]$_ } | Select-Object -Unique $Exc | 
        Export-Excel -Path $File -WorksheetName 'IOTHubs' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -Style $Style

    }
    <######## Insert Column comments and documentations here following this model #########>
}
