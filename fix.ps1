<#
.SYNOPSIS
    Fixes the repeated "Downloading Antigravity Backend (win32-x64)..." loop in the VS Code Google Antigravity extension.

.DESCRIPTION
    1. Full Fix (Default):
       - Increases execution timeout from 5s to 30s + adds transient process lock retry.
       - Download Gatekeeper: If the binary exists on disk, intercepts ANY download attempts and asks first.
       - Prompts before downloading updates with exact download size.
       - Options: [Update], [Later (1 day)], [Skip for 3 days], [Disable update checks permanently].
       - Confirms your selection and guides you to Extension Settings if you want to change it later.
       - Contributes settings ('antigravity.updateCheckMode') and Command Palette actions ('Check for Backend Updates').
    2. Timeout Only:
       - Increases timeout from 5s to 30s.
    3. Restore:
       - Restores original extension.js and package.json from backup.

.PARAMETER Full
    Applies Full Fix (Timeout + Download Gatekeeper, Size, Settings & Commands).

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
        Write-Host "  [1] Full Fix (Timeout + Download Gatekeeper & Settings) [Recommended]" -ForegroundColor Green
        Write-Host "      - Fixes Defender timeout (5s -> 30s) + transient process lock retry"
        Write-Host "      - Download Gatekeeper: Never downloads if binary already exists on disk"
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
    $extJsPath   = Join-Path $folder.FullName "extension.js"
    $extJsBak    = Join-Path $folder.FullName "extension.js.bak"
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

    # Read from pristine backup to ensure clean injection
    $content = [System.IO.File]::ReadAllText($extJsBak, [System.Text.Encoding]::UTF8)
    $modified = $false

    # 1. Timeout Patch (5s -> 30s)
    $targetTimeout = 'Ha(a,["--version"],{timeout:5E3})'
    $repTimeout    = 'Ha(a,["--version"],{timeout:3E4})'
    if ($content.Contains($targetTimeout)) {
        $content = $content.Replace($targetTimeout, $repTimeout)
        $modified = $true
        Write-Success "Increased version check timeout from 5s to 30s."
    }

    # 2. Add retry logic to handle transient process lock / EBUSY
    $targetExec = 'let {stdout:m,stderr:p}=c(await d(Ha(a,["--version"],{timeout:3E4})))'
    $repExec    = 'let _vRes;try{_vRes=c(await d(Ha(a,["--version"],{timeout:3E4})))}catch(_fe){c(await d(new Promise(_r=>setTimeout(_r,300))));_vRes=c(await d(Ha(a,["--version"],{timeout:3E4})))}let {stdout:m,stderr:p}=_vRes'
    if ($content.Contains($targetExec)) {
        $content = $content.Replace($targetExec, $repExec)
        $modified = $true
        Write-Success "Added retry logic for binary execution."
    }

    # 3. Full Fix: Enhanced Entrance, Download Gatekeeper & Settings
    if ($Mode -eq "Full") {
        $targetEntrance = 'var d=b(await c(hb(w,Ga.MIN_AGY_VERSION,k)));let ja=Ga.MIN_AGY_VERSION;a=!1;'
        $repEntrance    = 'var d=b(await c(hb(w,Ga.MIN_AGY_VERSION,k)));let _agyInstalledVer=d;let ja=Ga.MIN_AGY_VERSION;a=!1;let _agyCfg=l.workspace.getConfiguration("antigravity");let _agyMode=_agyCfg.get("updateCheckMode")||"prompt";let _agySnooze=_agyCfg.get("updateSnoozeUntil")||g.globalState.get("antigravity.updatePostponedUntil");if(!globalThis.__agyForceCheck){if(_agyMode==="disabled"){k.appendLine(`[INSTALL] Automatic update checks are disabled in settings (antigravity.updateCheckMode=disabled). Continuing with existing binary.`);return w;}if(_agySnooze&&Date.now()<Number(_agySnooze)){k.appendLine(`[INSTALL] Update checks are silenced until ${new Date(Number(_agySnooze)).toLocaleString()}. Continuing with existing binary.`);return w;}}'
        if ($content.Contains($targetEntrance)) {
            $content = $content.Replace($targetEntrance, $repEntrance)
            $modified = $true
            Write-Success "Injected settings & snooze check at installer entry point."
        }

        $targetUb = 'let Ub=async Bb=>{'
        $repUb    = 'let _agyExists=!1;try{b(await c(fa.promises.access(w,fa.constants.F_OK))),_agyExists=!0}catch{}if(_agyExists){if(!globalThis.__agyForceCheck){if(_agyMode==="disabled"){k.appendLine(`[INSTALL] Download blocked: updateCheckMode is disabled. Using existing binary at ${w}.`);return w;}if(_agySnooze&&Date.now()<Number(_agySnooze)){k.appendLine(`[INSTALL] Download blocked: updates silenced until ${new Date(Number(_agySnooze)).toLocaleString()}. Using existing binary at ${w}.`);return w;}}if(_agyMode!=="always"){globalThis.__agyPromptShown=!0;let _curVer=_agyInstalledVer||"1.4.5";try{let {stdout:_s}=b(await c(Ha(w,["--version"],{timeout:3E4})));let _m=_s.match(/(\d+\.\d+\.\d+[^ \t\n\r]*)/);if(_m)_curVer=_m[1];}catch{}let _sz="~76 MB (~202 MB uncompressed)";try{let _murl=`${V}/manifests/${process.platform==="win32"?"windows":process.platform}_${process.arch==="x64"?"amd64":process.arch}.json`;let _mres=b(await c(ta(_murl,{signal:AbortSignal.timeout(1500)})));if(_mres&&_mres.status===200){let _mdata=b(await c(_mres.json()));let _bin=tb(_mdata,process.platform,process.arch);if(_bin&&_bin.url){let _hres=b(await c(ta(_bin.url,{method:"HEAD",signal:AbortSignal.timeout(1500)})));let _cl=_hres&&_hres.headers&&_hres.headers.get("content-length");if(_cl){_sz=`${(Number(_cl)/(1024*1024)).toFixed(1)} MB (~202 MB uncompressed)`;}}}}catch{}let _promptMsg=`Antigravity Backend Update (v${ja}) is available (current: v${_curVer}). Update now?\n\nDownload size: ${_sz}`;let _ans=b(await c(l.window.showInformationMessage(_promptMsg,"Update","Later (1 day)","Skip for 3 days","Disable update checks permanently")));if(_ans==="Update"){b(await c(g.globalState.update("antigravity.updatePostponedUntil",0)));try{_agyCfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);}catch{}}else if(_ans==="Later (1 day)"){let _until=Date.now()+86400000;b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));try{_agyCfg.update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch{}l.window.showInformationMessage("Antigravity update check delayed for 1 day. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");k.appendLine(`[INSTALL] User chose ''Later (1 day)''. Continuing with existing binary v${_curVer}.`);return w;}else if(_ans==="Skip for 3 days"){let _until=Date.now()+259200000;b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));try{_agyCfg.update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch{}l.window.showInformationMessage("Antigravity update checks paused for 3 days. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");k.appendLine(`[INSTALL] User chose ''Skip for 3 days''. Continuing with existing binary v${_curVer}.`);return w;}else if(_ans==="Disable update checks permanently"){b(await c(g.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER)));try{_agyCfg.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);_agyCfg.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);}catch{}l.window.showInformationMessage("Automatic update checks disabled permanently. Note: This preference cannot be changed from the popup; you can re-enable checks in Extension Settings or run ''Antigravity: Check for Backend Updates'' from the Command Palette.");k.appendLine(`[INSTALL] User chose ''Disable update checks permanently''. Continuing with existing binary v${_curVer}.`);return w;}else{k.appendLine(`[INSTALL] Update prompt dismissed. Continuing with existing binary v${_curVer}.`);return w;}}}let Ub=async Bb=>{'
        if ($content.Contains($targetUb)) {
            $content = $content.Replace($targetUb, $repUb)
            $modified = $true
            Write-Success "Injected download gatekeeper before Ub (prevents any unintended downloads)."
        }

        $regexCmd = '(a\.subscriptions\.push\(l\.commands\.registerCommand\("antigravity\.openSettings",\s*async\s+[a-zA-Z0-9_]+\s*=>\s*\{.*?\}\)\);)'
        $repCmd   = '$1a.subscriptions.push(l.commands.registerCommand("antigravity.checkForBackendUpdates",async()=>{l.window.withProgress({location:l.ProgressLocation.Notification,title:"Checking for Antigravity backend updates..."},async()=>{globalThis.__agyForceCheck=true;globalThis.__agyPromptShown=false;try{let _cfg=l.workspace.getConfiguration("antigravity");await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",0);await cc.AntigravityServerManager.getInstance().acquireInstalledBinaryPath(a);if(!globalThis.__agyPromptShown){l.window.showInformationMessage("Antigravity backend is up to date.");}}catch(_err){l.window.showErrorMessage(`Update check failed: ${_err.message}`);}finally{delete globalThis.__agyForceCheck;delete globalThis.__agyPromptShown;}});}));a.subscriptions.push(l.commands.registerCommand("antigravity.configureUpdateSettings",async()=>{let _pick=await l.window.showQuickPick([{label:"$(check) Enable Automatic Updates (Prompt on update)",description:"Prompt before downloading with download size",action:"prompt"},{label:"$(clock) Pause Updates for 1 Day",description:"Silence update checks for 24 hours",action:"pause1d"},{label:"$(clock) Pause Updates for 3 Days",description:"Silence update checks for 72 hours",action:"pause3d"},{label:"$(clock) Pause Updates for 1 Week",description:"Silence update checks for 7 days",action:"pause7d"},{label:"$(circle-slash) Disable Automatic Updates Permanently",description:"Never check automatically; manual check only",action:"disabled"},{label:"$(gear) Open Antigravity Settings",description:"Open VS Code Settings filtered to Antigravity",action:"settings"}],{placeHolder:"Configure Antigravity Backend Update Behavior"});if(!_pick)return;let _cfg=l.workspace.getConfiguration("antigravity");if(_pick.action==="prompt"){await _cfg.update("updateCheckMode","prompt",l.ConfigurationTarget.Global);await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",0);l.window.showInformationMessage("Antigravity updates set to Prompt mode. Snooze cleared.");}else if(_pick.action==="pause1d"){let _u=Date.now()+86400000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 1 day.");}else if(_pick.action==="pause3d"){let _u=Date.now()+259200000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 3 days.");}else if(_pick.action==="pause7d"){let _u=Date.now()+7*86400000;await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",_u);l.window.showInformationMessage("Antigravity updates paused for 1 week.");}else if(_pick.action==="disabled"){await _cfg.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);await _cfg.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);await a.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER);l.window.showInformationMessage("Antigravity automatic update checks disabled permanently.");}else if(_pick.action==="settings"){l.commands.executeCommand("workbench.action.openSettings","antigravity");}}));'

        if ($content -match $regexCmd) {
            $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regexCmd, $repCmd)
            $modified = $true
            Write-Success "Registered manual update check & configuration commands."
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
