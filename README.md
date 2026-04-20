# Sync-AADGroupMembers

Synchronizes Azure AD security group membership with a text file of email addresses.

## Prerequisites

- **Windows 11** with PowerShell 7+
- **Azure CLI** installed ([install guide](https://aka.ms/installazurecli))
- **Azure CLI logged in** (`az login`)

## Usage

```powershell
.\Sync-AADGroupMembers.ps1 -GroupName "My Security Group" -MemberFile ".\members.txt"
```

### Parameters

| Parameter | Description |
|-----------|-------------|
| `GroupName` | Display name of the AAD security group |
| `MemberFile` | Path to text file with one email per line |

### Preview Mode

Use `-WhatIf` to preview changes without applying them:

```powershell
.\Sync-AADGroupMembers.ps1 -GroupName "My Security Group" -MemberFile ".\members.txt" -WhatIf
```

## Member File Format

```
# Lines starting with # are comments
user1@example.com
user2@example.com
alias@example.com
```

- One email per line
- Blank lines and `#` comments are ignored
- Case-insensitive
- Duplicates are removed automatically

## How It Works

1. Reads email addresses from the member file
2. Looks up the AAD group by name
3. Gets current group members
4. **Removes** members not in the file
5. **Adds** members from the file not already in the group

> **Warning**: This is a full sync. Members not in the file will be removed from the group.

## Examples

### Initial Setup

```powershell
# Install Azure CLI (if needed)
winget install Microsoft.AzureCLI

# Login to Azure
az login

# Run the sync
.\Sync-AADGroupMembers.ps1 -GroupName "App Owners" -MemberFile ".\owners.txt"
```

### Update Group Members

Edit `members.txt` then run the script again. The sync will add new emails and remove old ones.

## Troubleshooting

**"Not logged in to Azure CLI"**
```powershell
az login
```

**"No AAD group found"**
Verify the group name matches exactly in Azure AD.

**"Multiple AAD groups found"**
Use an exact group ID instead of the display name to avoid ambiguity.
