<#
.SYNOPSIS
    Quarkus development environment setup and performance test

.DESCRIPTION
    Dette script installerer IntelliJ IDEA Ultimate og Git, opsætter Git config,
    kloner Quarkus repository fra GitHub, og måler IntelliJ project load tid.
    
    Scriptet følger Quarkus guide til BD maskiner.
    
.PARAMETER WorkspaceFolder
    Sti til workspace mappen hvor Quarkus skal klones.
    Standard: C:\DevXGo-Test\Quarkus

.PARAMETER GitUserName
    Navn til Git config (fornavn efternavn).
    Påkrævet hvis .gitconfig ikke eksisterer.

.PARAMETER GitUserEmail
    Email til Git config (xyz@bankdata.dk).
    Påkrævet hvis .gitconfig ikke eksisterer.

.PARAMETER SkipInstall
    Spring installation af IntelliJ og Git over.

.PARAMETER CleanInstall
    Opretter IntelliJ vmoptions fil med 8GB heap size.

.PARAMETER Cleanup
    Sletter Quarkus repository efter test er gennemført.

.PARAMETER CleanupIntelliJ
    Afinstallerer IntelliJ IDEA efter test er gennemført.

.PARAMETER CleanupGit
    Afinstallerer Git efter test er gennemført.

.EXAMPLE
    .\Test-DevXGoQuarkus.ps1 -GitUserName "John Doe" -GitUserEmail "abc123@bankdata.dk"
    Kører fuld setup og test

.EXAMPLE
    .\Test-DevXGoQuarkus.ps1 -GitUserName "John Doe" -GitUserEmail "abc123@bankdata.dk" -SkipInstall
    Springer installation over og kører kun clone og IntelliJ load test

.EXAMPLE
    .\Test-DevXGoQuarkus.ps1 -GitUserName "John Doe" -GitUserEmail "abc123@bankdata.dk" -CleanInstall
    Kører setup med IntelliJ vmoptions konfiguration

.EXAMPLE
    .\Test-DevXGoQuarkus.ps1 -GitUserName "John Doe" -GitUserEmail "abc123@bankdata.dk" -Cleanup -CleanupIntelliJ -CleanupGit
    Kører test og rydder alt op bagefter

.NOTES
    Version: 1.0
    Author: EUT Team
    Changelog:
        1.0 - Initial version med IntelliJ install, Git config, og Quarkus clone
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceFolder = "C:\DevXGo-Test",
    
    [Parameter(Mandatory = $false)]
    [string]$GitUserName,
    
    [Parameter(Mandatory = $false)]
    [string]$GitUserEmail,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipInstall,
    
    [Parameter(Mandatory = $false)]
    [switch]$CleanInstall,
    
    [Parameter(Mandatory = $false)]
    [switch]$Cleanup,
    
    [Parameter(Mandatory = $false)]
    [switch]$CleanupIntelliJ,
    
    [Parameter(Mandatory = $false)]
    [switch]$CleanupGit
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Measure-Operation {
    param(
        [string]$Name,
        [scriptblock]$Operation
    )
    
    Write-Log "Starter: $Name" -Level Info
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        & $Operation
        $stopwatch.Stop()
        $duration = $stopwatch.Elapsed
        Write-Log "Færdig: $Name - Tid: $($duration.ToString('hh\:mm\:ss\.fff'))" -Level Success
        return $duration
    }
    catch {
        $stopwatch.Stop()
        Write-Log "Fejl i: $Name - $_" -Level Error
        throw
    }
}

#endregion

#region Main Script

$scriptVersion = "1.0"

Write-Log "=== Quarkus Development Environment Setup v$scriptVersion ===" -Level Info
Write-Log "Workspace folder: $WorkspaceFolder" -Level Info
Write-Log "Git bruger: $GitUserName <$GitUserEmail>" -Level Info
Write-Log ""

# Definer stier
$quarkusRepoFolder = Join-Path $WorkspaceFolder "quarkus"
$gitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$gitConfigCreatedByScript = $false

# Tjek om .gitconfig eksisterer
$gitConfigExists = Test-Path $gitConfigPath
if (-not $gitConfigExists) {
    # .gitconfig findes ikke, valider at GitUserName og GitUserEmail er angivet
    if ([string]::IsNullOrWhiteSpace($GitUserName) -or [string]::IsNullOrWhiteSpace($GitUserEmail)) {
        Write-Log "FEJL: .gitconfig findes ikke. GitUserName og GitUserEmail er påkrævet." -Level Error
        Write-Log "Brug: .\Test-DevXGoQuarkus.ps1 -GitUserName 'Fornavn Efternavn' -GitUserEmail 'xyz@bankdata.dk'" -Level Error
        exit 1
    }
} else {
    Write-Log ".gitconfig eksisterer allerede: $gitConfigPath" -Level Info
    Write-Log "Springer Git konfiguration over..." -Level Info
}

# Opret workspace folder
if (-not (Test-Path $WorkspaceFolder)) {
    New-Item -Path $WorkspaceFolder -ItemType Directory -Force | Out-Null
    Write-Log "Oprettet workspace folder: $WorkspaceFolder" -Level Success
}

#region Step 1: Install IntelliJ IDEA Ultimate
Write-Log "" -Level Info
Write-Log "=== STEP 1: Installér IntelliJ IDEA Ultimate ===" -Level Info

$intellijInstallTime = $null
if ($SkipInstall) {
    Write-Log "Springer installation over (SkipInstall parameter)" -Level Warning
} else {
    # Tjek om IntelliJ allerede er installeret
    $intellijPath = "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe"
    $intellijInstalled = Test-Path $intellijPath
    
    if ($intellijInstalled) {
        Write-Log "IntelliJ IDEA er allerede installeret" -Level Success
    } else {
        Write-Log "Installerer IntelliJ IDEA Ultimate via winget (dette kan tage op til 10 minutter)..." -Level Info
        
        try {
            $intellijInstallTime = Measure-Operation -Name "IntelliJ IDEA installation" -Operation {
                winget install JetBrains.IntelliJIDEA.Ultimate --accept-source-agreements --accept-package-agreements
            }
            
            # Winget returnerer -1978335189 (0x8A15002B) når pakken allerede er installeret
            # Exit code 0 = Success, -1978335189 = Already installed
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                Write-Log "IntelliJ IDEA installeret succesfuldt" -Level Success
            } else {
                Write-Log "ADVARSEL: IntelliJ installation returnerede exit code: $LASTEXITCODE" -Level Warning
            }
        }
        catch {
            Write-Log "FEJL ved installation af IntelliJ: $_" -Level Error
            exit 1
        }
    }
}

#endregion

#region Step 2: Install Git
Write-Log "" -Level Info
Write-Log "=== STEP 2: Installér Git ===" -Level Info

$gitInstallTime = $null
if ($SkipInstall) {
    Write-Log "Springer installation over (SkipInstall parameter)" -Level Warning
} else {
    # Tjek om Git allerede er installeret
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            Write-Log "Git er allerede installeret: $gitVersion" -Level Success
        }
    }
    catch {
        Write-Log "Installerer Git via winget..." -Level Info
        
        try {
            $gitInstallTime = Measure-Operation -Name "Git installation" -Operation {
                winget install Git.Git --accept-source-agreements --accept-package-agreements
            }
            
            # Winget returnerer -1978335189 (0x8A15002B) når pakken allerede er installeret
            # Exit code 0 = Success, -1978335189 = Already installed
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                Write-Log "Git installeret succesfuldt" -Level Success
                
                # Opdater PATH for nuværende session
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } else {
                Write-Log "ADVARSEL: Git installation returnerede exit code: $LASTEXITCODE" -Level Warning
            }
        }
        catch {
            Write-Log "FEJL ved installation af Git: $_" -Level Error
            exit 1
        }
    }
}

#endregion

#region Step 3: Configure Git
Write-Log "" -Level Info
Write-Log "=== STEP 3: Konfigurér Git ===" -Level Info

if ($gitConfigExists) {
    Write-Log ".gitconfig eksisterer allerede - springer konfiguration over" -Level Success
} else {
    Write-Log "Opretter .gitconfig fil..." -Level Info

    $gitConfigContent = @"
[user]
    name = $GitUserName
    email = $GitUserEmail
[core]
    autocrlf = true
    fscache = true
    symlinks = false
    longpaths = true
[init]
    defaultBranch = main
[credential]
    provider = generic
"@

    try {
        Set-Content -Path $gitConfigPath -Value $gitConfigContent -Encoding UTF8
        Write-Log ".gitconfig oprettet: $gitConfigPath" -Level Success
        $gitConfigCreatedByScript = $true
    }
    catch {
        Write-Log "FEJL ved oprettelse af .gitconfig: $_" -Level Error
        exit 1
    }
}

#endregion

#region Step 4: Clone Quarkus repository
Write-Log "" -Level Info
Write-Log "=== STEP 4: Klon Quarkus repository ===" -Level Info

$cloneTime = $null
if (Test-Path $quarkusRepoFolder) {
    Write-Log "Quarkus repository findes allerede - sletter og kloner igen..." -Level Warning
    
    try {
        Remove-Item -Path $quarkusRepoFolder -Recurse -Force -ErrorAction Stop
        Write-Log "Eksisterende repository slettet" -Level Success
    }
    catch {
        Write-Log "FEJL ved sletning af eksisterende repository: $_" -Level Error
        exit 1
    }
}

Write-Log "Kloner Quarkus fra GitHub..." -Level Info
Write-Log "Destination: $quarkusRepoFolder" -Level Info

Set-Location $WorkspaceFolder

try {
    $cloneTime = Measure-Operation -Name "Git clone Quarkus repository" -Operation {
        git clone https://github.com/quarkusio/quarkus.git
    }
    
    if (Test-Path $quarkusRepoFolder) {
        Write-Log "Quarkus repository klonet succesfuldt" -Level Success
        $repoSize = (Get-ChildItem -Path $quarkusRepoFolder -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB
        Write-Log "Repository størrelse: $([math]::Round($repoSize, 2)) GB" -Level Info
    } else {
        Write-Log "FEJL: Repository ikke fundet efter clone" -Level Error
        exit 1
    }
}
catch {
    Write-Log "FEJL ved clone af repository: $_" -Level Error
    exit 1
}

# Opret IntelliJ konfiguration hvis CleanInstall er sat
if ($CleanInstall) {
    Write-Log "" -Level Info
    Write-Log "=== Konfigurerer IntelliJ optimeringsindstillinger ===" -Level Info
    
    # Opret IntelliJ vmoptions fil
    Write-Log "Opretter IntelliJ vmoptions fil..." -Level Info
    
    $vmoptionsPath = Join-Path $env:APPDATA "JetBrains\IntelliJIdea2025.2\idea64.exe.vmoptions"
    $vmoptionsDir = Split-Path $vmoptionsPath -Parent
    
    # Opret directory hvis det ikke eksisterer
    if (-not (Test-Path $vmoptionsDir)) {
        New-Item -Path $vmoptionsDir -ItemType Directory -Force | Out-Null
        Write-Log "Oprettet directory: $vmoptionsDir" -Level Success
    }
    
    # Opret vmoptions fil med korrekt format
    $vmoptionsContent = @"
-Xms128m
-Xmx8192m
-XX:ReservedCodeCacheSize=512m
-XX:+UseG1GC
-XX:SoftRefLRUPolicyMSPerMB=50
-XX:CICompilerCount=2
-XX:+HeapDumpOnOutOfMemoryError
-XX:-OmitStackTraceInFastThrow
-ea
-Dsun.io.useCanonCaches=false
-Djdk.http.auth.tunneling.disabledSchemes=""
-Djdk.attach.allowAttachSelf=true
-Djdk.module.illegalAccess.silent=true
-Dkotlinx.coroutines.debug=off
"@
    
    try {
        Set-Content -Path $vmoptionsPath -Value $vmoptionsContent -Encoding UTF8
        Write-Log "IntelliJ heap size sat til 8192 MB" -Level Success
        Write-Log "vmoptions fil oprettet: $vmoptionsPath" -Level Info
    }
    catch {
        Write-Log "FEJL ved konfiguration af IntelliJ heap size: $_" -Level Error
        exit 1
    }
    
    # Opret .idea/gradle.xml med parallel model fetching
    Write-Log "Konfigurerer Gradle parallel model fetching..." -Level Info
    
    $ideaDir = Join-Path $quarkusRepoFolder ".idea"
    $gradleXmlPath = Join-Path $ideaDir "gradle.xml"
    
    # Opret .idea directory hvis det ikke eksisterer
    if (-not (Test-Path $ideaDir)) {
        New-Item -Path $ideaDir -ItemType Directory -Force | Out-Null
        Write-Log "Oprettet .idea directory: $ideaDir" -Level Success
    }
    
    # Opret gradle.xml fil
    $gradleXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="GradleSettings">
    <option name="parallelModelFetch" value="true" />
  </component>
</project>
"@
    
    try {
        Set-Content -Path $gradleXmlPath -Value $gradleXmlContent -Encoding UTF8
        Write-Log "Gradle konfiguration oprettet: $gradleXmlPath" -Level Success
        Write-Log "Parallel model fetching aktiveret (kræver Gradle 7.4+)" -Level Info
    }
    catch {
        Write-Log "FEJL ved oprettelse af gradle.xml: $_" -Level Error
        exit 1
    }
    
    # Opret Maven konfiguration med thread count
    Write-Log "Konfigurerer Maven thread count..." -Level Info
    
    $mavenXmlPath = Join-Path $ideaDir "maven.xml"
    
    # Opret maven.xml fil med korrekt struktur
    $mavenXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="MavenImportPreferences">
    <option name="generalSettings">
      <MavenGeneralSettings>
        <option name="threads" value="2" />
        <option name="mavenHome" value="Bundled (Maven 3)" />
      </MavenGeneralSettings>
    </option>
    <option name="importingSettings">
      <MavenImportingSettings>
        <option name="vmOptionsForImporter" value="-Xmx2048m" />
      </MavenImportingSettings>
    </option>
  </component>
</project>
"@
    
    try {
        Set-Content -Path $mavenXmlPath -Value $mavenXmlContent -Encoding UTF8
        Write-Log "Maven konfiguration oprettet: $mavenXmlPath" -Level Success
        Write-Log "Maven thread count sat til 2" -Level Info
    }
    catch {
        Write-Log "FEJL ved oprettelse af maven.xml: $_" -Level Error
        exit 1
    }
}

#endregion

#region Step 5: Open project in IntelliJ and measure load time
Write-Log "" -Level Info
Write-Log "=== STEP 5: Åbn projekt i IntelliJ ===" -Level Info

# Find IntelliJ executable
$intellijExe = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $intellijExe) {
    Write-Log "FEJL: Kunne ikke finde IntelliJ IDEA executable" -Level Error
    Write-Log "Forventet placering: C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe" -Level Error
    exit 1
}

Write-Log "IntelliJ executable fundet: $($intellijExe.FullName)" -Level Success
Write-Log "" -Level Info
Write-Log "VIGTIGT: Tag tid på hvor lang tid det tager at åbne projektet!" -Level Warning
Write-Log "" -Level Info

# Vent på bruger input før start
Write-Host ""
Write-Host "Tryk ENTER for at starte IntelliJ og begynde tidstagning..." -ForegroundColor Yellow
$null = Read-Host
Write-Host ""

# Start IntelliJ med Quarkus projektet
Write-Log "Starter IntelliJ med Quarkus projekt..." -Level Info
$startTime = Get-Date

try {
    Start-Process -FilePath $intellijExe.FullName -ArgumentList $quarkusRepoFolder
    Write-Log "IntelliJ startet - vent venligst på at projektet indlæses..." -Level Success
}
catch {
    Write-Log "FEJL ved start af IntelliJ: $_" -Level Error
    exit 1
}

# Vent 10 sekunder med nedtælling før bruger kan trykke ENTER
Write-Host ""
Write-Host "Vent venligst..." -ForegroundColor Yellow
for ($i = 10; $i -gt 0; $i--) {
    Write-Host "`r  $i sekunder..." -ForegroundColor Cyan -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host "`r                    `r" -NoNewline  # Ryd linjen
Write-Host ""

# Første ENTER - gem tiden
Write-Host "Tryk ENTER når projektet ser ud til at være fuldt indlæst..." -ForegroundColor Yellow
$null = Read-Host
$firstEndTime = Get-Date

# Bekræft at projektet er færdigt
Write-Host ""
Write-Host "Er projektet FULDT indlæst og klar? (J/N)" -ForegroundColor Yellow
$confirmation = Read-Host

if ($confirmation -eq 'J' -or $confirmation -eq 'j') {
    # Brug den første tid
    $endTime = $firstEndTime
    Write-Host "Første tid bekræftet" -ForegroundColor Green
} else {
    # Fortsæt med at vente
    Write-Host ""
    Write-Host "Fortsætter tidstagning..." -ForegroundColor Yellow
    Write-Host "Tryk ENTER når projektet er FULDT indlæst og klar..." -ForegroundColor Yellow
    $null = Read-Host
    $endTime = Get-Date
    Write-Host "Anden tid registreret" -ForegroundColor Green
}

$projectLoadTime = $endTime - $startTime

Write-Log "Projekt load tid: $($projectLoadTime.ToString('mm\:ss')) ($([math]::Round($projectLoadTime.TotalSeconds, 2)) sekunder)" -Level Success

#endregion

#region Step 6: Gem resultater
Write-Log "" -Level Info
Write-Log "========================================" -Level Info
Write-Log "===     SAMLEDE TEST RESULTATER     ===" -Level Info
Write-Log "========================================" -Level Info
Write-Log "" -Level Info

Write-Log "Quarkus Setup & Performance:" -Level Info
Write-Log "" -Level Info
if ($intellijInstallTime) {
    $intellijTimeSpan = [TimeSpan]::FromSeconds($intellijInstallTime.TotalSeconds)
    Write-Log "IntelliJ installation tid: $([math]::Round($intellijInstallTime.TotalSeconds, 2)) sekunder ($($intellijTimeSpan.ToString('mm\:ss')))" -Level Success
}
if ($gitInstallTime) {
    $gitTimeSpan = [TimeSpan]::FromSeconds($gitInstallTime.TotalSeconds)
    Write-Log "Git installation tid: $([math]::Round($gitInstallTime.TotalSeconds, 2)) sekunder ($($gitTimeSpan.ToString('mm\:ss')))" -Level Success
}
if ($cloneTime) {
    $cloneTimeSpan = [TimeSpan]::FromSeconds($cloneTime.TotalSeconds)
    Write-Log "Git clone tid: $([math]::Round($cloneTime.TotalSeconds, 2)) sekunder ($($cloneTimeSpan.ToString('mm\:ss')))" -Level Success
}
Write-Log "IntelliJ projekt load tid: $([math]::Round($projectLoadTime.TotalSeconds, 2)) sekunder ($($projectLoadTime.ToString('mm\:ss')))" -Level Success
Write-Log "" -Level Info
Write-Log "Setup gennemført!" -Level Success

# Gem resultater til fil
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultsFile = Join-Path $WorkspaceFolder "Test-DevXGoQuarkus_TestResults_$timestamp.txt"

$intellijInstallTimeText = if ($intellijInstallTime) {
    $timeSpan = [TimeSpan]::FromSeconds($intellijInstallTime.TotalSeconds)
    "$([math]::Round($intellijInstallTime.TotalSeconds, 2)) sekunder ($($timeSpan.ToString('mm\:ss')))"
} else {
    "Ikke målt (allerede installeret eller sprunget over)"
}

$gitInstallTimeText = if ($gitInstallTime) {
    $timeSpan = [TimeSpan]::FromSeconds($gitInstallTime.TotalSeconds)
    "$([math]::Round($gitInstallTime.TotalSeconds, 2)) sekunder ($($timeSpan.ToString('mm\:ss')))"
} else {
    "Ikke målt (allerede installeret eller sprunget over)"
}

$cloneTimeText = if ($cloneTime) {
    $timeSpan = [TimeSpan]::FromSeconds($cloneTime.TotalSeconds)
    "$([math]::Round($cloneTime.TotalSeconds, 2)) sekunder ($($timeSpan.ToString('mm\:ss')))"
} else {
    "Ikke målt (repository var allerede klonet)"
}

$results = @"
Quarkus Development Environment Setup Resultater
================================================
Script version: $scriptVersion
Test udført: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
Bruger: $env:USERNAME
Workspace folder: $WorkspaceFolder

Installation:
-------------
IntelliJ IDEA installation tid: $intellijInstallTimeText
Git installation tid: $gitInstallTimeText

Git Configuration:
------------------
Config fil: $gitConfigPath
Config fil oprettet af script: $(if ($gitConfigCreatedByScript) { 'Ja' } else { 'Nej (eksisterede allerede)' })
$(if ($gitConfigCreatedByScript) { "Navn: $GitUserName`nEmail: $GitUserEmail" } else { 'Eksisterende konfiguration bevaret' })

Repository:
-----------
Quarkus repository: $quarkusRepoFolder
Repository URL: https://github.com/quarkusio/quarkus.git
Clone tid: $cloneTimeText

Performance:
------------
IntelliJ projekt load tid: $([math]::Round($projectLoadTime.TotalSeconds, 2)) sekunder ($($projectLoadTime.ToString('mm\:ss')))
"@

Set-Content -Path $resultsFile -Value $results -Encoding UTF8
Write-Log "Resultater gemt til: $resultsFile" -Level Success

#endregion

#region Cleanup
if ($Cleanup -or $CleanupIntelliJ -or $CleanupGit) {
    Write-Log "" -Level Info
    Write-Log "=== CLEANUP ==="-Level Info
    Write-Log "" -Level Info
}

if ($CleanupIntelliJ) {
    Write-Log "Afinstallerer IntelliJ IDEA..." -Level Info
    
    # Stop/kill IntelliJ processer først
    $intellijProcesses = Get-Process -Name "idea64","idea" -ErrorAction SilentlyContinue
    
    if ($intellijProcesses) {
        Write-Log "Stopper IntelliJ processer..." -Level Warning
        foreach ($process in $intellijProcesses) {
            try {
                $process.Kill()
                $process.WaitForExit(5000)
                Write-Log "Stoppet proces: $($process.ProcessName) (PID: $($process.Id))" -Level Success
            }
            catch {
                Write-Log "Kunne ikke stoppe proces $($process.ProcessName): $_" -Level Warning
            }
        }
        Start-Sleep -Seconds 2
    }
    
    try {
        $uninstallProcess = Start-Process -FilePath "winget" -ArgumentList "uninstall","JetBrains.IntelliJIDEA.Ultimate","--silent","--accept-source-agreements" -NoNewWindow -Wait -PassThru
        
        if (-not $uninstallProcess.HasExited) {
            Write-Log "Venter på at uninstall proces afsluttes..." -Level Info
            $uninstallProcess.WaitForExit()
        }
        
        # Tjek om "Un" uninstaller proces stadig kører
        Start-Sleep -Seconds 2
        $uninstallerProcess = Get-Process -Name "Un" -ErrorAction SilentlyContinue
        if ($uninstallerProcess) {
            Write-Log "Venter på IntelliJ uninstaller (Un.exe)..." -Level Info
            $uninstallerProcess.WaitForExit()
            Write-Log "Uninstaller proces afsluttet" -Level Success
        }
        
        if ($uninstallProcess.ExitCode -eq 0) {
            Write-Log "IntelliJ IDEA afinstalleret succesfuldt" -Level Success
        } else {
            Write-Log "ADVARSEL: Afinstallation returnerede exit code: $($uninstallProcess.ExitCode)" -Level Warning
        }
        
        # Fjern resterende filer
        Start-Sleep -Seconds 2
        $intellijPath = "C:\Program Files\JetBrains\IntelliJ IDEA*"
        if (Test-Path $intellijPath) {
            Write-Log "Fjerner resterende IntelliJ filer..." -Level Info
            Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "FEJL ved afinstallation af IntelliJ: $_" -Level Error
    }
}

if ($Cleanup) {
    Write-Log "Sletter Quarkus repository..." -Level Info
    
    if (Test-Path $quarkusRepoFolder) {
        # Brug robocopy til at slette repository med lange stier
        $emptyFolder = Join-Path $env:TEMP "empty_temp_$(Get-Random)"
        try {
            # Opret tom folder
            New-Item -Path $emptyFolder -ItemType Directory -Force | Out-Null
            
            # Brug robocopy til at spejle tom folder til repository (sletter alt indhold)
            robocopy $emptyFolder $quarkusRepoFolder /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
            
            # Slet begge folders
            if (Test-Path $quarkusRepoFolder) {
                Remove-Item $quarkusRepoFolder -Force -Recurse -ErrorAction SilentlyContinue
            }
            if (Test-Path $emptyFolder) {
                Remove-Item $emptyFolder -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            Write-Log "Quarkus repository slettet succesfuldt" -Level Success
        }
        catch {
            Write-Log "FEJL ved sletning af repository: $_" -Level Error
        }
    } else {
        Write-Log "Quarkus repository findes ikke" -Level Warning
    }
}

if ($CleanupIntelliJ) {
    Write-Log "Afinstallerer IntelliJ IDEA..." -Level Info
    
    # Stop/kill IntelliJ processer først
    $intellijProcesses = Get-Process -Name "idea64","idea" -ErrorAction SilentlyContinue
    
    if ($intellijProcesses) {
        Write-Log "Stopper IntelliJ processer..." -Level Warning
        foreach ($process in $intellijProcesses) {
            try {
                $process.Kill()
                $process.WaitForExit(5000)
                Write-Log "Stoppet proces: $($process.ProcessName) (PID: $($process.Id))" -Level Success
            }
            catch {
                Write-Log "Kunne ikke stoppe proces $($process.ProcessName): $_" -Level Warning
            }
        }
        Start-Sleep -Seconds 2
    }
    
    try {
        $uninstallProcess = Start-Process -FilePath "winget" -ArgumentList "uninstall","JetBrains.IntelliJIDEA.Ultimate","--silent","--accept-source-agreements" -NoNewWindow -Wait -PassThru
        
        if (-not $uninstallProcess.HasExited) {
            Write-Log "Venter på at uninstall proces afsluttes..." -Level Info
            $uninstallProcess.WaitForExit()
        }
        
        # Tjek om "Un" uninstaller proces stadig kører
        Start-Sleep -Seconds 2
        $uninstallerProcess = Get-Process -Name "Un" -ErrorAction SilentlyContinue
        if ($uninstallerProcess) {
            Write-Log "Venter på IntelliJ uninstaller (Un.exe)..." -Level Info
            $uninstallerProcess.WaitForExit()
            Write-Log "Uninstaller proces afsluttet" -Level Success
        }
        
        if ($uninstallProcess.ExitCode -eq 0) {
            Write-Log "IntelliJ IDEA afinstalleret succesfuldt" -Level Success
        } else {
            Write-Log "ADVARSEL: Afinstallation returnerede exit code: $($uninstallProcess.ExitCode)" -Level Warning
        }
        
        # Fjern resterende filer
        Start-Sleep -Seconds 2
        $intellijPath = "C:\Program Files\JetBrains\IntelliJ IDEA*"
        if (Test-Path $intellijPath) {
            Write-Log "Fjerner resterende IntelliJ filer..." -Level Info
            Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "FEJL ved afinstallation af IntelliJ: $_" -Level Error
    }
}

if ($Cleanup) {
    Write-Log "Sletter Quarkus repository..." -Level Info
    
    if (Test-Path $quarkusRepoFolder) {
        # Brug robocopy mirror trick til at slette mappen (håndterer lange paths)
        $emptyFolder = Join-Path $env:TEMP "empty_temp_$(Get-Random)"
        try {
            # Opret tom folder
            New-Item -Path $emptyFolder -ItemType Directory -Force | Out-Null
            
            # Brug robocopy til at spejle tom folder til repository (sletter alt indhold)
            robocopy $emptyFolder $quarkusRepoFolder /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS | Out-Null
            
            # Slet begge folders
            if (Test-Path $quarkusRepoFolder) {
                Remove-Item $quarkusRepoFolder -Force -Recurse -ErrorAction SilentlyContinue
            }
            if (Test-Path $emptyFolder) {
                Remove-Item $emptyFolder -Force -Recurse -ErrorAction SilentlyContinue
            }
            
            Write-Log "Quarkus repository slettet succesfuldt" -Level Success
        }
        catch {
            Write-Log "FEJL ved sletning af repository: $_" -Level Error
        }
    } else {
        Write-Log "Quarkus repository findes ikke" -Level Warning
    }
}

if ($CleanupGit) {
    Write-Log "Afinstallerer Git..." -Level Info
    
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            try {
                $uninstallProcess = Start-Process -FilePath "winget" -ArgumentList "uninstall","Git.Git","--silent","--accept-source-agreements" -NoNewWindow -Wait -PassThru

                if (-not $uninstallProcess.HasExited) {
                    Write-Log "Venter på at uninstall proces afsluttes..." -Level Info
                    $uninstallProcess.WaitForExit()
                }
                
                if ($uninstallProcess.ExitCode -eq 0) {
                    Write-Log "Git afinstalleret succesfuldt" -Level Success
                } else {
                    Write-Log "ADVARSEL: Git afinstallation returnerede exit code: $($uninstallProcess.ExitCode)" -Level Warning
                }
            }
            catch {
                Write-Log "FEJL ved afinstallation af Git: $_" -Level Error
            }
        } else {
            Write-Log "Git er ikke installeret" -Level Warning
        }
    }
    catch {
        Write-Log "Git er ikke installeret" -Level Warning
    }
}

if ($Cleanup -or $CleanupIntelliJ -or $CleanupGit) {
    Write-Log "" -Level Info
    Write-Log "Cleanup gennemført" -Level Success
}
#endregion

Set-Location $env:USERPROFILE
