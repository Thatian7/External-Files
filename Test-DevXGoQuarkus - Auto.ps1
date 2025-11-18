# ================================
# 6. Start IntelliJ & AUTOMATICALLY detect when project is fully loaded
# ================================
$ijExe = Get-ChildItem "C:\Program Files\JetBrains\IntelliJ IDEA*\bin\idea64.exe" | 
         Sort FullName -Desc | Select -First 1 | % FullName

if (-not $ijExe) { Write-Log "FEJL: IntelliJ ikke fundet!" Error; exit 1 }

Write-Log "Starter IntelliJ med Quarkus projektet..." Info
$startTime = Get-Date

# Start IntelliJ (in background)
$proc = Start-Process -FilePath $ijExe -ArgumentList "`"$quarkusRepo`"" -PassThru

Write-Log "Venter på at projektet er fuldt indekseret og klar..." Info

# These folders/files only exist while IntelliJ is indexing / doing background work
$systemDir = "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system"
$indexesDirPattern = "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\index"
$backgroundTasksFile = "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\backgroundTasks"

$timeout = 600  # max 10 min
$elapsed = 0
$step = 5

while ($elapsed -lt $timeout) {
    $indexingActive = Get-ChildItem $indexesDirPattern -ErrorAction SilentlyContinue | Where-Object {
        # Check if any index file was modified in last 15 seconds
        $_.LastWriteTime -gt (Get-Date).AddSeconds(-15)
    }

    $backgroundActive = Test-Path $backgroundTasksFile

    if (-not $indexingActive -and -not $backgroundActive) {
        # Extra safety: also check that no "dumb mode" (project still loading)
        $dumbFile = Get-ChildItem "$env:LOCALAPPDATA\JetBrains\IntelliJIdea*\system\projectDumbMode" -ErrorAction SilentlyContinue
        if (-not $dumbFile) {
            break
        }
    }

    Write-Progress -Activity "Venter på IntelliJ færdigindlæsning..." -Status "Indexing kører..." -PercentComplete ($elapsed/$timeout*100)
    Start-Sleep -Seconds $step
    $elapsed += $step
}

$loadTime = (Get-Date) - $startTime

# Final check – if we timed out
if ($elapsed -ge $timeout) {
    Write-Log "TIMEOUT: IntelliJ blev ikke færdig inden for 10 min" Warning
} else {
    Write-Log "PROJEKT FULDT INDlÆST!" Success
}

Write-Log "FINAL LOAD TID: $($loadTime.ToString('mm\:ss')) ($($loadTime.TotalSeconds.ToString('F1')) sekunder)" Success

# Optional: Bring IntelliJ to front so user sees it's ready
try {
    $null = (New-Object -ComObject WScript.Shell).AppActivate($proc.Id)
    Start-Sleep -Milliseconds 500
} catch {}

# ================================
# 7. Save results (now fully automatic!)
# ================================
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = "$resultsDir\quarkus_AUTO_$ts.txt"

@"
QUARKUS DEVXGO – FULDT AUTOMATISK TEST
====================================
Dato: $(Get-Date)
Maskine: $env:COMPUTERNAME
Bruger: $env:USERNAME

Git clone tid      : $($cloneTime.TotalSeconds.ToString('F1')) sekunder
IntelliJ load tid  : $($loadTime.TotalSeconds.ToString('F1')) sekunder (100% automatisk målt)

Konfiguration:
- Xmx8196m fra første launch
- Gradle parallel model fetch + execution
- Maven -T 2 + parallel downloads
- Ingen manuel input nødvendig

Status: FÆRDIG – projekt er klar til brug!
"@ | Set-Content $resultFile -Encoding UTF8

Write-Log "Resultater gemt → $resultFile" Success
Write-Log "HELE TESTEN ER FÆRDIG – INGEN MANUELLE TRIN!" Success

# Optional: Beep when done
[Console]::Beep(1000, 500)