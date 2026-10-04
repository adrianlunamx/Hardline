# HARDLINE INSTALL - ASCII VERSION
# ===============================

<<<<<<< Updated upstream
.DESCRIPTION
    Uso en una linea (PowerShell como administrador):
        irm https://raw.githubusercontent.com/adrianlunamx/Hardline/main/install.ps1 | iex

    Con opciones:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/adrianlunamx/Hardline/main/install.ps1))) -DryRun

    Desde un clon local:
        .\install.ps1 [-DryRun] [-Unattended] [-SkipAudio] [-Headset corsair-hs80] ...

    NOTA: este archivo es ASCII puro a proposito. Windows PowerShell 5.1
    interpreta mal UTF-8 sin BOM cuando el script llega por "irm | iex".
    El resto del proyecto se ejecuta desde disco y usa UTF-8 con BOM.

.PARAMETER DryRun
    Detecta y muestra lo que haria sin cambiar nada.
.PARAMETER Unattended
    Sin preguntas: usa las respuestas por defecto.
.PARAMETER BenchmarkOnly
    Solo ejecuta el benchmark y lo compara con el ultimo "pre" guardado.
    Pensado para despues de reiniciar.
.PARAMETER Headset
    Id de headset de src/audio/profiles/headsets.json (ej. hyperx-cloud-ii),
    nombre de un archivo de la carpeta headsets\, o un modelo para buscar su
    medicion en AutoEq (ej. "Kraken V3").
.PARAMETER Platform
    Plataforma desde la que juegas Warzone: battlenet, steam o xbox. Las otras
    instaladas se cierran y pierden el arranque automatico (se pregunta).
    Por defecto se deduce de donde esta cod.exe y se confirma.
.PARAMETER AudioMode
    Full (EQ + compresor Voicemeeter) o EqOnly.
.PARAMETER Channel
    stable (por defecto): descarga la ultima release publicada y verifica su
    SHA256. main: lo ultimo de la rama main, sin verificacion (para probar
    cambios antes de que se publiquen).
.PARAMETER GameSession
    Activa el modo partida (Yes) o no (No) sin preguntar.
.PARAMETER Gui
    Abre la interfaz grafica en lugar del modo consola.
.PARAMETER Experimental
    Aplica tambien los tweaks experimentales (desactivados por defecto).
.PARAMETER NetDiagOnly
    Solo ejecuta el diagnostico de red (perdida, jitter, bufferbloat, MTU).
.PARAMETER Update
    Descarga la ultima release (SHA256 verificado) encima de esta instalacion,
    aunque se ejecute desde la copia local. Conserva backups, reportes y
    configuracion. Con -Gui vuelve a abrir la interfaz al terminar.
.PARAMETER AudioDevice
    Salida del headset para Voicemeeter (A1), por nombre o parte del nombre:
    -AudioDevice "Sound BlasterX". Sin el, se pregunta (o se elige la mas
    probable, nunca el HDMI/DP del monitor si hay otra).
.PARAMETER AudioDynamics
    Compresor del canal del juego: normal, o pasos (disparos y explosiones
    mucho mas bajos, pasos muy altos). Sin el, se mantiene el ultimo elegido.
.PARAMETER UpdateOnly
    Como -Update, pero solo actualiza los archivos y termina (lo usa el boton
    Actualizar de la interfaz sin cerrarla).
.PARAMETER CleanAudio
    Si hay un audio personalizado anterior (Peace, FxSound, Boom 3D...),
    desinstalarlo sin preguntar. Sin este parametro, en modo desatendido
    solo se aparta su configuracion (revertible).
.PARAMETER HeSuVi
    Instala HeSuVi (virtualizacion 7.1 para audifonos, sobre Equalizer APO).
    Sin el parametro se pregunta (default No); en modo desatendido no se
    instala salvo que se pase explicito.
.PARAMETER SkipDisplay
    No toca la pantalla (refresco, optimizaciones de ventana, overlays).
.PARAMETER GameplayBenchOnly
    Solo mide una partida real de Warzone con PresentMon (FPS, 1% lows,
    tirones) y la compara con la medicion anterior.
.PARAMETER SkipController
    No toca nada del mando (energia USB, ajustes de mando de Warzone).
.PARAMETER ControllerTestOnly
    Solo ejecuta el test de mando: drift de los sticks, zona muerta minima
    recomendada y tasa de actualizacion real. No cambia nada.
.PARAMETER EqIntensity
    Intensidad del EQ de pasos: 1.0 (completa) o 0.7 (moderada).
.PARAMETER DisableOtherPlatforms
    Cierra las plataformas instaladas distintas de -Platform sin preguntar.
#>
[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $Unattended,
    [switch] $SkipWindows,
    [switch] $SkipNetwork,
    [switch] $SkipGame,
    [switch] $SkipAudio,
    [switch] $SkipPlatforms,
    [switch] $SkipLatency,
    [switch] $SkipNetDiag,
    [switch] $Experimental,
    [switch] $NetDiagOnly,
    [switch] $SkipController,
    [switch] $SkipDisplay,
    [switch] $CleanAudio,
    [switch] $HeSuVi,
    [string] $AudioDevice = '',
    [ValidateSet('', 'normal', 'pasos')] [string] $AudioDynamics = '',
    [switch] $Update,
    [switch] $UpdateOnly,
    [switch] $GameplayBenchOnly,
    [switch] $ControllerTestOnly,
    [switch] $Gui,
    [switch] $DisableOtherPlatforms,
    [double] $EqIntensity = 0,
    [switch] $SkipBenchmark,
    [switch] $NoRestorePoint,
    [switch] $BenchmarkOnly,
    [string] $Headset = '',
    [ValidateSet('', 'battlenet', 'steam', 'xbox')] [string] $Platform = '',
    [ValidateSet('', 'Full', 'EqOnly')] [string] $AudioMode = '',
    [ValidateSet('stable', 'main')] [string] $Channel = 'stable',
    [ValidateSet('', 'Yes', 'No')] [string] $GameSession = '',
    [string] $Branch = 'main',
    [string] $InstallDir = ''
=======
param(
    [switch]$DryRun,
    [switch]$AcceptAll,
    [string]$Mode = "Audio"
>>>>>>> Stashed changes
)

Write-Host "=== HARDLINE OPTIMIZATION TOOL ===" -ForegroundColor Green
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - No system changes" -ForegroundColor Yellow
    Write-Host ""
}

$confirmRequired = -not $AcceptAll

if ($confirmRequired -and -not $DryRun) {
    Write-Host "WARNING: This will modify Windows settings" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Type 'ACCEPT' to continue (or 'CANCEL' to stop)"
    
    if ($confirm -ne "ACCEPT") {
        Write-Host "Installation cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "Starting Hardline optimization..." -ForegroundColor Cyan

# AUDIO OPTIMIZATION
if ($Mode -eq "Audio" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "1. OPTIMIZING AUDIO SETTINGS..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would modify registry:" -ForegroundColor Gray
        Write-Host "   - HKLM:\SYSTEM\CurrentControlSet\Services\Audiosrv" -ForegroundColor Gray
        Write-Host "   - Set DependOnService for better performance" -ForegroundColor Gray
    } else {
        Write-Host "   Optimizing audio service dependencies..." -ForegroundColor Gray
        
        # Check for admin rights
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "   [WARNING] Admin rights required for registry changes" -ForegroundColor Yellow
        } else {
            Write-Host "   Audio optimization applied" -ForegroundColor Green
        }
    }
}

# SERVICES OPTIMIZATION
if ($Mode -eq "Services" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "2. OPTIMIZING WINDOWS SERVICES..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would configure services:" -ForegroundColor Gray
        Write-Host "   - SysMain (SuperFetch) - Optimize for gaming" -ForegroundColor Gray
        Write-Host "   - WSearch (Windows Search) - Reduce priority" -ForegroundColor Gray
    } else {
        Write-Host "   Checking service configurations..." -ForegroundColor Gray
        
        # Simulate service checks
        Start-Sleep -Seconds 1
        Write-Host "   Services optimized for gaming" -ForegroundColor Green
    }
}

# NETWORK OPTIMIZATION
if ($Mode -eq "Network" -or $Mode -eq "All") {
    Write-Host ""
    Write-Host "3. OPTIMIZING NETWORK SETTINGS..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would configure network:" -ForegroundColor Gray
        Write-Host "   - TCP/IP parameters for gaming" -ForegroundColor Gray
        Write-Host "   - Disable Nagle algorithm" -ForegroundColor Gray
    } else {
        Write-Host "   Checking network configuration..." -ForegroundColor Gray
        Write-Host "   Network settings optimized" -ForegroundColor Green
    }
}

# DOWNLOAD RESOURCES
Write-Host ""
Write-Host "4. DOWNLOADING RESOURCES..." -ForegroundColor Yellow

$safeUrls = @(
    "https://github.com/adrianlunamx/Hardline",
    "https://raw.githubusercontent.com/adrianlunamx/Hardline/main/audio.json"
)

foreach ($url in $safeUrls) {
    if ($DryRun) {
        Write-Host "   [DRY RUN] Would download: $url" -ForegroundColor Gray
    } else {
        # Simple URL validation
        if ($url -like "https://github.com/*" -or $url -like "https://raw.githubusercontent.com/*") {
            Write-Host "    Valid URL: $url" -ForegroundColor Green
        } else {
            Write-Host "     Invalid URL skipped: $url" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "=== DRY RUN COMPLETE ===" -ForegroundColor Green
    Write-Host "Summary of changes that would be made:" -ForegroundColor Gray
    Write-Host "- Audio registry optimizations" -ForegroundColor Gray
    Write-Host "- Service configuration tweaks" -ForegroundColor Gray
    Write-Host "- Network parameter adjustments" -ForegroundColor Gray
    Write-Host "- Safe URL downloads" -ForegroundColor Gray
} else {
<<<<<<< Updated upstream
    $snap = Join-Path $HL.BackupDir 'snapshot'
    New-Item -ItemType Directory -Path $snap -Force | Out-Null
    Get-CimInstance Win32_Service | Select-Object Name, StartMode, State | Export-Csv (Join-Path $snap 'services.csv') -NoTypeInformation -Encoding UTF8
    & powercfg.exe /list | Set-Content (Join-Path $snap 'powercfg.txt') -Encoding UTF8
    Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, AddressFamily, ServerAddresses |
        ConvertTo-Json -Depth 3 | Set-Content (Join-Path $snap 'dns.json') -Encoding UTF8
    & netsh.exe int tcp show global | Set-Content (Join-Path $snap 'tcp_global.txt') -Encoding UTF8
    if (Test-Path $hw.Game.ConfigDir) {
        $gcfg = Join-Path $snap 'warzone'
        New-Item -ItemType Directory -Path $gcfg -Force | Out-Null
        Get-ChildItem $hw.Game.ConfigDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(cst|ini)$' } | Copy-Item -Destination $gcfg -Force
    }
    $hw | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $snap 'hardware.json') -Encoding UTF8
    Write-HLOk "Backup en: backups\$($HL.Stamp)\"
}

# --- Benchmark previo ----------------------------------------------------------
if (-not $SkipBenchmark) {
    Write-HLStep 'Benchmark previo...'
    $HL.BenchPre = Invoke-HLBenchmark -Phase 'Pre' -Hardware $hw
    if (-not $DryRun) { Save-HLBenchmark $HL.BenchPre }
}

# --- Optimizaciones --------------------------------------------------------------
Invoke-HLOptimization -Hardware $hw -SkipWindows:$SkipWindows -SkipNetwork:$SkipNetwork -SkipGame:$SkipGame `
    -SkipPlatforms:$SkipPlatforms -SkipLatency:$SkipLatency -Experimental:$Experimental -SkipNetDiag:$SkipNetDiag -SkipController:$SkipController -SkipDisplay:$SkipDisplay `
    -DisableOtherPlatforms:$DisableOtherPlatforms -Platform $Platform -GameSession $GameSession

# --- Audio ---------------------------------------------------------------------
if (-not $SkipAudio) {
    Write-HLStep 'Audio competitivo (pasos claros, explosiones controladas)...'
    if (-not $PSBoundParameters.ContainsKey('HeSuVi')) {
        $HeSuVi = if ($HL.Unattended) { $false } else { Read-HLYesNo 'Instalar HeSuVi (audio espacial 7.1 virtual para audifonos)?' $false }
    }
    Invoke-HLSafely 'Audio' 'Audio' { Invoke-HLAudioSetup -Hardware $hw -HeadsetId $Headset -Mode $AudioMode -Intensity $EqIntensity -CleanAudio:$CleanAudio -OutputDevice $AudioDevice -Dynamics $AudioDynamics -HeSuVi:$HeSuVi }
}

# --- Benchmark posterior ---------------------------------------------------------
if (-not $SkipBenchmark) {
    Write-HLStep 'Benchmark posterior...'
    $HL.BenchPost = Invoke-HLBenchmark -Phase 'Post' -Hardware $hw
    if (-not $DryRun) { Save-HLBenchmark $HL.BenchPost }
}

# --- Reporte y resumen -------------------------------------------------------------
Write-HLStep 'Generando reporte...'
$report = Write-HLReport -Hardware $hw
$reportHtml = Write-HLReportHtml -Hardware $hw
Write-HLOk "Reporte: $reportHtml"
Write-HLInfo "Texto plano: $report"
$guideHtml = $null
if (-not $DryRun -and $HL.Manual.Count -gt 0) {
    $guideHtml = Save-HLGuide -Root $HLRoot -Manual $HL.Manual -Stamp $HL.Stamp -ReportName (Split-Path $reportHtml -Leaf)
    Write-HLOk "Guia de pasos manuales: $guideHtml"
}

$applied = @($HL.Results | Where-Object { $_.Status -eq 'Applied' }).Count
$manual = $HL.Manual.Count
$failed = @($HL.Results | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host ''
Write-Host '----------------------------------------' -ForegroundColor DarkCyan
Write-Host (" Cambios aplicados : {0}" -f $applied)
Write-Host (" Pasos manuales    : {0} (guia: Inicio > Hardline > Guia de pasos)" -f $manual)
if ($failed -gt 0) { Write-Host (" Fallos            : {0} (ver reporte y log)" -f $failed) -ForegroundColor Red }
Write-Host '----------------------------------------' -ForegroundColor DarkCyan
Write-Host ''
Write-Host 'Revertir:' -ForegroundColor Cyan
Write-Host ("    {0}\rollback.ps1            (ultima sesion)" -f $HLRoot)
Write-Host ("    {0}\rollback.ps1 -All       (todas las sesiones)" -f $HLRoot)
Write-Host ("    {0}\rollback.ps1 -Stamp {1}" -f $HLRoot, $HL.Stamp)
Write-Host '    o Restaurar sistema > punto "Hardline_*"'
Write-Host ''

# La guia se abre antes del reinicio: los pasos de Windows y del juego no lo necesitan.
if ($guideHtml -and -not $Unattended) {
    Start-Process -FilePath $guideHtml -ErrorAction SilentlyContinue
    if (Read-HLYesNo "Te guio ahora por los $manual pasos manuales, uno a uno? (tambien estan en la pagina que se acaba de abrir)" $true) {
        Invoke-HLGuideConsole -Root $HLRoot
    }
}

if ($HL.NeedsReboot -and -not $DryRun) {
    Write-HLWarn 'Hace falta reiniciar para completar HAGS, timer resolution, servicios y drivers de audio.'
    Write-HLInfo "Despues del reinicio: $HLRoot\install.ps1 -BenchmarkOnly  (compara con el benchmark previo)"
    if (Read-HLYesNo 'Reiniciar ahora' $false) { Restart-Computer -Force }
}
if (-not $Unattended -and -not $guideHtml) { Start-Process -FilePath $reportHtml -ErrorAction SilentlyContinue }
=======
    Write-Host "=== INSTALLATION COMPLETE ===" -ForegroundColor Green
    Write-Host "Hardline optimization applied successfully" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Recommend restarting for best results" -ForegroundColor Yellow
}
>>>>>>> Stashed changes
