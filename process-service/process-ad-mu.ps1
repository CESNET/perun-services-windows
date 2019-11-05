#0.1

<#
.SYNOPSIS
Perun provisioning script for MU Identities AD.


.DESCRIPTION
Perun provisioning script for MU Identities AD.


.NOTES
2019/04/15

https://www.muni.cz/lide/433479-david-stencel
#>

#--------------------- Functions

#function write-perunlog ($LogLevel, $LogMessage)
#{
#    write-host "$LogLevel, $LogMessage"
#}

function process_users {

    # Get the input file
    $perunUsers = Get-Content ("$EXTRACT_DIR_PATH\$SERVICE_NAME" + '_users.json') -Encoding UTF8 | ConvertFrom-Json
    
    # Create hashtable from AD export
    $ADUsersMap = @{ }
    Get-ADUser -SearchBase $baseDNUsers -Filter $FILTER_USERS -Properties $FILTER_AD_USERS_GET_ATT -SearchScope subtree | Where-Object { $_ -ne $null } | ForEach-Object { $ADUsersMap.Add($_.samAccountName, $_) }

    ForEach ($perunUser in $perunUsers) {

        $userSAM = $perunUser.samAccountName

        $ADUser = $ADUsersMap.Item($userSAM)
        if ([string]::IsNullOrEmpty($ADUser)) {

            add_user $perunUser
        } else {

            update_user $ADUser $perunUser
        }
    }
}

function add_user($user) {

    try {
        # Create hashtable from user attributes
        $userAttributesHash = @{ }
        $($user.PSObject.Properties) | ForEach-Object { if (($_.Value -ne $null) -and ($_.name -notin 'samaccountname', 'dn')) { $userAttributesHash[$_.Name] = $_.Value } }

        #cn = samaccountname; dn generates automatically

        New-ADUser  -Name $user.samAccountName `
            -OtherAttributes $userAttributesHash `
            -Path $($user.dn -replace "CN=$($user.cn),")

        ++$script:COUNTER_USERS_ADDED
        Write-PerunLog -LogLevel 'INFO' -LogMessage "Added user: $($user.samAccountName).|ADD_USER"
    } catch {
        ++$script:COUNTER_USERS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed adding user $($user.samAccountName). $_|ADD_USER"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed adding user $($user.samAccountName). $_)")
    }
}

function update_user($user, $updateUser) {

    try {

        $updated = $false
    
        foreach ($attribute in $FILTER_AD_USERS_UPDATE_ATT) {
            $userAtt = $($user.$attribute)
            $updateUserAtt = $($updateUser.$attribute)

            
            if (($userAtt -ne $null) -and ($updateUserAtt -ne $null)) {
                
                # If an attribute is an array
                if ((($($userAtt.gettype().name) -eq 'Object[]')) -or ($($userAtt.gettype().name) -eq 'ADPropertyValueCollection')) {

                    Compare-Object -ReferenceObject $userAtt -DifferenceObject $updateUserAtt -CaseSensitive `
                    | ForEach-Object {
                        if ($_.SideIndicator -eq '=>') {
                            $null = $user.$attribute.Add($_.InputObject)
                        } else {
                            $null = $user.$attribute.Remove($_.InputObject)
                        }

                        $updated = $true
                    }
                } elseif (($userAtt -ne $updateUserAtt) -or ($updateUserAtt -ne $userAtt)) {
             
                    $user.$attribute = $updateUserAtt
                    $updated = $true
                }
            } elseif (($userAtt -ne $updateUserAtt) -or ($updateUserAtt -ne $userAtt)) {
                
                $user.$attribute = $updateUserAtt
                $updated = $true
            }    
        }
      
        if ($updated) {
            Set-ADUser -Instance $user

            ++$script:COUNTER_USERS_UPDATED
            Write-PerunLog -LogLevel 'INFO' -LogMessage "Updated user: $($user.samAccountName).|UPDATE_USER"
        }
    } catch {
        ++$script:COUNTER_USERS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed updating user $($user.samAccountName). $_|UDATE_USER"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed updating user $($user.samAccountName). $_)")
    }
}

function process_groups($ou) {

    # Create hashtable from Perun input
    $perunGroupsMap = @{ }
    $(Get-Content ("$EXTRACT_DIR_PATH\$SERVICE_NAME" + "_groups_$($ou.ou).json") -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $perunGroupsMap.Add($_.cn, $_) }
    
    # Create hashtable from AD export
    $ADGroupsMap = @{ }
    Get-ADGroup -SearchBase $ou.dn -Filter $FILTER_GROUPS -Properties $FILTER_AD_GROUPS_GET_ATT -SearchScope subtree | Where-Object { $_ -ne $null } | ForEach-Object { $ADGroupsMap.Add($_.Name, $_) }
    

    ForEach ($perunGroup in $($perunGroupsMap.Values)) {
        $groupCN = $perunGroup.cn

        
        try {

            $ADGroup = $ADGroupsMap.Item($groupCN)
            if ([string]::IsNullOrEmpty($ADGroup)) {

                add_group $perunGroup
            } else {

                update_group $ADGroup $perunGroup
            }
        } catch {

            Write-PerunLog -LogLevel 'WARNING' -LogMessage "Skipping processing group members $($groupCN). $_|PROCESS_GROUP"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Skipping processing group members $($groupCN). $_)")

            continue
        }

        # Update group members
        try {
            process_group_members $perunGroup
        } catch {
            ++$script:COUNTER_GROUPS_FAILED
            Write-PerunLog -LogLevel 'WARNING' -LogMessage "Could not process group members $($groupCN). $_|PROCESS_MEMBERS"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Could not process group members $($groupCN). $_)")

            continue
        }
    }

    # Empty groups (empty group and do not delete)
    ForEach ($ADGroup in $($ADGroupsMap.Values)) {
        $groupCN = $ADGroup.Name

        $perunGroup = $perunGroupsMap.Item($groupCN)
        if ([string]::IsNullOrEmpty($perunGroup)) {

            empty_group $ADGroup
        }
    }
}

function add_group($group) {

    try {
        $groupAttributesHash = @{ }
        $($group.PSObject.Properties) | ForEach-Object { if (($_.Value -ne $null) -and ($_.name -notin 'samaccountname', 'dn', 'members', 'cn')) { $groupAttributesHash[$_.Name] = $_.Value } }

        New-ADgroup -Name $group.samAccountName `
            -GroupScope Global `
            -OtherAttributes $groupAttributesHash `
            -Path $($group.dn -replace "CN=$($group.cn),")

        ++$script:COUNTER_GROUPS_ADDED
        Write-PerunLog -LogLevel 'INFO' -LogMessage "Added group: $($group.cn).|ADD_GROUP"
    } catch {
        ++$script:COUNTER_GROUPS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed adding group $($group.cn). $_|ADD_GROUP"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed adding group $($group.cn). $_)")

        throw
    }
}

function update_group($group, $updateGroup) {

    try {
        $updated = $false
    
        foreach ($attribute in $FILTER_AD_GROUPS_UPDATE_ATT) { 

            $groupAtt = $($group.$attribute)
            $updateGroupAtt = $($updateGroup.$attribute)

            if (($groupAtt -ne $null) -and ($updateGroupAtt -ne $null)) {
                # If the attribute is an array
                if ((($($groupAtt.gettype().name) -eq 'Object[]')) -or ($($groupAtt.gettype().name) -eq 'ADPropertyValueCollection')) {

                    Compare-Object -ReferenceObject $groupAtt -DifferenceObject $updateGroupAtt -CaseSensitive `
                    | ForEach-Object {
                        if ($_.SideIndicator -eq '=>') {
                            $null = $group.$attribute.Add($_.InputObject)
                        } else {
                            $null = $group.$attribute.Remove($_.InputObject)
                        }

                        $updated = $true
                    }
                } elseif (($groupAtt -ne $updateGroupAtt) -or ($updateGroupAtt -ne $groupAtt)) {
             
                    $group.$attribute = $updateGroupAtt
                    $updated = $true
                }
            } elseif (($groupAtt -ne $updateGroupAtt) -or ($updateGroupAtt -ne $groupAtt)) {
             
                $group.$attribute = $updateGroupAtt
                $updated = $true
            }
        }

        
        if ($updated) {
            Set-ADGroup -Instance $group
            ++$script:COUNTER_GROUPS_UPDATED
            Write-PerunLog -LogLevel 'INFO' -LogMessage "Updated group: $($group.cn).|UPDATE_GROUP"
        }
    } catch {
        ++$script:COUNTER_GROUPS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed updating group $($group.cn). $_|UDATE_GROUP"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed updating group $($group.cn). $_)")

        throw
    }
}

function empty_group ($group) {
    try {
        # Remove all group users
        if ($group.DistinguishedName -notmatch $baseDNlicenses) {
            $members = Get-ADGroupMember -Identity $group.DistinguishedName

            if ($members.count -gt 0) {
                Remove-ADGroupMember -Identity $group.DistinguishedName -Members $members -Confirm:$false

                # Set 'stop syncing' attribute
                if ($group.extensionAttribute1) {
                    $group.extensionAttribute1 = 'FALSE'
                }

                Set-ADGroup -Instance $group
                ++$script:COUNTER_GROUPS_EMPTIED
                Write-PerunLog -LogLevel 'INFO' -LogMessage "Emptied group: $($group.cn).|EMPTY_GROUP"
            }
        } else {
            Write-PerunLog -LogLevel 'WARNING' -LogMessage "Prevented from emptying a licence group $group.cn|EMPTY_GROUP"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Prevented from emptying a licence group $group.cn)")
        }
    } catch {
        ++$script:COUNTER_GROUPS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed emptying group $($group.cn). $_|EMPTY_GROUP"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed emptying group $($group.cn). $_)")
    }
}

function process_group_members ($updateGroup) {
    
    try {
        # Create hashtable from AD export
        $ADMembersMap = @{ }
        (Get-ADGroupMember -Identity $updateGroup.dn).distinguishedName | Where-Object { $_ -ne $null } | ForEach-Object { $ADMembersMap.Add($_, $null) }

        # Create hashtable from Perun import
        $perunMembersMap = @{ }
        $perunMembers = $updateGroup.members
        $perunMembers | ForEach-Object { $perunMembersMap.Add($_, $null) }

        # Compare members, remove common entries
        $perunMembers | ForEach-Object {
            if ($ADMembersMap.Contains($_)) {
                $perunMembersMap.Remove($_)
                $ADMembersMap.Remove($_)
            }
        }

        # Users in AD that are not in Perun
        if ($ADMembersMap.Keys.Count -gt 0) {
            $members = $ADMembersMap.Keys | ForEach-Object { $_.ToString() }
            Remove-ADGroupMember -Identity $updateGroup.dn -Members $members -Confirm:$false

            Write-PerunLog -LogLevel 'INFO' -LogMessage "Removed group members: $($updateGroup.cn). $($members -join ';') |MEMBER_GROUP"
        }

        # Users in Perun that are not in AD
        if ($perunMembersMap.Keys.Count -gt 0) {
            $members = $perunMembersMap.Keys | ForEach-Object { $_.ToString() }
            Add-ADGroupMember -Identity $updateGroup.dn -Members $members

            Write-PerunLog -LogLevel 'INFO' -LogMessage "Added group members: $($updateGroup.cn). $($members -join ';') |MEMBER_GROUP"
        }
    } catch {
        ++$script:COUNTER_GROUPS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Editing group members $($updateGroup.cn). $_|MEMBER_GROUP"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Editing group members $($updateGroup.cn). $_)")
    }
}


function process_ous {

    # Get the input file
    $perunOUs = Get-Content ("$EXTRACT_DIR_PATH\$SERVICE_NAME" + '_ous.json') -Encoding UTF8 | ConvertFrom-Json

    # Create hashtable from AD export
    $ADOUsMap = @{ }
    Get-ADOrganizationalUnit -SearchBase $baseDNgroups -Filter $FILTER_OUS -SearchScope subtree | Where-Object { $_ -ne $null } | ForEach-Object { $ADOUsMap.Add($_.DistinguishedName, $_) }

    ForEach ($perunOU in $perunOUs) {
        $ouDN = $perunOU.dn

        $ADOU = $ADOUsMap.Item($ouDN)
        if ([string]::IsNullOrEmpty($ADOU)) {
            try {

                add_ou $perunOU
            } catch {

                Write-PerunLog -LogLevel 'WARNING' -LogMessage "Skipping processing groups in $($ouDN). $_|PROCESS_OU"
                [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Skipping processing groups in $($ouDN). $_)")

                continue
            }
        }
        try {
            process_groups $perunOU
        } catch {
            ++$script:COUNTER_GROUPS_FAILED
            Write-PerunLog -LogLevel 'WARNING' -LogMessage "Could not processs group $ouDN. $_|PROCESS_GROUP"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Could not processs group $ouDN. $_)")

            continue
        }
    }
}

function add_ou($ou) {

    try {

        New-ADOrganizationalUnit -Name $ou.ou -Path $($ou.dn -replace "OU=$($ou.ou),")

        ++$script:COUNTER_OUS_ADDED
        Write-PerunLog -LogLevel 'INFO' -LogMessage "Added OU: $($ou.ou).|ADD_OU"
    } catch {

        ++$script:COUNTER_OUS_FAILED
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Failed adding OU: $($ou.ou). $_|ADD_OU"
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Failed adding OU: $($ou.ou). $_)")

        throw
    }
}

$ErrorActionPreference = 'stop'
$global:ProgressPreference = 'SilentlyContinue'

#--------------------- Set environment and variables

try {
    #$global:LOG_DIR_PATH
    #$global:LOG_FILE_PATH
    #$global:TEMP_DIR_PATH
    #$global:EXTRACT_DIR_PATH
    
    $SERVICE_NAME = 'ad-mu'

    # test
    #$EXTRACT_DIR_PATH = 'C:\Scripts\perun\debug'
    #$EXTRACT_DIR_PATH = 'C:\Scripts\perun\test-data'

    $script:config = Get-Content "$PSScriptRoot\process-$SERVICE_NAME.config" -Encoding UTF8 | ConvertFrom-Json

    $FILTER_USERS = $config.FILTER_USERS
    $FILTER_AD_USERS_GET_ATT = $config.FILTER_AD_USERS_GET_ATT
    $FILTER_AD_USERS_UPDATE_ATT = $config.FILTER_AD_USERS_UPDATE_ATT

    $FILTER_GROUPS = $config.FILTER_GROUPS
    $FILTER_AD_GROUPS_GET_ATT = $config.FILTER_AD_GROUPS_GET_ATT
    $FILTER_AD_GROUPS_UPDATE_ATT = $config.FILTER_AD_GROUPS_UPDATE_ATT

    $FILTER_OUS = $config.FILTER_OUS

    $baseDNUsers = Get-Content "$EXTRACT_DIR_PATH\BaseDNUsers" -First 1
    $baseDNGroups = Get-Content "$EXTRACT_DIR_PATH\BaseDNGroups" -First 1
    $baseDNlicenses = Get-Content "$EXTRACT_DIR_PATH\BaseDNLicenses" -First 1

    $script:COUNTER_USERS_ADDED = 0
    $script:COUNTER_USERS_UPDATED = 0
    $script:COUNTER_USERS_FAILED = 0

    $script:COUNTER_GROUPS_ADDED = 0
    $script:COUNTER_GROUPS_UPDATED = 0
    $script:COUNTER_GROUPS_EMPTIED = 0
    $script:COUNTER_GROUPS_FAILED = 0

    $script:COUNTER_OUS_ADDED = 0
    $script:COUNTER_OUS_FAILED = 0

    #--------------------- Start processing

    Import-Module ActiveDirectory

    # Process users
    process_users

    # Process OUs and groups in them
    process_ous

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Users`tAdded: $script:COUNTER_USERS_ADDED, Updated: $script:COUNTER_USERS_UPDATED, Failed: $script:COUNTER_USERS_FAILED"
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Groups`tAdded: $script:COUNTER_GROUPS_ADDED, Updated: $script:COUNTER_GROUPS_UPDATED, Failed: $script:COUNTER_GROUPS_FAILED Emptied: $script:COUNTER_GROUPS_EMPTIED"
    Write-PerunLog -LogLevel 'INFO' -LogMessage "OUs`tAdded: $script:COUNTER_OUS_ADDED, Failed: $script:COUNTER_OUS_FAILED"

    if ($script:COUNTER_USERS_FAILED -or $script:COUNTER_GROUPS_FAILED -or $script:COUNTER_OUS_FAILED) {
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Some AD updates failed."
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Some AD updates failed.)")

        return 2
    }

    return 0
} catch {

    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}