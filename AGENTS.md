# AGENTS.md

## Overview

Single-repo PowerShell script (`Sync-AADGroupMembers.ps1`) that syncs Azure AD security group membership with a text file of email addresses using Azure CLI (`az ad group`).

## Dependencies

- PowerShell 7+ on Windows 11
- Azure CLI (`az`) — logged in via `az login`

## No build/test/CI

There is no build step, test suite, linter, or CI pipeline. Verify changes by running:

```powershell
.\Sync-AADGroupMembers.ps1 -GroupName "Test Group" -MemberFile ".\members.txt" -WhatIf
```

`-WhatIf` is supported via `[CmdletBinding(SupportsShouldProcess)]` — it previews adds/removes without applying them.

## Key details

- The script requires an active `az login` session. It checks login status on startup.
- Member file format: one email per line, `#` comments and blank lines ignored, case-insensitive, duplicates deduplicated.
- The script does a **full sync** — members not in the file are **removed** from the group. This is intentional; do not change to add-only without explicit request.
- User lookup matches on both `Mail` and `UserPrincipalName` fields.
