<#
.SYNOPSIS
    Fixes the repeated "Downloading Antigravity Backend (win32-x64)..." loop in the VS Code Google Antigravity extension.

.DESCRIPTION
    1. Full Fix (Default):
       - Increases execution timeout from 5s to 30s (prevents Defender cold-start kill).
       - Adds interactive update confirmation prompt ("Update", "Later (1 day)", "Skip for 3 days")
         so rapid daily backend releases do not trigger recurring 200MB background downloads without your consent.
    2. Timeout Only:
       - Increases timeout from 5s to 30s.
    3. Restore:
       - Restores original extension.js from extension.js.bak.

.PARAMETER Full
    Applies Full Fix (Timeout + Update Confirmation Prompt & Snooze).

.PARAMETER TimeoutOnly
    Applies Timeout Fix only (5s -> 30s).

.PARAMETER Restore
    Restores extension.js from extension.js.bak.

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
    # Interactive menu if run with no parameters in an interactive shell
    if ([Environment]::UserInteractive) {
        Write-Host "Select an option:"
        Write-Host "  [1] Full Fix (30s Timeout + Update Prompt & Snooze) [Recommended]" -ForegroundColor Green
        Write-Host "      - Fixes Defender timeout (5s -> 30s)"
        Write-Host "      - Prompts before downloading daily updates (Update / Later 1 day / Skip 3 days)"
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
    $extJsPath = Join-Path $folder.FullName "extension.js"
    $bakPath   = Join-Path $folder.FullName "extension.js.bak"

    Write-Info "Found extension: $($folder.Name)"

    if (-not (Test-Path $extJsPath)) {
        Write-Warn "extension.js not found in $($folder.FullName). Skipping."
        continue
    }

    if ($Mode -eq "Restore") {
        if (Test-Path $bakPath) {
            Copy-Item -Path $bakPath -Destination $extJsPath -Force
            Write-Success "Restored original extension.js from backup."
        } else {
            Write-Warn "No backup found at $bakPath to restore."
        }
        continue
    }

    # Backup if not already backed up
    if (-not (Test-Path $bakPath)) {
        Copy-Item -Path $extJsPath -Destination $bakPath
        Write-Success "Created pristine backup at: $bakPath"
    } else {
        Write-Info "Existing backup found. Preserving original backup."
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

    # 2. Interactive Update Confirmation Prompt & Snooze (Full Fix)
    if ($Mode -eq "Full") {
        if ($content.Contains("antigravity.updatePostponedUntil")) {
            Write-Info "Interactive update confirmation prompt is already active."
        } else {
            $regex1 = '(var d=b\(await c\(hb\(w,Ga\.MIN_AGY_VERSION,k\)\)\);let ja=Ga\.MIN_AGY_VERSION;a=!1;if\(d\)\{)'
            $inj1   = '$1let _pu=g.globalState.get("antigravity.updatePostponedUntil");if(_pu&&Date.now()<_pu){k.appendLine(`[INSTALL] Update checks are postponed until ${new Date(_pu).toLocaleString()}. Continuing with existing binary v${d}.`);return w;}'

            $regex2 = '(Skipping download\.`\),\s*w;)(let Ub=)'
            $inj2   = '$1if(d&&!cb(d,ja)){let _ans=b(await c(l.window.showInformationMessage(`Antigravity Backend update (v${ja}) is available (current: v${d}). Update now?`,"Update","Later (1 day)","Skip for 3 days")));if(_ans!=="Update"){let _hrs=_ans==="Skip for 3 days"?72:24;b(await c(g.globalState.update("antigravity.updatePostponedUntil",Date.now()+_hrs*3600000)));k.appendLine(`[INSTALL] User chose ''${_ans||"Dismiss"}''. Postponing updates for ${_hrs}h. Continuing with existing binary v${d}.`);return w;}}$2'

            if (($content -match $regex1) -and ($content -match $regex2)) {
                $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regex1, $inj1)
                $content = [System.Text.RegularExpressions.Regex]::Replace($content, $regex2, $inj2)
                $modified = $true
                Write-Success "Enabled interactive update prompt & snooze (1-day / 3-day quiet mode)."
            } else {
                Write-Warn "Could not match update confirmation injection points. Upstream code may have changed."
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
