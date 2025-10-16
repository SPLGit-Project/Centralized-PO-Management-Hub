<# 
  export-unpack.ps1
  PURPOSE:
  1) Auth to your Dev Power Platform environment
  2) Export the unmanaged solution zip
  3) Unpack it to source-controlled folders (./powerplatform/solution-src)
  4) (Optional) Unpack any Canvas apps (.msapp) to YAML source

  HOW TO RUN (from VS Code Terminal, opened at repo root):
    pwsh -File .\scripts\export-unpack.ps1 `
      -EnvUrl "https://<YOUR-DEV-ORG>.crm.dynamics.com" `
      -SolutionName "Centralized PO Management Hub"

  NOTES:
  - "SolutionName" is the display name shown in Solutions. If export fails, use Unique Name:
      pac solution list
      # Look for "Unique Name" (e.g., spl_centralizedpomanager)
      and pass that to -SolutionUniqueName instead.
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$EnvUrl,
  [Parameter(Mandatory = $false)]
  [string]$SolutionName = "",
  [Parameter(Mandatory = $false)]
  [string]$SolutionUniqueName = ""
)

$ErrorActionPreference = "Stop"

# --- Paths (relative to repo root) ---
$repoRoot = (Get-Location).Path
$workDir  = Join-Path $repoRoot "powerplatform"
$srcDir   = Join-Path $workDir  "solution-src"
$zipDir   = Join-Path $workDir  "exports"
New-Item -ItemType Directory -Force -Path $workDir,$srcDir,$zipDir | Out-Null

# --- Ensure PAC is available ---
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
  Write-Error "PAC CLI not found. Install with: npm i -g @microsoft/powerplatform-cli"
}

Write-Host "== Power Platform auth =="
# Save/activate a profile for Dev
pac auth create --url $EnvUrl --name Dev | Out-Null
pac auth select --name Dev | Out-Null

# Resolve solution name
if ([string]::IsNullOrWhiteSpace($SolutionUniqueName) -and [string]::IsNullOrWhiteSpace($SolutionName)) {
  Write-Error "You must provide either -SolutionName or -SolutionUniqueName."
}

if ([string]::IsNullOrWhiteSpace($SolutionUniqueName)) {
  # Try to find the unique name by display name
  $solutions = pac solution list | Out-String
  if ($solutions -notmatch [regex]::Escape($SolutionName)) {
    Write-Error "Solution '$SolutionName' not found in this environment. Run 'pac solution list' to confirm."
  }
  # crude parse helper:
  $SolutionUniqueName = ($solutions -split "`r?`n" | Where-Object {$_ -match $SolutionName} | Select-Object -First 1) `
                          -replace '.*Unique Name:\s*',''
  if ([string]::IsNullOrWhiteSpace($SolutionUniqueName)) {
    Write-Host "Could not parse Unique Name. If needed, pass -SolutionUniqueName explicitly."
  }
}

if ([string]::IsNullOrWhiteSpace($SolutionUniqueName)) { $SolutionUniqueName = $SolutionName }

# --- Export unmanaged zip ---
$timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$zipPath   = Join-Path $zipDir "$($SolutionUniqueName)-unmanaged-$timestamp.zip"

Write-Host "== Exporting solution '$SolutionUniqueName' (unmanaged) =="
pac solution export `
  --name $SolutionUniqueName `
  --path $zipPath `
  --managed false

# --- Clean existing src before unpack to prevent stale files ---
Write-Host "== Cleaning old source folder =="
Get-ChildItem $srcDir -Force -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

# --- Unpack to source folder ---
Write-Host "== Unpacking to $srcDir =="
pac solution unpack `
  --zipfile $zipPath `
  --folder  $srcDir `
  --solution-type Unmanaged

# --- Optional: unpack Canvas Apps (.msapp) to YAML source ---
$canvasApps = Get-ChildItem -Path (Join-Path $srcDir "CanvasApps") -Filter *.msapp -Recurse -ErrorAction SilentlyContinue
if ($canvasApps) {
  Write-Host "== Unpacking Canvas apps to YAML source =="
  foreach ($app in $canvasApps) {
    $outFolder = "$($app.DirectoryName)\$($app.BaseName)_src"
    Write-Host "Unpacking $($app.Name) -> $outFolder"
    pac canvas unpack --msapp $app.FullName --sources $outFolder
  }
} else {
  Write-Host "No .msapp files found under CanvasApps (skipping canvas unpack)."
}

Write-Host "== DONE: Solution exported and unpacked to $srcDir =="
Write-Host "Next: review changes, then 'git add/commit/push'."
