<#
.SYNOPSIS
    All-in-one Quarkus DevXGo test script (Install + Ultra-fast config + Uninstall)
.DESCRIPTION
    One script to rule them all:
      • Normal run          → Full install + 8196 MB heap from first launch + parallel builds
      • -Uninstall          → Full cleanup (selective with -KeepGit etc.)
      • -CleanupOnly        → Only cleanup, no install
      • -CleanInstall       → Forces max-performance config (8196 MB + parallel)
#>
#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName="Install")][switch]$CleanInstall,      # Force 8196 MB + parallel from first launch
    [Parameter(ParameterSetName="Install")][switch]$SkipInstall,       # Skip IntelliJ+Git install

    [Parameter(ParameterSetName="Uninstall")][switch]$Uninstall,       # <<<=== UNINSTALL MODE
    [Parameter(ParameterSetName="Uninstall")][switch]$CleanupOnly,     # Only run uninstall, ignore everything else

    [switch]$KeepGit,           # Keep Git installation
    [switch]$KeepGitConfig,     # Keep .gitconfig
    [switch]$KeepTestResults,   # Keep result folder

    [string]$WorkspaceFolder = "C:\DevXGo-Test",
    [string]$GitUserName,
    [string]$GitUserEmail
)

# ================================
# Shared Functions
# ================================
function Write-Log {
    param([string]$Message, [ValidateSet('Info','Warning','Error','Success')]$Level='Info')
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $c = @{'Info'='Cyan'; 'Warning'='Yellow'; 'Error'='Red'; 'Success'='Green'}
    Write-Host "[$t] [$Level] $Message" -ForegroundColor $c[$Level]
}

function Remove-Safely {
    param([string]$Path, [string]$Desc, [switch]$Dir)
    if (Test-Path $Path) {
        Write-Log "Fjerner $Desc..." Info
        try { Remove-Item $Path -Recurse:$Dir -Force -ErrorAction Stop; Write-Log "$Desc fjernet" Success; $true }
        catch { Write-Log "FEJL: $_" Error; $false }
    } else { Write-Log "$Desc findes ikke" Warning; $false }
}

# ================================
# UNINSTALL / CLEANUP MODE
# ================================
if ($Uninstall -or $CleanupOnly) {
    Write-Log "=== QUARKUS CLEANUP MODE ===" Info

    $q = Join-Path $WorkspaceFolder "quarkus"
    $results = "$env:USERPROFILE\DevXGo-test-results"

    # Confirmation
    if (-not $CleanupOnly) {
        Write-Host "`nADVARSEL: Dette fjerner:" -ForegroundColor Red
        Write-Host " • IntelliJ IDEA Ultimate + alle settings"
        if (-not $KeepGit)       { Write-Host " • Git" }
        if (-not $KeepGitConfig) { Write-Host " • .gitconfig" }
        Write-Host " • Quarkus repository"
        if (-not $KeepTestResults) { Write-Host " • Testresultater" }
        $confirm = Read-Host "`nEr du sikker? (skriv ja for at fortsætte)"
        if ($confirm -ne "ja") { Write-Log "Afbrudt" Warning; exit 0 }
    }

    # 1. IntelliJ
    winget uninstall JetBrains.IntelliJIDEA.Ultimate --silent --force | Out-Null
    Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" | Remove-Safely -Desc "IntelliJ installationsmappe" -Dir
    @("$env:APPDATA\JetBrains", "$env:LOCALAPPDATA\JetBrains") | Remove-Safely -Desc "IntelliJ brugerdata" -Dir

    # 2. Git
    if (-not $KeepGit) {
        winget uninstall Git.Git --silent --force | Out-Null
    }

    # 3. .gitconfig
    if (-not $KeepGitConfig -and (Test-Path "$env:USERPROFILE\.gitconfig")) {
        Remove-Safely "$env:USERPROFILE\.gitconfig" ".gitconfig"
    }

    # 4. Quarkus repo + .idea configs
    Remove-Safely $q "Quarkus repository" -Dir

    # 5. Test results
    if (-not $KeepTestResults) {
        Remove-Safely $results "Testresultater" -Dir
    }

    Write-Log "=== CLEANUP FÆRDIG ===" Success
    exit 0
}

# ================================
# INSTALL MODE (normal run)
# ================================
Write-Log "=== QUARKUS DEVXGO SETUP (8196 MB + parallel) ===" Info

$quarkusRepo = Join-Path $WorkspaceFolder "quarkus"
$resultsDir  = "$env:USERPROFILE\DevXGo-test-results"
New-Item -Path $WorkspaceFolder, $resultsDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# -------------------------------
# 1. Install IntelliJ + Git
# -------------------------------
if (-not $SkipInstall) {
    if (-not (Test-Path "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe")) {
        Write-Log "Installerer IntelliJ IDEA Ultimate..." Info
        winget install JetBrains.IntelliJIDEA.Ultimate --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else { Write-Log "IntelliJ allerede installeret" Success }

    try { git --version | Out-Null } catch {
        Write-Log "Installerer Git..." Info
        winget install Git.Git --silent --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    }
}

# -------------------------------
# 2. FORCE 8196 MB + performance from FIRST launch
# -------------------------------
if ($CleanInstall) {
    $ijDir = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" | Sort Name -Desc | Select -First 1 | % FullName
    $vmFile = Join-Path $ijDir "bin\idea64.exe.vmoptions"
    $vmContent = @"
-Xms512m
-Xmx8196m
-XX:ReservedCodeCacheSize=1024m
-XX:+UseG1GC
-XX:SoftRefLRUPolicyMSPerMB=50
-XX:CICompilerCount=4
-Dsun.io.useCanonCaches=false
-Djava.net.preferIPv4Stack=true
-XX:+HeapDumpOnOutOfMemoryError
-Dawt.useSystemAAFontSettings=lcd
"@
    $vmContent.Trim() | Set-Content $vmFile -Encoding UTF8 -Force
    Write-Log "8196 MB heap + perf-flags aktiveret fra allerførste launch" Success
}

# -------------------------------
# 3. Git config
# -------------------------------
if (-not (Test-Path "$env:USERPROFILE\.gitconfig")) {
    if (-not $GitUserName -or -not $GitUserEmail) {
        Write-Log "FEJL: .gitconfig findes ikke → angiv -GitUserName og -GitUserEmail" Error
        exit 1
    }
    $gitConf = @"
[user]
    name = $GitUserName
    email = $GitUserEmail
[core]
    autocrlf = true
    longpaths = true
[init]
    defaultBranch = main
"@
    $gitConf | Set-Content "$env:USERPROFILE\.gitconfig" -Encoding UTF8
    Write-Log ".gitconfig oprettet" Success
}

# -------------------------------
# 4. Clone Quarkus
# -------------------------------
if (Test-Path $quarkusRepo) { Remove-Item $quarkusRepo -Recurse -Force }
Set-Location $WorkspaceFolder
$cloneStart = Get-Date
git clone https://github.com/quarkusio/quarkus.git
$cloneTime = (Get-Date) - $cloneStart
Write-Log "Quarkus klonet på $($cloneTime.TotalSeconds.ToString('F1')) sekunder" Success

# -------------------------------
# 5. Pre-create .idea with Gradle parallel + Maven -T 2
# -------------------------------
$ideaDir = Join-Path $quarkusRepo ".idea"
New-Item $ideaDir -ItemType Directory -Force | Out-Null

# Gradle parallel everything
@"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="GradleSettings">
    <option name="parallelModelFetch" value="true" />
    <option name="useParallelExecution" value="true" />
  </component>
</project>
"@ | Set-Content (Join-Path $ideaDir "gradle.xml") -Encoding UTF8

# Maven -T 2 + parallel downloads
@"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="MavenImportPreferences">
    <option name="generalSettings">
      <MavenGeneralSettings>
        <option name="threads" value="2" />
        <option name="useParallelDownloads" value="true" />
      </MavenGeneralSettings>
    </option>
  </component>
</project>
"@ | Set-Content (Join-Path $ideaDir "maven.xml") -Encoding UTF8

Write-Log "Gradle (parallel) + Maven (-T 2) konfigureret før første import" Success

# -------------------------------
# 6. Start IntelliJ & measure load time
# -------------------------------
$ijExe = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe" | Sort FullName -Desc | Select -First 1

Write-Host "`nTryk ENTER for at starte IntelliJ og måle load-tid..." -ForegroundColor Yellow
Read-Host | Out-Null

$start = Get-Date
Start-Process $ijExe.FullName "`"$quarkusRepo`""

Write-Host "`nTryk ENTER når projektet er fuldt indekseret og klar..." -ForegroundColor Yellow
Read-Host | Out-Null
$loadTime = (Get-Date) - $start

Write-Log "PROJEKT LOAD TID: $($loadTime.ToString('mm\:ss')) ($($loadTime.TotalSeconds.ToString('F1')) sek)" Success

# -------------------------------
# 7. Save results
# -------------------------------
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = "$resultsDir\quarkus_$ts.txt"
@"
QUARKUS DEVXGO RESULTAT
=======================
Dato: $(Get-Date)
Maskine: $env:COMPUTERNAME

Clone tid: $($cloneTime.TotalSeconds.ToString('F1')) sek
Load tid : $($loadTime.TotalSeconds.ToString('F1')) sek

Konfiguration:
- IntelliJ heap: 8196 MB (fra første launch)
- Gradle: parallel model fetch + parallel execution
- Maven : -T 2 + parallel downloads
"@ | Set-Content $resultFile -Encoding UTF8

Write-Log "Resultater gemt → $resultFile" Success
Write-Log "ALT FÆRDIG – DU ER KLAR!" Success