<#
.SYNOPSIS
    Guide til verifikation af BD maskiner - Performance test script

.DESCRIPTION
    Dette script automatiserer performance test processen for BD maskiner.
    Scriptet følger den strukturerede guide til at downloade, installere og teste Java udviklings miljø.
    
    Test processen inkluderer:
    1. Download af JDK 21 og Maven
    2. Installation af software
    3. Download og udpakning af Axis test projekt
    4. Fil kopierings test
    5. Første Maven build (cold cache)
    6. Efterfølgende Maven builds (warm cache)
    
.PARAMETER TestFolder
    Sti til test mappen hvor alle downloads og tests skal udføres.
    Standard: C:\DevXGo-Test

.PARAMETER AxisUrl
    URL til Axis zip fil.
    Standard: https://github.com/apache/axis-axis2-java-core/archive/refs/tags/v2.0.0.zip

.PARAMETER WarmBuildIterations
    Antal gange Maven build skal køres for at lave et gennemsnit.
    Standard: 5

.PARAMETER MavenThreadsPerCore
    Antal threads per CPU core som Maven skal bruge (T parameter).
    Standard: 1 (1 thread per core)
    Eksempel: 2 = 2 threads per core

.PARAMETER SkipDownload
    Spring download steppen over hvis filerne allerede er downloadet.

.EXAMPLE
    .\Test-DevXGoPerformance.ps1
    Kører fuld test med standard indstillinger

.EXAMPLE
    .\Test-DevXGoPerformance.ps1 -TestFolder "D:\Test" -WarmBuildIterations 5
    Kører test i D:\Test med 5 warm build iterationer

.EXAMPLE
    .\Test-DevXGoPerformance.ps1 -MavenThreadsPerCore 2
    Kører Maven med 2 threads per CPU core

.EXAMPLE
    .\Test-DevXGoPerformance.ps1 -SkipDownload
    Springer download over, men installerer/opdaterer software hvis nødvendigt

.NOTES
    Version: 2.0
    Author: EUT Team
    Kræver: Administrator rettigheder for JDK installation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TestFolder = "C:\DevXGo-test",
    
    [Parameter(Mandatory = $false)]
    [string]$AxisUrl = "https://github.com/apache/axis-axis2-java-core/archive/refs/tags/v2.0.0.zip",
    
    [Parameter(Mandatory = $false)]
    [int]$WarmBuildIterations = 5,
    
    [Parameter(Mandatory = $false)]
    [int]$MavenThreadsPerCore = 1,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipDownload
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

$scriptVersion = "2.0"

Write-Log "=== BD Maskine Performance Test v$scriptVersion ===" -Level Info
Write-Log "Test folder: $TestFolder" -Level Info
Write-Log "Warm build iterationer: $WarmBuildIterations" -Level Info
Write-Log "Maven threads per core: $MavenThreadsPerCore" -Level Info
Write-Log ""

# Check for administrator rettigheder (hvis JDK ikke er installeret)
$jdkPath = "C:\jdk21"
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not (Test-Path $jdkPath)) {
    Write-Log "ADVARSEL: Scriptet kører ikke som Administrator!" -Level Warning
    Write-Log "JDK installation kræver Administrator rettigheder." -Level Warning
    Write-Log "Genstart PowerShell som Administrator for at installere JDK." -Level Warning
    Write-Log "" -Level Warning
}

# Opret test folder
if (-not (Test-Path $TestFolder)) {
    New-Item -Path $TestFolder -ItemType Directory -Force | Out-Null
    Write-Log "Oprettet test folder: $TestFolder" -Level Success
}

# Opret Software Download folder
$downloadFolder = Join-Path $TestFolder "Software Download"
if (-not (Test-Path $downloadFolder)) {
    New-Item -Path $downloadFolder -ItemType Directory -Force | Out-Null
    Write-Log "Oprettet download folder: $downloadFolder" -Level Success
}

Set-Location $TestFolder

# URLs
$jdkUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_windows_hotspot_21.0.5_11.msi"
$mavenUrl = "https://dlcdn.apache.org/maven/maven-3/3.9.11/binaries/apache-maven-3.9.11-bin.zip"

# Filnavne
$jdkFile = "OpenJDK21U-jdk_x64_windows_hotspot_21.0.5_11.msi"
$mavenZip = "apache-maven-3.9.11-bin.zip"
$axisZip = "axis-axis2-java-core-2.0.0.zip"

# Maven thread configuration
$cpuCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$mavenThreads = $cpuCores * $MavenThreadsPerCore
Write-Log "System har $cpuCores CPU cores" -Level Info
Write-Log "Maven vil bruge $mavenThreads threads ($MavenThreadsPerCore threads per core)" -Level Info
Write-Log ""

#region Step 1: Download software
if (-not $SkipDownload) {
    Write-Log "" -Level Info
    Write-Log "=== STEP 1: Download software ===" -Level Info
    
    # Download JDK 21
    $downloadFolder = Join-Path $TestFolder "Software Download"
    $jdkFilePath = Join-Path $downloadFolder $jdkFile
    if (-not (Test-Path $jdkFilePath)) {
        Write-Log "Downloader JDK 21..." -Level Info
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($jdkUrl, $jdkFilePath)
        $webClient.Dispose()
        Write-Log "JDK 21 downloadet til: $jdkFilePath" -Level Success
    }
    else {
        Write-Log "JDK 21 allerede downloadet" -Level Info
    }
    
    # Download Maven
    $mavenZipPath = Join-Path $downloadFolder $mavenZip
    if (-not (Test-Path $mavenZipPath)) {
        Write-Log "Downloader Maven..." -Level Info
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($mavenUrl, $mavenZipPath)
        $webClient.Dispose()
        Write-Log "Maven downloadet til: $mavenZipPath" -Level Success
    }
    else {
        Write-Log "Maven allerede downloadet" -Level Info
    }
    
    # Download Axis
    $axisZipPath = Join-Path $downloadFolder $axisZip
    if (-not (Test-Path $axisZipPath)) {
        Write-Log "Downloader Axis..." -Level Info
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($AxisUrl, $axisZipPath)
        $webClient.Dispose()
        Write-Log "Axis downloadet til: $axisZipPath" -Level Success
    }
    else {
        Write-Log "Axis allerede downloadet" -Level Info
    }
}
else {
    Write-Log "Spring download over (SkipDownload)" -Level Info
}

#endregion

#region Step 2: Install software
Write-Log "" -Level Info
Write-Log "=== STEP 2: Install software ===" -Level Info

# Install JDK 21 (kun hvis ikke allerede installeret)
$jdkPath = "C:\jdk21"
$downloadFolder = Join-Path $TestFolder "Software Download"
$jdkFilePath = Join-Path $downloadFolder $jdkFile

if (Test-Path $jdkPath) {
    Write-Log "JDK 21 allerede installeret på $jdkPath" -Level Success
} else {
    if (-not $isAdmin) {
        Write-Log "FEJL: JDK ikke installeret og scriptet kører ikke som Administrator!" -Level Error
        Write-Log "Genstart PowerShell som Administrator for at installere JDK." -Level Warning
        exit 1
    }
    
    Write-Log "Installerer JDK 21..." -Level Info
        $installArgs = @(
            "/i",
            "`"$jdkFilePath`"",
            "/qn",
            "/norestart",
            "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith",
            "INSTALLDIR=`"$jdkPath`""
        )
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "JDK 21 installeret" -Level Success
        }
        else {
            Write-Log "JDK installation fejlede med exit code: $($process.ExitCode)" -Level Error
            switch ($process.ExitCode) {
                1619 { Write-Log "Error 1619: Installationen kan ikke køre. Kræver Administrator rettigheder!" -Level Error }
                1602 { Write-Log "Error 1602: Installationen blev annulleret af brugeren." -Level Error }
                1603 { Write-Log "Error 1603: Fatal fejl under installation." -Level Error }
                1618 { Write-Log "Error 1618: En anden installation er allerede i gang." -Level Error }
                1620 { Write-Log "Error 1620: MSI pakken er corrupt eller i brug." -Level Error }
                1633 { Write-Log "Error 1633: Platformen understøttes ikke." -Level Error }
                default { Write-Log "Se https://docs.microsoft.com/en-us/windows/win32/msi/error-codes for detaljer" -Level Error }
            }
            Write-Log "" -Level Error
            Write-Log "LØSNING: Genstart PowerShell som Administrator" -Level Warning
            exit 1
        }
}

# Udpak Maven
$mavenFolder = Join-Path $TestFolder "apache-maven-3.9.11"
$downloadFolder = Join-Path $TestFolder "Software Download"
$mavenZipPath = Join-Path $downloadFolder $mavenZip
if (-not (Test-Path $mavenFolder)) {
    Write-Log "Udpakker Maven..." -Level Info
    Expand-Archive -Path $mavenZipPath -DestinationPath $TestFolder -Force
    Write-Log "Maven udpakket til: $mavenFolder" -Level Success
}
else {
    Write-Log "Maven allerede udpakket" -Level Info
}

# Sæt miljø variabler
$javaBin = Join-Path $jdkPath "bin"
$mavenBin = Join-Path $mavenFolder "bin"

$currentPath = $env:PATH
$env:PATH = $javaBin + ";" + $mavenBin + ";" + $currentPath
$env:JAVA_HOME = $jdkPath

Write-Log "Miljø variabler sat:" -Level Success
Write-Log "  JAVA_HOME: $env:JAVA_HOME" -Level Info
Write-Log "  PATH opdateret med Java og Maven" -Level Info

# Verificer installation
Write-Log "" -Level Info
Write-Log "Verificerer installation..." -Level Info
$javaVersion = & java -version 2>&1 | Select-Object -First 1
$mavenVersion = & mvn -version 2>&1 | Select-Object -First 1
Write-Log "Java: $javaVersion" -Level Info
Write-Log "Maven: $mavenVersion" -Level Info

#endregion#region Step 3 & 4: Download og udpak Axis (mål udpakningstid)
Write-Log "" -Level Info
Write-Log "=== STEP 3 & 4: Download og udpak Axis ===" -Level Info

$axisFolder = Join-Path $TestFolder "axis-axis2-java-core-2.0.0"
$downloadFolder = Join-Path $TestFolder "Software Download"
$axisZipPath = Join-Path $downloadFolder $axisZip
if (Test-Path $axisFolder) {
    Write-Log "Sletter eksisterende Axis folder..." -Level Info
    Remove-Item $axisFolder -Recurse -Force
}

$unzipTime = Measure-Operation -Name "Udpakning af Axis" -Operation {
    Expand-Archive -Path $axisZipPath -DestinationPath $TestFolder -Force
}

Write-Log "" -Level Success
Write-Log "RESULTAT - Udpakningstid: $($unzipTime.TotalSeconds) sekunder" -Level Success

#endregion

#region Step 5: Kopier Axis folder (fil I/O test)
Write-Log "" -Level Info
Write-Log "=== STEP 5: Kopier Axis folder ===" -Level Info

Set-Location $TestFolder

$axisCopyFolder = Join-Path $TestFolder "axis-copy"
if (Test-Path $axisCopyFolder) {
    Write-Log "Sletter eksisterende kopi..." -Level Info
    Remove-Item $axisCopyFolder -Recurse -Force
}

$copyTime = Measure-Operation -Name "Kopiering af Axis folder" -Operation {
    # Brug Windows Shell (Explorer) til kopiering - samme som GUI kopiering
    # Dette håndterer lange stier bedre end Copy-Item og giver samme performance som manuel kopiering
    $shell = New-Object -ComObject Shell.Application
    
    # Hent source folder objekt
    $sourceFolder = $shell.NameSpace($axisFolder)
    
    # Opret destination folder hvis den ikke findes
    if (-not (Test-Path $axisCopyFolder)) {
        New-Item -Path $axisCopyFolder -ItemType Directory -Force | Out-Null
    }
    
    # Hent destination folder objekt
    $destFolder = $shell.NameSpace($axisCopyFolder)
    
    # Kopier med Shell - bruges samme metode som Explorer
    # 16 (0x10) = Automatically respond "Yes to All" for any dialog box that is displayed
    # 4 (0x4) = Do not display a progress dialog box
    # 20 (0x14) = Kombinerer begge flags
    $options = 20
    $destFolder.CopyHere($sourceFolder.Items(), $options)
    
    # Vent på at kopieringen er færdig ved at tjekke om alle filer er kopieret
    $sourceCount = (Get-ChildItem -Path $axisFolder -Recurse -File | Measure-Object).Count
    do {
        Start-Sleep -Milliseconds 500
        $destCount = (Get-ChildItem -Path $axisCopyFolder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    } while ($destCount -lt $sourceCount)
    
    Write-Log "Shell kopiering færdig - kopierede $sourceCount filer" -Level Success
}

Write-Log "" -Level Success
Write-Log "RESULTAT - Kopieringstid: $($copyTime.TotalSeconds) sekunder" -Level Success

#endregion

#region Step 6: Første Maven build (cold cache)
Write-Log "" -Level Info
Write-Log "=== STEP 6: Første Maven build (cold cache) ===" -Level Info

Set-Location $axisFolder

$coldBuildTime = Measure-Operation -Name "Maven clean package (cold cache)" -Operation {
    & mvn clean package -T $mavenThreads 2>&1 | Out-Null
}

Write-Log "" -Level Success
Write-Log "RESULTAT - Cold build tid: $($coldBuildTime.TotalSeconds) sekunder" -Level Success

#endregion

#region Step 7: Anden Maven build (warm cache - gentag for gennemsnit)
Write-Log "" -Level Info
Write-Log "=== STEP 7: Maven builds (warm cache) ===" -Level Info
Write-Log "Kører $WarmBuildIterations iterationer for gennemsnit..." -Level Info

$warmBuildTimes = @()

for ($i = 1; $i -le $WarmBuildIterations; $i++) {
    Write-Log "" -Level Info
    Write-Log "Warm build iteration $i af $WarmBuildIterations" -Level Info
    
    $warmBuildTime = Measure-Operation -Name "Maven clean package (warm cache #$i)" -Operation {
        & mvn clean package -T $mavenThreads 2>&1 | Out-Null
    }
    
    $warmBuildTimes += $warmBuildTime.TotalSeconds
}

$avgWarmBuildTime = ($warmBuildTimes | Measure-Object -Average).Average

Write-Log "" -Level Success
Write-Log "RESULTAT - Warm build tider:" -Level Success
for ($i = 0; $i -lt $warmBuildTimes.Count; $i++) {
    Write-Log "  Iteration $($i + 1): $($warmBuildTimes[$i]) sekunder" -Level Info
}
Write-Log "  Gennemsnit: $avgWarmBuildTime sekunder" -Level Success

#endregion

#region Samlet resultat
Write-Log "" -Level Info
Write-Log "========================================" -Level Info
Write-Log "===     SAMLEDE TEST RESULTATER     ===" -Level Info
Write-Log "========================================" -Level Info
Write-Log "" -Level Info
Write-Log "Test folder: $TestFolder" -Level Info
Write-Log "" -Level Info
Write-Log "1. Udpakningstid (Axis):        $($unzipTime.TotalSeconds) sekunder" -Level Success
Write-Log "2. Kopieringstid (Axis folder): $($copyTime.TotalSeconds) sekunder" -Level Success
Write-Log "3. Cold build tid (første):     $($coldBuildTime.TotalSeconds) sekunder" -Level Success
Write-Log "4. Warm build tid (gennemsnit): $avgWarmBuildTime sekunder" -Level Success
Write-Log "" -Level Info
Write-Log "Test gennemført!" -Level Success

# Gem resultater til fil
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultsFileName = "test-results_${timestamp}_${cpuCores}cores_${WarmBuildIterations}iter.txt"
$resultsFile = Join-Path $TestFolder $resultsFileName
$results = @"
BD Maskine Performance Test Resultater
========================================
Script version: $scriptVersion
Test udført: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
Bruger: $env:USERNAME
Test folder: $TestFolder

Maven konfiguration:
--------------------
CPU cores: $cpuCores
Threads per core: $MavenThreadsPerCore
Total Maven threads: $mavenThreads

Resultater:
-----------
1. Udpakningstid (Axis):        $($unzipTime.TotalSeconds) sekunder
2. Kopieringstid (Axis folder): $($copyTime.TotalSeconds) sekunder
3. Cold build tid (første):     $($coldBuildTime.TotalSeconds) sekunder
4. Warm build tid (gennemsnit): $avgWarmBuildTime sekunder
   - Iterationer: $WarmBuildIterations
   - Individuelle tider: $($warmBuildTimes -join ', ') sekunder

Miljø:
------
JAVA_HOME: $env:JAVA_HOME
Java version: $(& java -version 2>&1 | Select-Object -First 1)
Maven version: $(& mvn -version 2>&1 | Select-Object -First 1)
"@

Set-Content -Path $resultsFile -Value $results -Encoding UTF8
Write-Log "Resultater gemt til: $resultsFile" -Level Success

#endregion

