<#
.SYNOPSIS
    Fixes the repeated "Downloading Antigravity Backend (win32-x64)..." loop in the VS Code Google Antigravity extension.

.DESCRIPTION
    The Google Antigravity extension (google.google-antigravity) has a hardcoded 5-second timeout (5E3 ms)
    when verifying the local binary version (`agy.exe --version`).
    On Windows, because agy.exe is ~202 MB, Windows Defender real-time scanning and workspace startup I/O
    frequently delay execution past 5 seconds.
    This causes the extension to assume the backend is missing and re-download the 202 MB binary every time
    VS Code opens.

    This script:
    1. Finds all installed versions of google.google-antigravity across VS Code, Insiders, VSCodium, and Cursor
    2. Creates a backup (extension.js.bak)
    3. Patches the timeout from 5 seconds (5E3) to 30 seconds (3E4) using atomic writes
    4. Checks and offers to add a strictly scoped Windows Defender file exclusion for agy.exe

.PARAMETER Restore
    Restores extension.js from extension.js.bak.

.EXAMPLE
    .\fix.ps1
    .\fix.ps1 -Restore
#>

[CmdletBinding()]
param(
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

    if ($Restore) {
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
        Write-Success "Created backup at: $bakPath"
    } else {
        Write-Info "Existing backup found. Preserving original backup."
    }

    $content = [System.IO.File]::ReadAllText($extJsPath, [System.Text.Encoding]::UTF8)

    $targetPattern = 'Ha(a,["--version"],{timeout:5E3})'
    $patchedString = 'Ha(a,["--version"],{timeout:3E4})'

    if ($content.Contains($targetPattern)) {
        $newContent = $content.Replace($targetPattern, $patchedString)
        Write-AtomicFile -FilePath $extJsPath -Content $newContent
        Write-Success "Successfully increased version check timeout from 5s to 30s!"
    } elseif ($content.Contains($patchedString)) {
        Write-Info "Extension is already patched with 30s timeout."
    } else {
        # Fallback regex search if minification variables or whitespace differ slightly
        $regex = '(\\{timeout:)\\s*5E3(\\})'
        if ($content -match $regex) {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($content, '(?<=Ha\\([^)]*--version[^)]*\\{timeout:\\s*)5E3(?=\\s*\\})', '3E4')
            if ($newContent -ne $content) {
                Write-AtomicFile -FilePath $extJsPath -Content $newContent
                Write-Success "Successfully patched using regex match!"
            } else {
                Write-Warn "Could not find exact pattern. Extension may have been updated to a new version."
            }
        } else {
            Write-Warn "Target timeout pattern not found. The extension might already be fixed upstream or updated."
        }
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
