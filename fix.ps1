<#
.SYNOPSIS
    Fixes the repeated "Downloading Antigravity Backend (win32-x64)..." loop in the VS Code Google Antigravity extension.

.DESCRIPTION
    1. Full Fix (Default):
       - Increases execution timeout from 5s to 30s (prevents Defender cold-start kill).
       - Prompts before downloading updates with exact download size.
       - Options: [Update], [Later (1 day)], [Skip for 3 days], [Disable update checks permanently].
       - Confirms your selection and guides you to Extension Settings if you want to change it later.
       - Contributes settings ('antigravity.updateCheckMode') and Command Palette actions ('Check for Backend Updates').
    2. Timeout Only:
       - Increases timeout from 5s to 30s.
    3. Restore:
       - Restores original extension.js and package.json from backup.

.PARAMETER Full
    Applies Full Fix (Timeout + Update Confirmation Prompt, Size, Settings & Commands).

.PARAMETER TimeoutOnly
    Applies Timeout Fix only (5s -> 30s).

.PARAMETER Restore
    Restores extension from backup.

.EXAMPLE
    .\fix.ps1
    .\fix.ps1 -Full
    .\fix.ps1 -TimeoutOnly
    .\fix.ps1 -Restore
#>

[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$TimeoutOnly,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Info    { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Warn    { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

function Write-AtomicFile {
    param(
        [string]$FilePath,
        [string]$Content
    )
    $tmpPath = "$FilePath.tmp"
    try {
        [System.IO.File]::WriteAllText($tmpPath, $Content, [System.Text.Encoding]::UTF8)
        Move-Item -Path $tmpPath -Destination $FilePath -Force
    } catch {
        if (Test-Path $tmpPath) {
            Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   VS Code Google Antigravity Backend Re-download Fixer   " -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$Mode = "Full"

if ($Restore) {
    $Mode = "Restore"
} elseif ($TimeoutOnly) {
    $Mode = "TimeoutOnly"
} elseif ($Full) {
    $Mode = "Full"
} else {
    if ([Environment]::UserInteractive) {
        Write-Host "Select an option:"
        Write-Host "  [1] Full Fix (Timeout + Update Prompt, Size & Settings) [Recommended]" -ForegroundColor Green
        Write-Host "      - Fixes Defender timeout (5s -> 30s)"
        Write-Host "      - Prompts before downloading updates with exact download size"
        Write-Host "      - Options: Update / Later (1 day) / Skip for 3 days / Disable permanently"
        Write-Host "      - Adds Manual Check command and VS Code settings configuration"
        Write-Host "  [2] Timeout Fix Only"
        Write-Host "      - Increases timeout to 30s without update prompt"
        Write-Host "  [3] Restore Original Extension from Backup"
        Write-Host "  [4] Exit"
        Write-Host ""
        $choice = Read-Host "Enter choice [1-4] (default: 1)"
        if ($choice -eq "2") {
            $Mode = "TimeoutOnly"
        } elseif ($choice -eq "3") {
            $Mode = "Restore"
        } elseif ($choice -eq "4") {
            Write-Host "Exiting. No changes made."
            return
        } else {
            $Mode = "Full"
        }
        Write-Host ""
    }
}

$vscodeExtensionsPaths = @(
    (Join-Path $HOME ".vscode\extensions"),
    (Join-Path $HOME ".vscode-insiders\extensions"),
    (Join-Path $HOME ".vscode-oss\extensions"),
    (Join-Path $HOME ".cursor\extensions")
)

$targetFolders = @()
foreach ($extPath in $vscodeExtensionsPaths) {
    if (Test-Path $extPath) {
        $found = Get-ChildItem -Path $extPath -Directory -Filter "google.google-antigravity*" -ErrorAction SilentlyContinue
        if ($found) {
            $targetFolders += $found
        }
    }
}

if ($targetFolders.Count -eq 0) {
    Write-Err "Could not find any 'google.google-antigravity' extension installed."
    Write-Warn "Make sure the extension is installed in VS Code before running this script."
    if ($MyInvocation.Line) { return } else { exit 1 }
}

foreach ($folder in $targetFolders) {
    $extJsPath  = Join-Path $folder.FullName "extension.js"
    $extJsBak   = Join-Path $folder.FullName "extension.js.bak"
    $pkgJsonPath = Join-Path $folder.FullName "package.json"
    $pkgJsonBak  = Join-Path $folder.FullName "package.json.bak"

    Write-Info "Found extension: $($folder.Name)"

    if (-not (Test-Path $extJsPath)) {
        Write-Warn "extension.js not found in $($folder.FullName). Skipping."
        continue
    }

    if ($Mode -eq "Restore") {
        $restored = $false
        if (Test-Path $extJsBak) {
            Copy-Item -Path $extJsBak -Destination $extJsPath -Force
            Write-Success "Restored original extension.js from backup."
            $restored = $true
        }
        if (Test-Path $pkgJsonBak) {
            Copy-Item -Path $pkgJsonBak -Destination $pkgJsonPath -Force
            Write-Success "Restored original package.json from backup."
            $restored = $true
        }
        if (-not $restored) {
            Write-Warn "No backup files found at $($folder.FullName) to restore."
        }
        continue
    }

    # Backup if not already backed up
    if (-not (Test-Path $extJsBak)) {
        Copy-Item -Path $extJsPath -Destination $extJsBak
        Write-Success "Created pristine backup at: $(Split-Path $extJsBak -Leaf)"
    } else {
        Write-Info "Existing extension.js backup found. Preserving original backup."
    }

    if ((Test-Path $pkgJsonPath) -and (-not (Test-Path $pkgJsonBak))) {
        Copy-Item -Path $pkgJsonPath -Destination $pkgJsonBak
        Write-Success "Created pristine backup at: $(Split-Path $pkgJsonBak -Leaf)"
    }

    $content = [System.IO.File]::ReadAllText($extJsPath, [System.Text.Encoding]::UTF8)
    $modified = $false

    # 1. Timeout Patch (5s -> 30s)
    $targetPattern = 'Ha(a,["--version"],{timeout:5E3})'
    $patchedString = 'Ha(a,["--version"],{timeout:3E4})'

    if ($content.Contains($targetPattern)) {
        $content = $content.Replace($targetPattern, $patchedString)
        $modified = $true
        Write-Success "Increased version check timeout from 5s to 30s."
    } elseif ($content.Contains($patchedString)) {
        Write-Info "Timeout fix (30s) is already applied."
    } else {
        $regex = '(\{timeout:)\s*5E3(\})'
        if ($content -match $regex) {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($content, '(?<=Ha\([^)]*--version[^)]*\{timeout:\s*)5E3(?=\s*\})', '3E4')
            if ($newContent -ne $content) {
                $content = $newContent
                $modified = $true
                Write-Success "Increased version check timeout using regex match."
            }
        }
    }

    # 2. Enhanced Prompt, Size, Options & Settings (Full Fix)
    if ($Mode -eq "Full") {
        if ($content.Contains("antigravity.checkForBackendUpdates")) {
            Write-Info "Enhanced update prompt and commands are already active."
        } else {
            # If an earlier simple patch exists, revert to clean backup before re-patching
            if ($content.Contains("antigravity.updatePostponedUntil") -and (Test-Path $extJsBak)) {
                $content = [System.IO.File]::ReadAllText($extJsBak, [System.Text.Encoding]::UTF8)
                $content = $content.Replace($targetPattern, $patchedString)
            }

            $regex1 = '(var d=b\(await c\(hb\(w,Ga\.MIN_AGY_VERSION,k\)\)\);let ja=Ga\.MIN_AGY_VERSION;a=!1;if\(d\)\{)'
            $inj1   = '$1let _cfg=l.workspace.getConfiguration("antigravity");let _mode=_cfg.get("updateCheckMode")||"prompt";if(!globalThis.__agyForceCheck){if(_mode==="disabled"){k.appendLine(`[INSTALL] Automatic update checks are disabled in settings (antigravity.updateCheckMode=disabled). Continuing with existing binary v${d}.`);return w;}let _snooze=_cfg.get("updateSnoozeUntil")||g.globalState.get("antigravity.updatePostponedUntil");if(_snooze&&Date.now()<Number(_snooze)){k.appendLine(`[INSTALL] Update checks are silenced until ${new Date(Number(_snooze)).toLocaleString()}. Continuing with existing binary v${d}.`);return w;}}'

            $regex2 = '(Skipping download\.`\),\s*w;)(let Ub=)'
            $inj2   = '$1if(d&&!cb(d,ja)&&l.workspace.getConfiguration("antigravity").get("updateCheckMode")!=="always"){globalThis.__agyPromptShown=true;let _sz="~76 MB (~202 MB uncompressed)";try{let _murl=`${V}/manifests/${process.platform==="win32"?"windows":process.platform}_${process.arch==="x64"?"amd64":process.arch}.json`;let _mres=b(await c(ta(_murl,{signal:AbortSignal.timeout(1500)})));if(_mres&&_mres.status===200){let _mdata=b(await c(_mres.json()));let _bin=tb(_mdata,process.platform,process.arch);if(_bin&&_bin.url){let _hres=b(await c(ta(_bin.url,{method:"HEAD",signal:AbortSignal.timeout(1500)})));let _cl=_hres&&_hres.headers&&_hres.headers.get("content-length");if(_cl){_sz=`${(Number(_cl)/(1024*1024)).toFixed(1)} MB (~202 MB uncompressed)`;}}}}catch(_e){}let _promptMsg=`Antigravity Backend Update (v${ja}) is available (current: v${d}). Update now?\n\nDownload size: ${_sz}`;let _ans=b(await c(l.window.showInformationMessage(_promptMsg,"Update","Later (1 day)","Skip for 3 days","Disable update checks permanently")));if(_ans==="Update"){b(await c(g.globalState.update("antigravity.updatePostponedUntil",0)));try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);}catch(_e){}}else if(_ans==="Later (1 day)"){let _until=Date.now()+86400000;b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch(_e){}l.window.showInformationMessage("Antigravity update check delayed for 1 day. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");k.appendLine(`[INSTALL] User chose ''Later (1 day)''. Continuing with existing binary v${d}.`);return w;}else if(_ans==="Skip for 3 days"){let _until=Date.now()+259200000;b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch(_e){}l.window.showInformationMessage("Antigravity update checks paused for 3 days. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");k.appendLine(`[INSTALL] User chose ''Skip for 3 days''. Continuing with existing binary v${d}.`);return w;}else if(_ans==="Disable update checks permanently"){b(await c(g.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER)));try{let _c=l.workspace.getConfiguration("antigravity");_c.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);_c.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);}catch(_e){}l.window.showInformationMessage("Automatic update checks disabled permanently. Note: This preference cannot be changed from the popup; you can re-enable checks in Extension Settings or run ''Antigravity: Check for Backend Updates'' from the Command Palette.");k.appendLine(`[INSTALL] User chose ''Disable update checks permanently''. Continuing with existing binary v${d}.`);return w;}else{return w;}}$2'

            $regex3 = '(a\.subscriptions\.push\(l\.commands\.registerCommand\("antigravity\.openSettings",\s*async\s+[a-zA-Z0-9_]+\s*=>\s*\{.*?\}\)\);)'
            $inj3   = '$1a.subscriptions.push(l.commands.registerCommand("antigravity.checkForBackendUpdates",async()=>{l.window.withProgress({location:l.ProgressLocation.Notification,title:"Checking for Antigravity backend updates..."},async()=>{globalThis.__agyForceCheck=true;globalThis.__agyPromptShown=false;try{let _cfg=l.workspace.getConfiguration("antigravity");await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",0);await cc.AntigravityServerManager.getInstance().acquireInstalledBinaryPath(a);if(!globalThis.__agyPromptShown){l.window.showInformationMessage("Antigravity backend is up to date.");}}catch(_err){l.window.showErrorMessage(`Update check failed: ${_err.message}`);}finally{delete globalThis.__agyForceCheck;delete globalThis.__agyPromptShown;}});}));a.subscriptions.push(l.commands.registerCommand("antigravity.configureUpdateSettings",async()=>{let _pick=await l.window.showQuickPick([{label:"$(check) Enable Automatic Updates (Prompt on update)",description:"Prompt before downloading with download size",action:"prompt"},{label:"$(clock) Pause Updates for 1 Day",description:"Silence update checks for 24 hours",action:"pause1d"},{label:"$(clock) Pause Updates for 3 Days",description:"Silence update checks for 72 hours",action:"pause3d"},{label:"$(clock) Pause Updates for 1 Week",description:"Silence update checks for 7 days",action:"pause7d"},{label:"$(circle-slash) Disable Automatic Updates Permanently",description:"Never check automatically; manual check only",action:"disabled"},{label:"$(gear) Open Antigravity Settings",description:"Open VS Code Settings filtered to Antigravity",action:"settings"}],{placeHolder:"Configure Antigravity Backend Update Behavior"});if(!_pick)return;let _cfg=l.workspace.getConfiguration("antigravity");if(_pick.action==="prompt"){await _cfg.update("updateCheckMode","prompt",l.ConfigurationTarget.Global);await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",0);l.window.showInformationMessage("Antigravity updates set to Prompt mode. Snooze cleared.");}else if(_pick.action==="pause1d"){let _u=Date.now()+86400000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 1 day.");}else if(_pick.action==="pause3d"){let _u=Date.now()+259200000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 3 days.");}else if(_pick.action==="pause7d"){let _u=Date.now()+7*86400000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 1 week.");}else if(_pick.action==="disabled"){await _cfg.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);await _cfg.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER);l.window.showInformationMessage("Antigravity automatic update checks disabled permanently.");}else if(_pick.action==="settings"){l.commands.executeCommand("workbench.action.openSettings","antigravity");}}));'

            if (($content -match $regex1) -and ($content -match $regex2)) {
                $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regex1, $inj1)
                $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regex2, $inj2)
                if ($content -match $regex3) {
                    $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regex3, $inj3)
                } else {
                    Write-Warn "Could not match openSettings registration point for commands in extension.js."
                }
                $modified = $true
                Write-Success "Injected update prompt with download size & command palette controls."
            } else {
                Write-Warn "Could not match update confirmation injection points."
            }
        }

        # Update package.json
        if (Test-Path $pkgJsonPath) {
            try {
                $pkg = Get-Content $pkgJsonPath -Raw | ConvertFrom-Json
                $pkgModified = $false

                if (-not $pkg.contributes.commands) { $pkg.contributes | Add-Member -MemberType NoteProperty -Name "commands" -Value @() }

                $hasCheckCmd = $false
                foreach ($c in $pkg.contributes.commands) {
                    if ($c.command -eq "antigravity.checkForBackendUpdates") { $hasCheckCmd = $true; break }
                }
                if (-not $hasCheckCmd) {
                    $newCmds = @($pkg.contributes.commands) + @([PSCustomObject]@{
                        command  = "antigravity.checkForBackendUpdates"
                        title    = "Check for Backend Updates"
                        category = "Antigravity"
                    }, [PSCustomObject]@{
                        command  = "antigravity.configureUpdateSettings"
                        title    = "Configure Backend Update Settings"
                        category = "Antigravity"
                    })
                    $pkg.contributes.commands = $newCmds
                    $pkgModified = $true
                }

                if (-not $pkg.contributes.configuration.properties."antigravity.updateCheckMode") {
                    $pkg.contributes.configuration.properties | Add-Member -MemberType NoteProperty -Name "antigravity.updateCheckMode" -Value ([PSCustomObject]@{
                        type        = "string"
                        enum        = @("prompt", "disabled", "always")
                        default     = "prompt"
                        description = "Controls how Antigravity backend updates are handled: 'prompt' asks before downloading, 'disabled' stops automatic checks, 'always' auto-downloads."
                    })
                    $pkgModified = $true
                }

                if (-not $pkg.contributes.configuration.properties."antigravity.updateSnoozeUntil") {
                    $pkg.contributes.configuration.properties | Add-Member -MemberType NoteProperty -Name "antigravity.updateSnoozeUntil" -Value ([PSCustomObject]@{
                        type        = "number"
                        default     = 0
                        description = "Timestamp (epoch ms) until which automatic update prompts are silenced."
                    })
                    $pkgModified = $true
                }

                if ($pkgModified) {
                    $newJson = $pkg | ConvertTo-Json -Depth 20
                    Write-AtomicFile -FilePath $pkgJsonPath -Content $newJson
                    Write-Success "Updated package.json with configuration settings & commands."
                }
            } catch {
                Write-Warn "Could not update package.json: $($_.Exception.Message)"
            }
        }
    }

    if ($modified) {
        Write-AtomicFile -FilePath $extJsPath -Content $content
        Write-Success "All patches written safely to extension.js."
    } else {
        Write-Info "No new changes were needed."
    }
}

Write-Host ""
Write-Host "--- Windows Defender Optimization ---" -ForegroundColor Cyan
$geminiBinExe = Join-Path $HOME ".gemini\bin\agy.exe"

if (Test-Path $geminiBinExe) {
    Write-Info "Found Antigravity binary: $geminiBinExe"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        try {
            Add-MpPreference -ExclusionPath $geminiBinExe -ErrorAction Stop
            Write-Success "Added Windows Defender exclusion for: $geminiBinExe"
        } catch {
            Write-Warn "Could not add Defender exclusion automatically: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "Optional Performance Boost: To stop Windows Defender from scanning"
        Write-Warn "the 200MB agy.exe on startup, open PowerShell as Administrator and run:"
        Write-Host "    Add-MpPreference -ExclusionPath `"$geminiBinExe`"" -ForegroundColor Green
    }
}

Write-Host ""
Write-Success "Done! Restart VS Code for changes to take effect."
