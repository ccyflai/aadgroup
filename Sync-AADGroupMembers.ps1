<#
.SYNOPSIS
    Synchronizes Azure AD security group membership with a text file of email addresses.

.DESCRIPTION
    Reads email addresses from a text file (one per line) and ensures the AAD group
    membership matches exactly. Members not in the file are removed; addresses in the
    file but not in the group are added.

    Uses Azure CLI (az) instead of the Microsoft Graph PowerShell SDK, so no admin
    approval for Graph PowerShell modules is required.

.PARAMETER GroupName
    The display name of the AAD security group.

.PARAMETER MemberFile
    Path to a text file containing one email address per line.

.PARAMETER WhatIf
    Preview changes without applying them.

.NOTES
    Prerequisites:
        - Azure CLI installed (https://aka.ms/installazurecli)
        - Logged in: az login

.EXAMPLE
    .\Sync-AADGroupMembers.ps1 -GroupName "My Security Group" -MemberFile ".\members.txt"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$GroupName,

    [Parameter(Mandatory)]
    [string]$MemberFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Verify az CLI is available and logged in ---
try {
    $null = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not logged in to Azure CLI. Run 'az login' first."
        return
    }
} catch {
    Write-Error "Azure CLI (az) not found. Install from https://aka.ms/installazurecli"
    return
}

# --- Read and validate the member file ---
if (-not (Test-Path $MemberFile)) {
    Write-Error "Member file not found: $MemberFile"
    return
}

$desiredEmails = Get-Content $MemberFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" -and $_ -notmatch "^\s*#" } |
    ForEach-Object { $_.ToLower() } |
    Select-Object -Unique

if ($desiredEmails.Count -eq 0) {
    Write-Error "No email addresses found in $MemberFile"
    return
}

Write-Host "Desired members from file: $($desiredEmails.Count)"

# --- Verify group exists ---
$groupsJson = az ad group list --filter "displayName eq '$GroupName'" --query "[].{id:id, displayName:displayName}" -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to search for group '$GroupName'. Verify your permissions."
    return
}
$matchedGroups = $groupsJson | ConvertFrom-Json

if ($matchedGroups.Count -eq 0) {
    Write-Error "No AAD group found with name '$GroupName'."
    return
}
if ($matchedGroups.Count -gt 1) {
    Write-Error "Multiple AAD groups found with name '$GroupName'. Use an exact group ID instead:"
    $matchedGroups | ForEach-Object { Write-Host "  $($_.id) - $($_.displayName)" }
    return
}
$groupId = $matchedGroups[0].id
$group = $matchedGroups[0]
Write-Host "Target group: $($group.displayName)"

# --- Get current group members ---
$membersJson = az ad group member list --group $GroupId --query "[].{id:id, mail:mail, upn:userPrincipalName}" -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to list group members: $membersJson"
    return
}
$currentMembers = $membersJson | ConvertFrom-Json

$currentLookup = @{}
foreach ($member in $currentMembers) {
    $email = ($member.mail ?? $member.upn)
    if ($email) {
        $currentLookup[$email.ToLower()] = $member.id
    }
}

Write-Host "Current members in group: $($currentLookup.Count)"

# --- Resolve desired emails to user IDs ---
$desiredLookup = @{}
$notFound = @()

foreach ($email in $desiredEmails) {
    $userJson = az ad user list --filter "mail eq '$email' or userPrincipalName eq '$email'" --query "[0].id" -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($userJson)) {
        Write-Warning "User not found in AAD: $email"
        $notFound += $email
        continue
    }
    $desiredLookup[$email] = $userJson.Trim()
}

if ($notFound.Count -gt 0) {
    Write-Warning "The following emails were not found in AAD:"
    $notFound | ForEach-Object { Write-Warning "  $_" }
}

# --- Calculate additions and removals ---
$toAdd = $desiredLookup.Keys | Where-Object { -not $currentLookup.ContainsKey($_) }
$toRemove = $currentLookup.Keys | Where-Object { -not $desiredLookup.ContainsKey($_) }

Write-Host "`nChanges:"
Write-Host "  Add:    $(@($toAdd).Count)"
Write-Host "  Remove: $(@($toRemove).Count)"
Write-Host ""

# --- Apply additions ---
foreach ($email in $toAdd) {
    $userId = $desiredLookup[$email]
    if ($PSCmdlet.ShouldProcess($email, "Add to group")) {
        $result = az ad group member add --group $GroupId --member-id $userId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [+] Added: $email"
        } else {
            Write-Warning "  Failed to add $email - $result"
        }
    }
}

# --- Apply removals ---
foreach ($email in $toRemove) {
    $memberId = $currentLookup[$email]
    if ($PSCmdlet.ShouldProcess($email, "Remove from group")) {
        $result = az ad group member remove --group $GroupId --member-id $memberId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [-] Removed: $email"
        } else {
            Write-Warning "  Failed to remove $email - $result"
        }
    }
}

Write-Host "`nSync complete."
