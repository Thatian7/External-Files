<#
.SYNOPSIS
    Cleanup script for Quarkus development environment

.DESCRIPTION
    Dette script fjerner IntelliJ IDEA Ultimate, Git, .gitconfig, og Quarkus repository
    som blev installeret/oprettet af Test-DevXGoQuarkus.ps1
    
.PARAMETER WorkspaceFolder
    Sti til workspace mappen hvor Quarkus blev klonet.
    Standard: C:\DevXGo-Test\Quarkus

.PARAMETER KeepGit
    Behold Git installation (afinstallér ikke Git).

.PARAMETER KeepGitConfig
    Behold .gitconfig filen.

.PARAMETER KeepTestResults
    Behold test results mappen.

.EXAMPLE
    .\Uninstall-DevXGoQuarkus.ps1
    Fjerner alt (IntelliJ, Git, .gitconfig, Quarkus repo)

.EXAMPLE
    .\Uninstall-DevXGoQuarkus.ps1 -KeepGit
    Fjerner alt undtagen Git

.EXAMPLE
    .\Uninstall-DevXGoQuarkus.ps1 -KeepGit -KeepGitConfig
    Fjerner IntelliJ og Quarkus repo, beholder Git og .gitconfig

.NOTES
    Version: 1.0
    Author: EUT Team
    Changelog:
        1.0 - Initial cleanup version
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceFolder = "C:\DevXGo-Test",
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepGit,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepGitConfig,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepTestResults
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

function Remove-ItemSafely {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$IsDirectory
    )
    
    if (Test-Path $Path) {
        Write-Log "Fjerner $Description..." -Level Info
        try {
            if ($IsDirectory) {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -Path $Path -Force -ErrorAction Stop
            }
            Write-Log "$Description fjernet succesfuldt" -Level Success
            return $true
        }
        catch {
            Write-Log "FEJL ved fjernelse af $Description : $_" -Level Error
            return $false
        }
    } else {
        Write-Log "$Description findes ikke (allerede fjernet?)" -Level Warning
        return $false
    }
}

#endregion

#region Main Script

$scriptVersion = "1.0"

Write-Log "=== Quarkus Development Environment Cleanup v$scriptVersion ===" -Level Info
Write-Log "Workspace folder: $WorkspaceFolder" -Level Info
Write-Log ""

# Definer stier
$quarkusRepoFolder = Join-Path $WorkspaceFolder "quarkus"
$gitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$testResultsFolder = Join-Path $env:USERPROFILE "DevXGo-test-results"

# Bekræftelse
Write-Host ""
Write-Host "ADVARSEL: Dette script vil fjerne følgende:" -ForegroundColor Yellow
Write-Host "  - IntelliJ IDEA Ultimate" -ForegroundColor Yellow
if (-not $KeepGit) {
    Write-Host "  - Git" -ForegroundColor Yellow
}
if (-not $KeepGitConfig) {
    Write-Host "  - .gitconfig fil ($gitConfigPath)" -ForegroundColor Yellow
}
Write-Host "  - Quarkus repository ($quarkusRepoFolder)" -ForegroundColor Yellow
if (-not $KeepTestResults) {
    Write-Host "  - Test results folder ($testResultsFolder)" -ForegroundColor Yellow
}
Write-Host ""

$confirmation = Read-Host "Er du sikker på at du vil fortsætte? (ja/nej)"
if ($confirmation -ne "ja") {
    Write-Log "Afbrudt af bruger" -Level Warning
    exit 0
}

Write-Log ""
Write-Log "Starter cleanup..." -Level Info

#region Step 1: Uninstall IntelliJ IDEA Ultimate
Write-Log "" -Level Info
Write-Log "=== STEP 1: Afinstallér IntelliJ IDEA Ultimate ===" -Level Info

# Tjek om IntelliJ er installeret
$intellijPath = "C:\Program Files\JetBrains\IntelliJ IDEA*"
$intellijInstalled = Test-Path $intellijPath

if ($intellijInstalled) {
    Write-Log "IntelliJ IDEA fundet - afinstallerer via winget..." -Level Info
    
    try {
        winget uninstall JetBrains.IntelliJIDEA.Ultimate --silent --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "IntelliJ IDEA afinstalleret succesfuldt" -Level Success
        } else {
            Write-Log "ADVARSEL: Afinstallation returnerede exit code: $LASTEXITCODE" -Level Warning
        }
        
        # Tjek om der stadig er filer tilbage og fjern dem
        Start-Sleep -Seconds 2
        if (Test-Path $intellijPath) {
            Write-Log "Fjerner resterende IntelliJ filer..." -Level Info
            Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*" -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-ItemSafely -Path $_.FullName -Description "IntelliJ IDEA folder" -IsDirectory
            }
        }
    }
    catch {
        Write-Log "FEJL ved afinstallation af IntelliJ: $_" -Level Error
    }
} else {
    Write-Log "IntelliJ IDEA er ikke installeret" -Level Warning
}

# Fjern bruger-specifikke IntelliJ settings
$intellijUserPaths = @(
    (Join-Path $env:APPDATA "JetBrains"),
    (Join-Path $env:LOCALAPPDATA "JetBrains")
)

foreach ($path in $intellijUserPaths) {
    if (Test-Path $path) {
        Remove-ItemSafely -Path $path -Description "IntelliJ bruger settings ($path)" -IsDirectory | Out-Null
    }
}

# Fjern vmoptions fil hvis den eksisterer
$vmoptionsPath = Join-Path $env:APPDATA "JetBrains\IntelliJIdea2025.2\idea64.exe.vmoptions"
if (Test-Path $vmoptionsPath) {
    Remove-ItemSafely -Path $vmoptionsPath -Description "IntelliJ vmoptions fil" | Out-Null
}

#endregion

#region Step 2: Uninstall Git
Write-Log "" -Level Info
Write-Log "=== STEP 2: Afinstallér Git ===" -Level Info

if ($KeepGit) {
    Write-Log "Beholder Git (KeepGit parameter)" -Level Warning
} else {
    # Tjek om Git er installeret
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            Write-Log "Git fundet - afinstallerer via winget..." -Level Info
            
            try {
                winget uninstall Git.Git --silent --accept-source-agreements
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Git afinstalleret succesfuldt" -Level Success
                } else {
                    Write-Log "ADVARSEL: Git afinstallation returnerede exit code: $LASTEXITCODE" -Level Warning
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

#endregion

#region Step 3: Remove .gitconfig
Write-Log "" -Level Info
Write-Log "=== STEP 3: Fjern .gitconfig ===" -Level Info

if ($KeepGitConfig) {
    Write-Log "Beholder .gitconfig (KeepGitConfig parameter)" -Level Warning
} else {
    # Tjek om .gitconfig eksisterer
    if (-not (Test-Path $gitConfigPath)) {
        Write-Log ".gitconfig findes ikke" -Level Warning
    } else {
        # Tjek om scriptet oprettede .gitconfig
        # Vi kan kun vide dette sikkert hvis vi læser results filen fra setup scriptet
        # For sikkerhed, advarer vi brugeren
        Write-Log "ADVARSEL: .gitconfig eksisterer: $gitConfigPath" -Level Warning
        Write-Log "Dette script kan ikke afgøre om .gitconfig blev oprettet af Test-DevXGoQuarkus.ps1" -Level Warning
        $confirmation = Read-Host "Vil du slette .gitconfig? (ja/nej)"
        
        if ($confirmation -eq "ja") {
            Remove-ItemSafely -Path $gitConfigPath -Description ".gitconfig fil" | Out-Null
        } else {
            Write-Log ".gitconfig bevaret" -Level Success
        }
    }
}

#endregion

#region Step 4: Remove Quarkus repository
Write-Log "" -Level Info
Write-Log "=== STEP 4: Fjern Quarkus repository ===" -Level Info

if (Test-Path $quarkusRepoFolder) {
    Write-Log "Beregner repository størrelse..." -Level Info
    try {
        $repoSize = (Get-ChildItem -Path $quarkusRepoFolder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
        Write-Log "Repository størrelse: $([math]::Round($repoSize, 2)) GB" -Level Info
    }
    catch {
        Write-Log "Kunne ikke beregne størrelse" -Level Warning
    }
    
    # Fjern .idea folder med gradle.xml og maven.xml
    $ideaFolder = Join-Path $quarkusRepoFolder ".idea"
    if (Test-Path $ideaFolder) {
        $gradleXml = Join-Path $ideaFolder "gradle.xml"
        $mavenXml = Join-Path $ideaFolder "maven.xml"
        
        if (Test-Path $gradleXml) {
            Remove-ItemSafely -Path $gradleXml -Description "IntelliJ Gradle konfiguration" | Out-Null
        }
        if (Test-Path $mavenXml) {
            Remove-ItemSafely -Path $mavenXml -Description "IntelliJ Maven konfiguration" | Out-Null
        }
        
        # Fjern hele .idea folder hvis den er tom eller kun indeholder config filer
        Remove-ItemSafely -Path $ideaFolder -Description "IntelliJ projekt konfiguration (.idea)" -IsDirectory | Out-Null
    }
    
    Remove-ItemSafely -Path $quarkusRepoFolder -Description "Quarkus repository" -IsDirectory | Out-Null
} else {
    Write-Log "Quarkus repository findes ikke" -Level Warning
}

# Fjern workspace folder hvis den er tom
if (Test-Path $WorkspaceFolder) {
    $items = Get-ChildItem -Path $WorkspaceFolder -ErrorAction SilentlyContinue
    if ($items.Count -eq 0) {
        Write-Log "Workspace folder er tom - fjerner..." -Level Info
        Remove-ItemSafely -Path $WorkspaceFolder -Description "Workspace folder" -IsDirectory | Out-Null
    } else {
        Write-Log "Workspace folder indeholder andre filer - beholder mappen" -Level Warning
    }
}

#endregion

#region Step 5: Remove test results
Write-Log "" -Level Info
Write-Log "=== STEP 5: Fjern test resultater ===" -Level Info

if ($KeepTestResults) {
    Write-Log "Beholder test results (KeepTestResults parameter)" -Level Warning
} else {
    if (Test-Path $testResultsFolder) {
        # Vis antal filer
        $resultFiles = Get-ChildItem -Path $testResultsFolder -Filter "quarkus-*.txt" -ErrorAction SilentlyContinue
        if ($resultFiles.Count -gt 0) {
            Write-Log "Fundet $($resultFiles.Count) resultat fil(er)" -Level Info
        }
        
        Remove-ItemSafely -Path $testResultsFolder -Description "Test results folder" -IsDirectory | Out-Null
    } else {
        Write-Log "Test results folder findes ikke" -Level Warning
    }
}

#endregion

#region Summary
Write-Log "" -Level Info
Write-Log "========================================" -Level Info
Write-Log "===     CLEANUP GENNEMFØRT          ===" -Level Info
Write-Log "========================================" -Level Info
Write-Log "" -Level Info
Write-Log "Cleanup afsluttet!" -Level Success
Write-Log "" -Level Info

# Gem cleanup log
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFolder = Join-Path $env:TEMP "DevXGo-cleanup-logs"
if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}
$logFile = Join-Path $logFolder "quarkus-cleanup_$timestamp.log"

$cleanupLog = @"
Quarkus Development Environment Cleanup Log
============================================
Script version: $scriptVersion
Cleanup udført: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
Bruger: $env:USERNAME

Parametre:
----------
Workspace folder: $WorkspaceFolder
Keep Git: $KeepGit
Keep GitConfig: $KeepGitConfig
Keep Test Results: $KeepTestResults

Fjernet:
--------
- IntelliJ IDEA Ultimate
$(if (-not $KeepGit) { "- Git" } else { "  (Git beholdt)" })
$(if (-not $KeepGitConfig) { "- .gitconfig" } else { "  (.gitconfig beholdt)" })
- Quarkus repository ($quarkusRepoFolder)
$(if (-not $KeepTestResults) { "- Test results folder" } else { "  (Test results beholdt)" })

Cleanup gennemført succesfuldt.
"@

Set-Content -Path $logFile -Value $cleanupLog -Encoding UTF8
Write-Log "Cleanup log gemt til: $logFile" -Level Success

#endregion
