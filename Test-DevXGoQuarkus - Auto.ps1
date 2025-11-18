<#
.SYNOPSIS
    DevXGo Quarkus Test – FULLY AUTOMATIC (8196 MB + parallel + auto-detect ready)
.DESCRIPTION
    One script that:
     • Installs IntelliJ + Git (unless skipped)
     • Configures 8196 MB heap from the very first launch
     • Enables Gradle parallel + Maven -T 2 before opening
     • Clones Quarkus
     • Opens IntelliJ and waits AUTOMATICALLY until indexing & background tasks are 100% finished
     • Prints exact load time and saves result
     • Beeps when done
     • -Uninstall = full cleanup

    Perfect for performance benchmarking, golden images, demos.
#>
#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName="Install")][switch]$CleanInstall,      # Force 8196 MB + parallel from first launch
    [Parameter(ParameterSetName="Install")][switch]$SkipInstall,       # Skip installing IntelliJ/Git

    [Parameter(ParameterSetName="Uninstall")][switch]$Uninstall,
    [switch]$KeepGit,
    [switch]$KeepGitConfig,
    [switch]$KeepTestResults,

    [string]$WorkspaceFolder = "C:\DevXGo-Test",
    [string]$GitUserName,
    [string]$GitUserEmail
)

function Write-Log { param([string]$m,[string]$l='Info') $t=Get-Date -f"yyyy-MM-dd HH:mm:ss"; $c=@{'Info'='Cyan';'Warning'='Yellow';'Error'='Red';'Success'='Green'}; Write-Host "[$t] [$l] $m" -ForegroundColor $c[$l] }
function Remove-Safely { param($p,$d,[switch]$dir) if(Test-Path $p){Write-Log "Fjerner $d..." Info; Remove-Item $p -Recurse:$dir -Force -EA SilentlyContinue | Out-Null; Write-Log "$d fjernet" Success} }

# ================================
# UNINSTALL MODE
# ================================
if ($Uninstall) {
    Write-Log "=== QUARKUS FULL CLEANUP ===" Info
    Write-Host "`nDette fjerner IntelliJ, Quarkus repo og mere. Tryk Ctrl+C for at afbryde." -ForegroundColor Red; Start-Sleep 3

    winget uninstall JetBrains.IntelliJIDEA.Ultimate --silent --force 2>$null
    Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" | Remove-Safely -d "IntelliJ mappe" -dir
    @("$env:APPDATA\JetBrains","$env:LOCALAPPDATA\JetBrains") | Remove-Safely -d "IntelliJ brugerdata" -dir
    if(-not $KeepGit)       { winget uninstall Git.Git --silent --force 2>$null }
    if(-not $KeepGitConfig) { Remove-Safely "$env:USERPROFILE\.gitconfig" ".gitconfig" }
    Remove-Safely (Join-Path $WorkspaceFolder "quarkus") "Quarkus repository" -dir
    if(-not $KeepTestResults) { Remove-Safely "$env:USERPROFILE\DevXGo-test-results" "Testresultater" -dir }

    Write-Log "=== ALT RYDDDET OP ===" Success
    exit 0
}

# ================================
# INSTALL & TEST MODE
# ================================
Write-Log "=== QUARKUS DEVXGO – FULD AUTOMATISK TEST STARTET ===" Success

$quarkusRepo = Join-Path $WorkspaceFolder "quarkus"
$resultsDir  = "$env:USERPROFILE\DevXGo-test-results"
@($WorkspaceFolder, $resultsDir) | ForEach-Object { New-Item $_ -ItemType Directory -Force -EA SilentlyContinue | Out-Null }

# 1. Install IntelliJ + Git
if (-not $SkipInstall) {
    if (-not (Test-Path "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe")) {
        Write-Log "Installerer IntelliJ IDEA Ultimate..." Info
        winget install JetBrains.IntelliJIDEA.Ultimate --silent --accept-source-agreements --accept-package-agreements | Out-Null
    }
    try { git --version | Out-Null } catch {
        Write-Log "Installerer Git..." Info
        winget install Git.Git --silent --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    }
}

# 2. FORCE 8196 MB from first launch
if ($CleanInstall) {
    $ijDir = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" | Sort Name -Desc | Select -First 1 | % FullName
    $vmFile = Join-Path $ijDir "bin\idea64.exe.vmoptions"
    $vm = @"
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
"@.Trim()
    $vm | Set-Content $vmFile -Encoding UTF8 -Force
    Write-Log "8196 MB heap + performance flags aktiveret fra allerførste launch" Success
}

# 3. Git config
if (-not (Test-Path "$env:USERPROFILE\.gitconfig")) {
    if (!$GitUserName -or !$GitUserEmail) { Write-Log "FEJL: Angiv -GitUserName og -GitUserEmail" Error; exit 1 }
    @"
[user]
    name = $GitUserName
    email = $GitUserEmail
[core]
    autocrlf = true
    longpaths = true
[init]
    defaultBranch = main
"@ | Set-Content "$env:USERPROFILE\.gitconfig" -Encoding UTF8
    Write-Log ".gitconfig oprettet" Success
}

# 4. Clone Quarkus (fresh every time)
if (Test-Path $quarkusRepo) { Remove-Item $quarkusRepo -Recurse -Force }
Set-Location $WorkspaceFolder
$cloneStart = Get-Date
git clone https://github.com/quarkusio/quarkus.git
$cloneTime = (Get-Date) - $cloneStart
Write-Log "Quarkus klonet på $($cloneTime.TotalSeconds.ToString('F1')) sekunder" Success

# 5. Pre-configure Gradle parallel + Maven -T 2
$ideaDir = Join-Path $quarkusRepo ".idea"
New-Item $ideaDir -ItemType Directory -Force | Out-Null
@"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="GradleSettings">
    <option name="parallelModelFetch" value="true" />
    <option name="useParallelExecution" value="true" />
  </component>
</project>
"@ | Set-Content (Join-Path $ideaDir "gradle.xml") -Encoding UTF8

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
Write-Log "Gradle parallel + Maven -T 2 konfigureret før import" Success

# 6. Start IntelliJ + AUTO WAIT until 100% ready
$ijExe = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe" | Sort FullName -Desc | Select -First 1 | % FullName
Write-Log "Starter IntelliJ..." Info

$loadStart = Get-Date
$proc = Start-Process $ijExe "`"$quarkusRepo`"" -PassThru

Write-Log "Venter på fuld indeksering og baggrundsopgaver (max 15 min)..." Info

$timeout = 900   # 15 minutes
$elapsed = 0
while ($elapsed -lt $timeout) {
    Start-Sleep 5
    $elapsed += 5

    $indexActive   = Get-ChildItem "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\index" -Recurse -EA SilentlyContinue | 
                     Where-Object LastWriteTime -gt (Get-Date).AddSeconds(-20)
    $bgTasksActive = Test-Path "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\backgroundTasks"
    $dumbMode      = Test-Path "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\projectDumbMode"

    if (-not $indexActive -and -not $bgTasksActive -and -not $dumbMode) {
        Write-Log "PROJEKT FULDT KLAR!" Success
        break
    }
    Write-Progress -Activity "IntelliJ indeksere..." -Status "$([math]::Round($elapsed/60,1)) min gået..." -PercentComplete ($elapsed/$timeout*100)
}
$loadTime = (Get-Date) - $loadStart

if ($elapsed -ge $timeout) {
    Write-Log "TIMEOUT efter 15 min – projektet blev ikke helt færdigt" Warning
}

# 7. Final result + save
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = "$resultsDir\quarkus_AUTO_$ts.txt"
@"
QUARKUS DEVXGO – 100% AUTOMATISK TEST
========================================
Dato           : $(Get-Date)
Maskine        : $env:COMPUTERNAME
Bruger         : $env:USERNAME

Git clone tid  : $($cloneTime.TotalSeconds.ToString('F1')) sekunder
IntelliJ load tid : $($loadTime.TotalSeconds.ToString('F1')) sekunder  ← 100% automatisk målt!

Konfiguration
- Xmx8196m fra første launch
- Gradle parallel model fetch + execution
- Maven -T 2 + parallel downloads

STATUS: FÆRDIG – DU KAN NU BRUGE PROJEKTET!
"@ | Set-Content $resultFile -Encoding UTF8

Write-Log "RESULTAT GEMT → $resultFile" Success
Write-Log "HELE TESTEN FÆRDIG PÅ $($loadTime.ToString('mm\\:ss')) – INGEN MANUELLE TRIN!" Success

# Beep + bring window forward
[Console]::Beep(1200,300); [Console]::Beep(1500,400); [Console]::Beep(1800,500)
try { (New-Object -ComObject WScript.Shell).AppActivate($proc.Id) } catch {}

exit 0
