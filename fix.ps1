<#
.SYNOPSIS
    Fixes the repeated "Downloading Antigravity Backend (win32-x64)..." loop in the VS Code Google Antigravity extension.

.DESCRIPTION
    1. Full Fix (Default):
       - Increases execution timeout from 5s to 30s + adds transient process lock retry.
       - Download Gatekeeper: If the binary exists on disk, intercepts ANY download attempts and asks first.
       - Prompts before downloading updates with exact download size.
       - Options: [Update], [Later (1d)], [Skip (3d)], [Disable].
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
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($tmpPath, $Content, $utf8NoBom)
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
        Write-Host "      - Options: Update / Later (1d) / Skip (3d) / Disable"
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

    # 1. Timeout Patch (5s -> 30s) + Execution Retry Logic
    $regexExec = [regex]'let\s*\{stdout:\s*([a-zA-Z0-9_$]+),\s*stderr:\s*([a-zA-Z0-9_$]+)\}\s*=\s*([a-zA-Z0-9_$]+)\(await\s+([a-zA-Z0-9_$]+)\(([a-zA-Z0-9_$]+)\(([a-zA-Z0-9_$]+),\s*\["--version"\]\s*,\s*\{timeout:\s*([^}]+)\}\)\)\)'
    $mExec = $regexExec.Match($content)
    if ($mExec.Success) {
        $m = $mExec.Groups[1].Value
        $p = $mExec.Groups[2].Value
        $c = $mExec.Groups[3].Value
        $d = $mExec.Groups[4].Value
        $execFn = $mExec.Groups[5].Value
        $binArg = $mExec.Groups[6].Value

        $repExec = "let _vRes;try{_vRes=$c(await $d($execFn($binArg,[`"--version`"],{timeout:3E4})))}catch(_fe){$c(await $d(new Promise(_r=>setTimeout(_r,300))));_vRes=$c(await $d($execFn($binArg,[`"--version`"],{timeout:3E4})))}let {stdout:$m,stderr:$p}=_vRes"
        $content = $content.Substring(0, $mExec.Index) + $repExec + $content.Substring($mExec.Index + $mExec.Length)
        $modified = $true
        Write-Success "Increased version check timeout from 5s to 30s & added binary retry logic."
    } else {
        $regexSimple = [regex]'([a-zA-Z0-9_$]+\([a-zA-Z0-9_$]+,\["--version"\],\{timeout:)[^}]+(\})'
        if ($regexSimple.IsMatch($content)) {
            $content = $regexSimple.Replace($content, '$13E4$2')
            $modified = $true
            Write-Success "Increased version check timeout from 5s to 30s (fallback pattern)."
        }
    }

    # Bump default version check timeout constant if present
    $regexTimeoutConst = [regex]'DEFAULT_VERSION_CHECK_TIMEOUT_MS\s*=\s*\d+E?\d*'
    if ($regexTimeoutConst.IsMatch($content)) {
        $content = $regexTimeoutConst.Replace($content, 'DEFAULT_VERSION_CHECK_TIMEOUT_MS=3E4')
        $modified = $true
        Write-Success "Bumped DEFAULT_VERSION_CHECK_TIMEOUT_MS to 30s."
    }

    # 2. Full Fix: Enhanced Entrance, Download Gatekeeper & Settings
    if ($Mode -eq "Full") {
        # Discover installer parameters & vscode namespace dynamically
        $regexParams = [regex]'let\s*\{(?=[^}]*\bcontext:\s*([a-zA-Z0-9_$]+))(?=[^}]*\boutputChannel:\s*([a-zA-Z0-9_$]+))[^}]*\}\s*=\s*[a-zA-Z0-9_$]+,\s*([a-zA-Z0-9_$]+)\s*=\s*[a-zA-Z0-9_$]+!=null\?[a-zA-Z0-9_$]+:[a-zA-Z0-9_$]+\(\)'
        $mParams = $regexParams.Match($content)

        $regexVscode = [regex]'([a-zA-Z0-9_$]+)\.workspace\.getConfiguration\("antigravity"\)'
        $mVscode = $regexVscode.Match($content)

        $regexInstallerUrl = [regex]'Initializing update check[\s\S]{1,300}?Checking for updates at releaseBaseUrl=\$\{([a-zA-Z0-9_$]+)\}'
        $mUrl = $regexInstallerUrl.Match($content)
        if (-not $mUrl.Success) {
            $regexUrlFallback = [regex]'releaseBaseUrl=\$\{([a-zA-Z0-9_$]+)\}'
            $mUrl = $regexUrlFallback.Match($content)
        }

        $regexTargetVer = [regex]'(?:let\s+([a-zA-Z0-9_$]+)\s*=\s*[a-zA-Z0-9_$]+\.targetVersion|let\s+([a-zA-Z0-9_$]+)\s*=\s*[a-zA-Z0-9_$]+\.MIN_AGY_VERSION)'
        $mTargetVer = $regexTargetVer.Match($content)
        $targetVerVar = if ($mTargetVer.Success) {
            if ($mTargetVer.Groups[1].Value) { $mTargetVer.Groups[1].Value } else { $mTargetVer.Groups[2].Value }
        } else { $null }

        if ($mParams.Success -and $mVscode.Success -and $mUrl.Success) {
            $ctxVar = $mParams.Groups[1].Value
            $outChanVar = $mParams.Groups[2].Value
            $binPathVar = $mParams.Groups[3].Value
            $vscodeVar = $mVscode.Groups[1].Value
            $urlVar = $mUrl.Groups[1].Value

            # Entrance patch: Check mode and snooze at installer entry point
            $regexInit = [regex]'([a-zA-Z0-9_$]+\.appendLine\(`\[INSTALL\] Initializing update check[\s\S]*?`\);)'
            $mInit = $regexInit.Match($content)

            if ($mInit.Success) {
                $fullInit = $mInit.Groups[1].Value
                $repInit = $fullInit + "let _agyCfg=$vscodeVar.workspace.getConfiguration(`"antigravity`");let _agyMode=_agyCfg.get(`"updateCheckMode`")||`"prompt`";let _agySnooze=_agyCfg.get(`"updateSnoozeUntil`")||$ctxVar.globalState.get(`"antigravity.updatePostponedUntil`");if(!globalThis.__agyForceCheck){let _agyBinExists=!1;try{_agyBinExists=require(`"fs`").existsSync($binPathVar);}catch{}if(_agyBinExists){if(_agyMode===`"disabled`"){$outChanVar.appendLine(```[INSTALL] Automatic update checks are disabled in settings (antigravity.updateCheckMode=disabled). Continuing with existing binary.```);return $binPathVar;}if(_agySnooze&&Date.now()<Number(_agySnooze)){$outChanVar.appendLine(```[INSTALL] Update checks are silenced until `${new Date(Number(_agySnooze)).toLocaleString()}. Continuing with existing binary.```);return $binPathVar;}}}"
                $content = $content.Substring(0, $mInit.Index) + $repInit + $content.Substring($mInit.Index + $mInit.Length)
                $modified = $true
                Write-Success "Injected settings & snooze check at installer entry point."
            } else {
                Write-Warn "Could not locate installer entrance point for snooze/mode check."
            }

            # Gatekeeper: INTERCEPT ANY DOWNLOAD IF BINARY EXISTS ON DISK
            $regexDownload = [regex]'(?:let\s+|,)([a-zA-Z0-9_$]+)\s*=\s*async\s*(?:\([a-zA-Z0-9_$,\s]*\)|[a-zA-Z0-9_$]+)\s*=>\s*\{(?=[\s\S]{1,1000}\[INSTALL\] Checking Antigravity releases)'
            $mDl = $regexDownload.Match($content)
            if ($mDl.Success) {
                $fullDl = $mDl.Groups[0].Value
                $targetVerExpr = if ($targetVerVar) { "(`"v`" + $targetVerVar)" } else { "`"latest`"" }

                $repDl = $fullDl + "let _agyExists=!1;try{_agyExists=require(`"fs`").existsSync($binPathVar);}catch{}if(_agyExists){if(!globalThis.__agyForceCheck){if(_agyMode===`"disabled`"){$outChanVar.appendLine(`"[INSTALL] Download blocked: updateCheckMode is disabled. Using existing binary at `" + $binPathVar);return $binPathVar;}if(_agySnooze&&Date.now()<Number(_agySnooze)){$outChanVar.appendLine(`"[INSTALL] Download blocked: updates silenced until `" + new Date(Number(_agySnooze)).toLocaleString() + `". Using existing binary at `" + $binPathVar);return $binPathVar;}}}if(_agyMode!==`"always`"){globalThis.__agyPromptShown=!0;let _curVer=`"unknown`";try{let _s=require(`"child_process`").execFileSync($binPathVar,[`"--version`"],{timeout:3E4,encoding:`"utf8`"});let _m=_s.match(/(\d+\.\d+\.\d+\S*)/);if(_m)_curVer=_m[1];}catch{}_curVer=_curVer||`"unknown`";let _sz=`"~76 MB (~202 MB uncompressed)`";try{let _murl=$urlVar+`"/manifests/`"+(process.platform===`"win32`"?`"windows`":process.platform)+`"_`"+(process.arch===`"x64`"?`"amd64`":process.arch)+`".json`";let _mres=b(await c(fetch(_murl,{signal:AbortSignal.timeout(1500)})));if(_mres&&_mres.status===200){let _mdata=b(await c(_mres.json()));let _k1=process.platform+`"_`"+process.arch;let _k2=process.platform+`"-`"+process.arch;let _binInfo=_mdata.url?_mdata:(_mdata.binaries&&(_mdata.binaries[_k1]||_mdata.binaries[_k2]));let _bUrl=_binInfo&&(_binInfo.url||_binInfo);if(typeof _bUrl===`"string`"){let _hres=b(await c(fetch(_bUrl,{method:`"HEAD`",signal:AbortSignal.timeout(1500)})));let _cl=_hres&&_hres.headers&&_hres.headers.get(`"content-length`");if(_cl){_sz=(Number(_cl)/(1024*1024)).toFixed(1)+`" MB (~202 MB uncompressed)`";}}}}catch{}if(globalThis.__agyDismissCheckProgress){globalThis.__agyDismissCheckProgress();delete globalThis.__agyDismissCheckProgress;b(await c(new Promise(_r=>setTimeout(_r,100))));}let _promptMsg=`"Antigravity Backend Update (`" + $targetVerExpr + `") is available (current: v`" + _curVer + `") \\u2022 Download size: `" + _sz;let _ans=b(await c($vscodeVar.window.showInformationMessage(_promptMsg,`"Update`",`"Later (1d)`",`"Skip (3d)`",`"Disable`")));if(_ans===`"Update`"){b(await c($ctxVar.globalState.update(`"antigravity.updatePostponedUntil`",0)));try{_agyCfg.update(`"updateSnoozeUntil`",0,$vscodeVar.ConfigurationTarget.Global);}catch{}}else if(_ans===`"Later (1d)`"){let _until=Date.now()+86400000;b(await c($ctxVar.globalState.update(`"antigravity.updatePostponedUntil`",_until)));try{_agyCfg.update(`"updateSnoozeUntil`",_until,$vscodeVar.ConfigurationTarget.Global);}catch{}$vscodeVar.window.showInformationMessage(`"Antigravity update check delayed for 1 day. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.`");$outChanVar.appendLine(`"[INSTALL] User chose 'Later (1d)'. Continuing with existing binary v`" + _curVer + `".`");return $binPathVar;}else if(_ans===`"Skip (3d)`"){let _until=Date.now()+259200000;b(await c($ctxVar.globalState.update(`"antigravity.updatePostponedUntil`",_until)));try{_agyCfg.update(`"updateSnoozeUntil`",_until,$vscodeVar.ConfigurationTarget.Global);}catch{}$vscodeVar.window.showInformationMessage(`"Antigravity update checks paused for 3 days. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.`");$outChanVar.appendLine(`"[INSTALL] User chose 'Skip (3d)'. Continuing with existing binary v`" + _curVer + `".`");return $binPathVar;}else if(_ans===`"Disable`"){b(await c($ctxVar.globalState.update(`"antigravity.updatePostponedUntil`",Number.MAX_SAFE_INTEGER)));try{_agyCfg.update(`"updateCheckMode`",`"disabled`",$vscodeVar.ConfigurationTarget.Global);_agyCfg.update(`"updateSnoozeUntil`",Number.MAX_SAFE_INTEGER,$vscodeVar.ConfigurationTarget.Global);}catch{}$vscodeVar.window.showInformationMessage(`"Automatic update checks disabled permanently. Note: This preference cannot be changed from the popup; you can re-enable checks in Extension Settings or run 'Antigravity: Check for Backend Updates' from the Command Palette.`");$outChanVar.appendLine(`"[INSTALL] User chose 'Disable'. Continuing with existing binary v`" + _curVer + `".`");return $binPathVar;}else{$outChanVar.appendLine(`"[INSTALL] Update prompt dismissed. Continuing with existing binary v`" + _curVer + `".`");return $binPathVar;}}"
                        $content = $content.Substring(0, $mDl.Index) + $repDl + $content.Substring($mDl.Index + $mDl.Length)
                $modified = $true
                Write-Success "Injected download gatekeeper (prevents any unintended downloads)."
            } else {
                Write-Warn "Could not locate download handler function for gatekeeper injection."
            }
        } else {
            Write-Warn "Could not discover installer parameters."
        }
    
        # Commands registration
        $regexCmd = [regex]'([a-zA-Z0-9_$]+)\.subscriptions\.push\(([a-zA-Z0-9_$]+)\.commands\.registerCommand\("antigravity\.openSettings",\s*async\s+([a-zA-Z0-9_$]+)\s*=>\s*\{.*?\}\)\);'
        $mCmd = $regexCmd.Match($content)
        $regexSrv = [regex]'([a-zA-Z0-9_$]+)\.AntigravityServerManager\.getInstance\(\)'
        $mSrv = $regexSrv.Match($content)

        if ($mCmd.Success) {
            $extCtx = $mCmd.Groups[1].Value
            $extVs = $mCmd.Groups[2].Value
            $srvMgr = if ($mSrv.Success) { $mSrv.Groups[1].Value } elseif ($content.Contains("pc.AntigravityServerManager")) { "pc" } else { "`$c" }

            $repCmd = $mCmd.Groups[0].Value + "$extCtx.subscriptions.push($extVs.commands.registerCommand(`"antigravity.checkForBackendUpdates`",async()=>{if(globalThis.__agyCheckingInProgress){$extVs.window.showInformationMessage(`"Antigravity update check is already in progress.`");return;}globalThis.__agyCheckingInProgress=true;globalThis.__agyForceCheck=true;globalThis.__agyPromptShown=false;let _endProgress;const _progressPromise=new Promise(_r=>{_endProgress=_r;});globalThis.__agyDismissCheckProgress=_endProgress;try{let _cfg=$extVs.workspace.getConfiguration(`"antigravity`");await _cfg.update(`"updateSnoozeUntil`",0,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",0);const _progressTask=$extVs.window.withProgress({location:$extVs.ProgressLocation.Notification,title:`"Checking for Antigravity backend updates...`"},()=>_progressPromise);await $srvMgr.AntigravityServerManager.getInstance().acquireInstalledBinaryPath($extCtx);if(globalThis.__agyDismissCheckProgress){globalThis.__agyDismissCheckProgress();delete globalThis.__agyDismissCheckProgress;}await _progressTask;if(!globalThis.__agyPromptShown){let _cur=`"unknown`";try{let _inst=await $srvMgr.AntigravityServerManager.getInstance().getInstalledTargetPath();let _s=require(`"child_process`").execFileSync(_inst,[`"--version`"],{timeout:3E4,encoding:`"utf8`"});let _m=_s.match(/(\d+\.\d+\.\d+\S*)/);if(_m)_cur=_m[1];}catch{}$extVs.window.showInformationMessage(```Antigravity backend is up to date (v`${_cur}).```);}}catch(_err){if(globalThis.__agyDismissCheckProgress){globalThis.__agyDismissCheckProgress();delete globalThis.__agyDismissCheckProgress;}$extVs.window.showErrorMessage(```Update check failed: `${_err.message}```);}finally{if(globalThis.__agyDismissCheckProgress){globalThis.__agyDismissCheckProgress();delete globalThis.__agyDismissCheckProgress;}delete globalThis.__agyCheckingInProgress;delete globalThis.__agyForceCheck;delete globalThis.__agyPromptShown;}}));$extCtx.subscriptions.push($extVs.commands.registerCommand(`"antigravity.configureUpdateSettings`",async()=>{let _pick=await $extVs.window.showQuickPick([{label:`"`$(check) Enable Automatic Updates (Prompt on update)`",description:`"Prompt before downloading with download size`",action:`"prompt`"},{label:`"`$(clock) Pause Updates for 1 Day`",description:`"Silence update checks for 24 hours`",action:`"pause1d`"},{label:`"`$(clock) Pause Updates for 3 Days`",description:`"Silence update checks for 72 hours`",action:`"pause3d`"},{label:`"`$(clock) Pause Updates for 1 Week`",description:`"Silence update checks for 7 days`",action:`"pause7d`"},{label:`"`$(circle-slash) Disable Automatic Updates Permanently`",description:`"Never check automatically; manual check only`",action:`"disabled`"},{label:`"`$(gear) Open Antigravity Settings`",description:`"Open VS Code Settings filtered to Antigravity`",action:`"settings`"}],{placeHolder:`"Configure Antigravity Backend Update Behavior`"});if(!_pick)return;let _cfg=$extVs.workspace.getConfiguration(`"antigravity`");if(_pick.action===`"prompt`"){await _cfg.update(`"updateCheckMode`",`"prompt`",$extVs.ConfigurationTarget.Global);await _cfg.update(`"updateSnoozeUntil`",0,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",0);$extVs.window.showInformationMessage(`"Antigravity updates set to Prompt mode. Snooze cleared.`");}else if(_pick.action===`"pause1d`"){let _u=Date.now()+86400000;await _cfg.update(`"updateSnoozeUntil`",_u,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",_u);$extVs.window.showInformationMessage(`"Antigravity updates paused for 1 day.`");}else if(_pick.action===`"pause3d`"){let _u=Date.now()+259200000;await _cfg.update(`"updateSnoozeUntil`",_u,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",_u);$extVs.window.showInformationMessage(`"Antigravity updates paused for 3 days.`");}else if(_pick.action===`"pause7d`"){let _u=Date.now()+7*86400000;await _cfg.update(`"updateSnoozeUntil`",_u,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",_u);$extVs.window.showInformationMessage(`"Antigravity updates paused for 1 week.`");}else if(_pick.action===`"disabled`"){await _cfg.update(`"updateCheckMode`",`"disabled`",$extVs.ConfigurationTarget.Global);await _cfg.update(`"updateSnoozeUntil`",Number.MAX_SAFE_INTEGER,$extVs.ConfigurationTarget.Global);await $extCtx.globalState.update(`"antigravity.updatePostponedUntil`",Number.MAX_SAFE_INTEGER);$extVs.window.showInformationMessage(`"Antigravity automatic update checks disabled permanently.`");}else if(_pick.action===`"settings`"){$extVs.commands.executeCommand(`"workbench.action.openSettings`",`"antigravity`");}}));"
            $content = $content.Substring(0, $mCmd.Index) + $repCmd + $content.Substring($mCmd.Index + $mCmd.Length)
            $modified = $true
            Write-Success "Registered manual update check & configuration commands."
        } else {
            Write-Warn "Could not locate openSettings registration point for commands."
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
        $tmpCheckPath = "$extJsPath.check.js"
        try {
            [System.IO.File]::WriteAllText($tmpCheckPath, $content, [System.Text.Encoding]::UTF8)
            $checkProc = Start-Process -FilePath "node" -ArgumentList "-c", "`"$tmpCheckPath`"" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            if ($checkProc -and $checkProc.ExitCode -ne 0) {
                Write-Err "Syntax validation FAILED (exit code $($checkProc.ExitCode)). Aborting write to prevent extension breakage."
                Remove-Item -Path $tmpCheckPath -Force -ErrorAction SilentlyContinue
                continue
            }
            Remove-Item -Path $tmpCheckPath -Force -ErrorAction SilentlyContinue
        } catch {
            if (Test-Path $tmpCheckPath) { Remove-Item -Path $tmpCheckPath -Force -ErrorAction SilentlyContinue }
        }
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
