<#
.SYNOPSIS
    Cleanup script for Quarkus development environment

.DESCRIPTION
    Dette script fjerner IntelliJ IDEA Ultimate, Git, .gitconfig, og Quarkus repository
    som blev installeret/oprettet af Test-DevXGoQuarkus.ps1
    
.PARAMETER WorkspaceFolder
    Sti til workspace mappen hvor Quarkus blev klonet.
    Standard: C:\DevXGo-test

.PARAMETER KeepGit
    Behold Git installation (afinstallér ikke Git).

.PARAMETER KeepGitConfig
    Behold .gitconfig filen.

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
    [string]$WorkspaceFolder = "C:\DevXGo-test",
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepGit,
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepGitConfig
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
Write-Host "" -ForegroundColor Yellow
Write-Host "Test resultater vil IKKE blive slettet" -ForegroundColor Green
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
    
    # Stop/kill IntelliJ processer først
    Write-Log "Tjekker for kørende IntelliJ processer..." -Level Info
    $intellijProcesses = Get-Process -Name "idea64","idea" -ErrorAction SilentlyContinue
    
    if ($intellijProcesses) {
        Write-Log "Fundet $($intellijProcesses.Count) kørende IntelliJ proces(ser) - stopper dem..." -Level Warning
        foreach ($process in $intellijProcesses) {
            try {
                $process.Kill()
                $process.WaitForExit(5000)  # Vent max 5 sekunder
                Write-Log "Stoppet proces: $($process.ProcessName) (PID: $($process.Id))" -Level Success
            }
            catch {
                Write-Log "Kunne ikke stoppe proces $($process.ProcessName): $_" -Level Warning
            }
        }
        # Vent lidt ekstra for at sikre processer er helt lukket
        Start-Sleep -Seconds 2
    } else {
        Write-Log "Ingen kørende IntelliJ processer fundet" -Level Info
    }
    
    # Fjern IntelliJ bruger settings først (før afinstallation for at undgå prompts)
    Write-Log "Fjerner IntelliJ bruger settings og cache først..." -Level Info
    $intellijUserPaths = @(
        (Join-Path $env:APPDATA "JetBrains"),
        (Join-Path $env:LOCALAPPDATA "JetBrains")
    )
    
    foreach ($path in $intellijUserPaths) {
        if (Test-Path $path) {
            Write-Log "Sletter: $path" -Level Info
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    try {
        $uninstallProcess = Start-Process -FilePath "winget" -ArgumentList "uninstall","JetBrains.IntelliJIDEA.Ultimate","--silent","--accept-source-agreements" -NoNewWindow -Wait -PassThru
        
        if ($uninstallProcess.ExitCode -eq 0) {
            Write-Log "IntelliJ IDEA afinstalleret succesfuldt" -Level Success
        } else {
            Write-Log "ADVARSEL: Afinstallation returnerede exit code: $($uninstallProcess.ExitCode)" -Level Warning
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
                $uninstallProcess = Start-Process -FilePath "winget" -ArgumentList "uninstall","Git.Git","--silent","--accept-source-agreements" -NoNewWindow -Wait -PassThru
                
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
    
    # Brug robocopy til at slette repository med lange stier
    Write-Log "Sletter Quarkus repository (inkl. filer med lange stier)..." -Level Info
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
        
        Write-Log "Quarkus repository fjernet succesfuldt" -Level Success
    }
    catch {
        Write-Log "FEJL ved sletning af repository: $_" -Level Error
    }
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

Fjernet:
--------
- IntelliJ IDEA Ultimate
$(if (-not $KeepGit) { "- Git" } else { "  (Git beholdt)" })
$(if (-not $KeepGitConfig) { "- .gitconfig" } else { "  (.gitconfig beholdt)" })
- Quarkus repository ($quarkusRepoFolder)

Test resultater bevaret (slettes ikke).

Cleanup gennemført succesfuldt.
"@

Set-Content -Path $logFile -Value $cleanupLog -Encoding UTF8
Write-Log "Cleanup log gemt til: $logFile" -Level Success

#endregion
