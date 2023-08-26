﻿param($SCPath, $Sub, $Resources, $Task ,$File, $SmaResources, $TableStyle, $Metrics)

If ($Task -eq 'Processing') {
    <######### Insert the resource extraction here ########>

    $storageacc = $Resources | Where-Object { $_.TYPE -eq 'microsoft.storage/storageaccounts' }

    <######### Insert the resource Process here ########>

    if($storageacc)
        {
            $tmp = @()

            foreach ($1 in $storageacc) {
                $sub1 = $SUB | Where-Object { $_.Id -eq $1.subscriptionId }
                $data = $1.PROPERTIES
                $timecreated = $data.creationTime
                $timecreated = [datetime]$timecreated
                $timecreated = $timecreated.ToString("yyyy-MM-dd HH:mm")

                if([string]::IsNullOrEmpty($data.secondaryLocation)){ $secondaryLocation = "None" } else { $secondaryLocation = $data.secondaryLocation }
                if($data.isHnsEnabled){ $hnsEnabled = $true } else { $secondaryLocation = $hnsEnabled = $false }
                
                $obj = @{
                    'ID'                                   = $1.id;
                    'Subscription'                         = $sub1.Name;
                    'ResourceGroup'                        = $1.RESOURCEGROUP;
                    'Name'                                 = $1.NAME;
                    'Location'                             = $1.LOCATION;
                    'SKU'                                  = $1.sku.name;
                    'Tier'                                 = $1.sku.tier;
                    'Kind'                                 = $1.kind;
                    'AccessTier'                           = $data.accessTier;
                    'PrimaryLocation'                      = $data.primaryLocation;
                    'StatusOfPrimary'                      = $data.statusOfPrimary;
                    'SecondaryLocation'                    = $secondaryLocation;
                    'HierarchicalNamespace'                = $hnsEnabled;
                    'CreatedTime'                          = $timecreated;   
                }
                $tmp += $obj
            }
            $tmp
        }
}

<######## Resource Excel Reporting Begins Here ########>

Else {
    <######## $SmaResources.(RESOURCE FILE NAME) ##########>

    if ($SmaResources.StorageAcc) {

        $TableName = ('StorAccTable_'+($SmaResources.StorageAcc.id | Select-Object -Unique).count)
        $Style = @()
        
        $condtxt = @()

        $Exc = New-Object System.Collections.Generic.List[System.Object]
        $Exc.Add('Subscription')
        $Exc.Add('ResourceGroup')
        $Exc.Add('Name')
        $Exc.Add('Location')
        $Exc.Add('SKU')
        $Exc.Add('Tier')
        $Exc.Add('Kind')
        $Exc.Add('AccessTier')
        $Exc.Add('PrimaryLocation')
        $Exc.Add('StatusOfPrimary')
        $Exc.Add('SecondaryLocation')
        $Exc.Add('HierarchicalNamespace')
        $Exc.Add('CreatedTime')

        $ExcelVar = $SmaResources.StorageAcc

        $ExcelVar |
        ForEach-Object { [PSCustomObject]$_ } | Select-Object -Unique $Exc |
        Export-Excel -Path $File -WorksheetName 'Storage Acc' -AutoSize -MaxAutoSizeRows 100 -TableName $TableName -TableStyle $tableStyle -ConditionalText $condtxt -Style $Style
    }
}
