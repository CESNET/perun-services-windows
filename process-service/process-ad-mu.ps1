#3.0.0

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

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Processing users."

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

    # Create hashtable from user attributes
    $userAttributesHash = @{ }
    $($user.PSObject.Properties) | ForEach-Object { if (($_.Value -ne $null) -and ($_.name -notin 'samaccountname', 'dn')) { $userAttributesHash[$_.Name] = $_.Value } }

    #cn = samaccountname; dn generates automatically

    New-ADUser  -Name $user.samAccountName `
        -OtherAttributes $userAttributesHash `
        -Path $($user.dn -replace "CN=$($user.cn),")

    ++$script:COUNTER_USERS_ADDED
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Added user: $($user.samAccountName).|ADD_USER"
}

function update_user($user, $updateUser) {

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
}

function process_groups() {

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Processing groups and members."

    # Create hashtable from Perun input
    $perunGroupsMap = @{ }
    $(Get-Content ("$EXTRACT_DIR_PATH\$SERVICE_NAME" + "_groups.json") -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $perunGroupsMap.Add($_.cn, $_) }
    
    # Create hashtable from AD export
    $ADGroupsMap = @{ }
    Get-ADGroup -SearchBase $baseDNGroups -Filter $FILTER_GROUPS -Properties $FILTER_AD_GROUPS_GET_ATT -SearchScope subtree | Where-Object { $_ -ne $null } | ForEach-Object { $ADGroupsMap.Add($_.Name, $_) }
    

    ForEach ($perunGroup in $($perunGroupsMap.Values)) {
        $groupCN = $perunGroup.cn

        $ADGroup = $ADGroupsMap.Item($groupCN)
        if ([string]::IsNullOrEmpty($ADGroup)) {

            add_group $perunGroup
        } else {

            update_group $ADGroup $perunGroup
        }

        # Update group members
        process_group_members $perunGroup
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

    $groupAttributesHash = @{ }
    $($group.PSObject.Properties) | ForEach-Object { if (($_.Value -ne $null) -and ($_.name -notin 'samaccountname', 'dn', 'members', 'cn')) { $groupAttributesHash[$_.Name] = $_.Value } }

    New-ADgroup -Name $group.samAccountName `
        -GroupScope Global `
        -OtherAttributes $groupAttributesHash `
        -Path $($group.dn -replace "CN=$($group.cn),")

    ++$script:COUNTER_GROUPS_ADDED
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Added group: $($group.cn).|ADD_GROUP"
}

function update_group($group, $updateGroup) {

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
}

function empty_group ($group) {

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
}

function process_group_members ($updateGroup) {

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
}


function process_ous {

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Processing OUs."

    # Get the input file
    $perunOUs = Get-Content ("$EXTRACT_DIR_PATH\$SERVICE_NAME" + '_ous.json') -Encoding UTF8 | ConvertFrom-Json

    # Create hashtable from AD export
    $ADOUsMap = @{ }
    Get-ADOrganizationalUnit -SearchBase $baseDNgroups -Filter $FILTER_OUS -SearchScope subtree | Where-Object { $_ -ne $null } | ForEach-Object { $ADOUsMap.Add($_.DistinguishedName, $_) }

    ForEach ($perunOU in $perunOUs) {
        $ouDN = $perunOU.dn

        $ADOU = $ADOUsMap.Item($ouDN)
        if ([string]::IsNullOrEmpty($ADOU)) {

            add_ou $perunOU
        }
    }
}

function add_ou($ou) {

    New-ADOrganizationalUnit -Name $ou.ou -Path $($ou.dn -replace "OU=$($ou.ou),")

    ++$script:COUNTER_OUS_ADDED
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Added OU: $($ou.ou).|ADD_OU"
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

    # Needs to exist
    $baseDNUsers = Get-Content "$EXTRACT_DIR_PATH\BaseDNUsers" -First 1
    # Needs to exist
    $baseDNGroups = Get-Content "$EXTRACT_DIR_PATH\BaseDNGroups" -First 1
    # Just for checking if a license group is not being emptied
    $baseDNlicenses = Get-Content "$EXTRACT_DIR_PATH\BaseDNLicenses" -First 1

    $script:COUNTER_USERS_ADDED = 0
    $script:COUNTER_USERS_UPDATED = 0

    $script:COUNTER_GROUPS_ADDED = 0
    $script:COUNTER_GROUPS_UPDATED = 0
    $script:COUNTER_GROUPS_EMPTIED = 0

    $script:COUNTER_OUS_ADDED = 0

    #--------------------- Start processing

    Import-Module ActiveDirectory

    # Process users
    process_users

    # Process OUs
    process_ous

    # Process groups and group membership
    process_groups

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Users`tAdded: $script:COUNTER_USERS_ADDED, Updated: $script:COUNTER_USERS_UPDATED"
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Groups`tAdded: $script:COUNTER_GROUPS_ADDED, Updated: $script:COUNTER_GROUPS_UPDATED, Emptied: $script:COUNTER_GROUPS_EMPTIED"
    Write-PerunLog -LogLevel 'INFO' -LogMessage "OUs`tAdded: $script:COUNTER_OUS_ADDED"

    return 0
} catch {

    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}