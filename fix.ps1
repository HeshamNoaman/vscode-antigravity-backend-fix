# VS Code Google Antigravity Backend Re-download Fixer
# Repository: https://github.com/hesham/vscode-antigravity-backend-fix

[CmdletBinding()]
param(
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Info    { param([string]$Message) Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Warn    { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[-] $Message" -ForegroundColor Red }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   VS Code Google Antigravity Backend Re-download Fixer   " -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$vscodeExtensionsPaths = @(
    (Join-Path $HOME ".vscode\extensions"),
    (Join-Path $HOME ".vscode-insiders\extensions")
)

$targetFolders = @()
foreach ($extPath in $vscodeExtensionsPaths) {
    if (Test-Path $extPath) {
        $found = Get-ChildItem -Path $extPath -Directory -Filter "google.google-antigravity*"
        if ($found) {
            $targetFolders += $found
        }
    }
}

if ($targetFolders.Count -eq 0) {
    Write-Err "Could not find any 'google.google-antigravity' extension in .vscode/extensions."
    Write-Warn "Make sure the extension is installed in VS Code before running this script."
    exit 1
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
        [System.IO.File]::WriteAllText($extJsPath, $newContent, [System.Text.Encoding]::UTF8)
        Write-Success "Successfully increased version check timeout from 5s to 30s!"
    } elseif ($content.Contains($patchedString)) {
        Write-Info "Extension is already patched with 30s timeout."
    } else {
        $regex = '({timeout:)s*5E3(})'
        if ($content -match $regex) {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($content, '(?<=Ha\([^)]*--version[^)]*\{timeout:)5E3(?=\})', '3E4')
            if ($newContent -ne $content) {
                [System.IO.File]::WriteAllText($extJsPath, $newContent, [System.Text.Encoding]::UTF8)
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
$geminiBin = Join-Path $HOME ".gemini\bin"

if (Test-Path $geminiBin) {
    Write-Info "Found Antigravity binary directory: $geminiBin"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        try {
            Add-MpPreference -ExclusionPath $geminiBin -ErrorAction Stop
            Write-Success "Added Windows Defender exclusion for: $geminiBin"
        } catch {
            Write-Warn "Could not add Defender exclusion automatically: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "Optional Performance Boost: To stop Windows Defender from scanning"
        Write-Warn "the 200MB agy.exe on startup, open PowerShell as Administrator and run:"
        Write-Host "    Add-MpPreference -ExclusionPath `"$geminiBin`"" -ForegroundColor Green
    }
}

Write-Host ""
Write-Success "Done! Restart VS Code for changes to take effect."
