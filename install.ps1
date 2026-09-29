<#
.SYNOPSIS
    Hardline - optimizador de Windows/AMD/audio/red para Warzone.

.DESCRIPTION
    Uso en una linea (PowerShell como administrador):
        irm https://raw.githubusercontent.com/jhernandezl2c-hash/CLVX-GMNG/main/install.ps1 | iex

    Con opciones:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jhernandezl2c-hash/CLVX-GMNG/main/install.ps1))) -DryRun

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
    Id de headset de src/audio/profiles/headsets.json (ej. hyperx-cloud-ii).
.PARAMETER AudioMode
    Full (EQ + compresor Voicemeeter) o EqOnly.
#>
[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $Unattended,
    [switch] $SkipWindows,
    [switch] $SkipNetwork,
    [switch] $SkipGame,
    [switch] $SkipAudio,
    [switch] $SkipBenchmark,
    [switch] $NoRestorePoint,
    [switch] $BenchmarkOnly,
    [string] $Headset = '',
    [ValidateSet('', 'Full', 'EqOnly')] [string] $AudioMode = '',
    [string] $Branch = 'main',
    [string] $InstallDir = ''
)

# Sin '#Requires' en este archivo: con "irm | iex" no hay archivo de script y
# Windows PowerShell 5.1 lo trata distinto. Se comprueba a mano.
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host '[x] Hardline necesita PowerShell 5.1 o superior (incluido en Windows 10/11).' -ForegroundColor Red
    return
}

$ErrorActionPreference = 'Stop'
$HLRepoOwner = 'jhernandezl2c-hash'
$HLRepoName = 'CLVX-GMNG'
$HLRawInstaller = "https://raw.githubusercontent.com/$HLRepoOwner/$HLRepoName/$Branch/install.ps1"

# Variables de entorno como alternativa a los parametros (utiles con irm | iex).
if ($env:HARDLINE_DRYRUN -eq '1') { $DryRun = $true }
if ($env:HARDLINE_UNATTENDED -eq '1') { $Unattended = $true }
if ($env:HARDLINE_HEADSET) { $Headset = $env:HARDLINE_HEADSET }
if ($env:HARDLINE_BRANCH) { $Branch = $env:HARDLINE_BRANCH }

# Reconstruye los parametros para relanzar el script (elevado o en PS 5.1).
# Style Command: dentro de una cadena -Command "..." (comillas simples).
# Style File:    para -File (comillas dobles solo si hay espacios).
function Get-HLForwardArgs {
    param([hashtable]$Bound, [ValidateSet('Command', 'File')] [string]$Style = 'Command')
    $out = @()
    foreach ($k in $Bound.Keys) {
        $v = $Bound[$k]
        if ($v -is [System.Management.Automation.SwitchParameter] -or $v -is [bool]) {
            if ($v) { $out += "-$k" }
        } elseif ("$v" -ne '') {
            $out += "-$k"
            if ($Style -eq 'Command') { $out += "'" + ("$v" -replace "'", "''") + "'" }
            elseif ("$v" -match '\s') { $out += '"' + "$v" + '"' }
            else { $out += "$v" }
        }
    }
    return $out
}

# La politica por defecto en Windows cliente es Restricted: sin esto, los
# modulos descargados no se podrian cargar. Solo afecta a este proceso.
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { }

$localRoot = $null
if ($PSCommandPath -and (Test-Path (Join-Path (Split-Path $PSCommandPath -Parent) 'src\core\common.ps1'))) {
    $localRoot = Split-Path $PSCommandPath -Parent
}
$bound = @{}
foreach ($k in $PSBoundParameters.Keys) { $bound[$k] = $PSBoundParameters[$k] }
if ($DryRun) { $bound['DryRun'] = $true }
if ($Unattended) { $bound['Unattended'] = $true }
if ($Headset) { $bound['Headset'] = $Headset }

# ---------------------------------------------------------------------------
# 0. Windows PowerShell 5.1 (Checkpoint-Computer no existe en PowerShell 7)
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host '[*] PowerShell 7 detectado: relanzando en Windows PowerShell 5.1...' -ForegroundColor Cyan
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $fwd = (Get-HLForwardArgs $bound) -join ' '
    if ($localRoot) {
        & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $localRoot 'install.ps1') @(Get-HLForwardArgs $bound -Style File)
    } else {
        & $ps51 -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm '$HLRawInstaller'))) $fwd"
    }
    return
}

# ---------------------------------------------------------------------------
# 1. Permisos de administrador
# ---------------------------------------------------------------------------
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Hacen falta permisos de administrador. Se abre una ventana elevada (UAC)...' -ForegroundColor Yellow
    if ($localRoot) {
        $fwd = (Get-HLForwardArgs $bound -Style File) -join ' '
        $argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$(Join-Path $localRoot 'install.ps1')`" $fwd"
    } else {
        $fwd = (Get-HLForwardArgs $bound) -join ' '
        $argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -Command `"& ([scriptblock]::Create((irm '$HLRawInstaller'))) $fwd`""
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs | Out-Null
    } catch {
        Write-Host '[x] Elevacion cancelada. Abre PowerShell como administrador y vuelve a ejecutar el comando.' -ForegroundColor Red
    }
    return
}

# ---------------------------------------------------------------------------
# 2. Bootstrap: si viene de "irm | iex", descargar el repo completo
# ---------------------------------------------------------------------------
if (-not $localRoot) {
    if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Hardline' }
    Write-Host "[*] Descargando Hardline ($Branch) en $InstallDir ..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ("hardline_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'hardline.zip'
    $zipUrl = "https://github.com/$HLRepoOwner/$HLRepoName/archive/refs/heads/$Branch.zip"
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
    } catch {
        Write-Host "[x] No se pudo descargar $zipUrl : $($_.Exception.Message)" -ForegroundColor Red
        return
    } finally {
        $ProgressPreference = $oldProgress
    }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1
    if (-not $extracted) { Write-Host '[x] El ZIP descargado no contiene install.ps1.' -ForegroundColor Red; return }

    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    # Se conserva lo generado en ejecuciones anteriores (backups, reports, logs).
    Get-ChildItem $extracted.FullName -Force | Where-Object { $_.Name -notin @('backups', 'reports', 'logs') } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $InstallDir -Recurse -Force
    }
    foreach ($d in @('backups', 'reports', 'logs')) {
        $p = Join-Path $InstallDir $d
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    Get-ChildItem $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Descargado. Para revertir mas tarde: $InstallDir\rollback.ps1" -ForegroundColor Green

    & (Join-Path $InstallDir 'install.ps1') @bound
    return
}

# ---------------------------------------------------------------------------
# 3. Ejecucion local
# ---------------------------------------------------------------------------
$HLRoot = $localRoot
. (Join-Path $HLRoot 'src\core\common.ps1')
. (Join-Path $HLRoot 'src\core\detector.ps1')
. (Join-Path $HLRoot 'src\core\optimizer.ps1')

$ErrorActionPreference = 'Continue'

if ($BenchmarkOnly) {
    Initialize-HLSession -Root $HLRoot -Unattended -NoBackup
    Show-HLBanner
    Write-HLStep 'Detectando hardware...'
    $hw = Get-HLHardware
    Write-HLStep 'Benchmark...'
    $HL.BenchPre = Get-HLLastBenchmark -Phase 'pre'
    $HL.BenchPost = Invoke-HLBenchmark -Phase 'Post' -Hardware $hw
    Save-HLBenchmark $HL.BenchPost
    if ($HL.BenchPre) {
        Write-Host ''
        foreach ($r in (Format-HLBenchComparison -Pre $HL.BenchPre -Post $HL.BenchPost)) { Write-Host "    $r" }
    } else {
        Write-HLWarn 'No hay benchmark "pre" guardado para comparar.'
    }
    return
}

Initialize-HLSession -Root $HLRoot -DryRun:$DryRun -Unattended:$Unattended
Show-HLBanner

Write-HLStep 'Verificando permisos...'
Write-HLOk 'Admin OK'
if ($DryRun) { Write-HLWarn 'DryRun: se muestra lo que se haria, sin aplicar nada.' }

if (Test-HLProcess -Name 'cod') {
    Write-HLWarn 'Warzone esta abierto. Cierralo antes de continuar (la config del juego se sobrescribe al salir).'
    if (-not (Read-HLYesNo 'Continuar de todas formas' $false)) { return }
}

# --- Restore point -------------------------------------------------------------
Write-HLStep 'Creando restore point...'
if ($NoRestorePoint -or $DryRun) {
    Write-HLSub 'Restore point' 'SKIP'
} else {
    $rpName = "Hardline_$($HL.Stamp)"
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqPrev = Get-HLRegistryValue -Path $srKey -Name 'SystemRestorePointCreationFrequency'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Windows limita a un punto cada 24 h; se levanta el limite solo durante la llamada.
        New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        Write-HLInfo 'Puede tardar hasta un minuto...'
        Checkpoint-Computer -Description $rpName -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-HLOk "Restore point: $rpName"
        Add-HLResult -Module 'Sistema' -Item 'Restore point' -Status Applied -Detail $rpName
    } catch {
        Write-HLWarn "No se pudo crear el restore point: $($_.Exception.Message)"
        Write-HLInfo 'El manifiesto de Hardline permite revertir igualmente con rollback.ps1.'
        Add-HLResult -Module 'Sistema' -Item 'Restore point' -Status Failed -Detail $_.Exception.Message
        if (-not (Read-HLYesNo 'Continuar sin restore point' $true)) { return }
    } finally {
        if ($freqPrev.Exists) {
            New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value $freqPrev.Value -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        }
    }
}

# --- Hardware ------------------------------------------------------------------
Write-HLStep 'Detectando hardware...'
$hw = Get-HLHardware
$HL.Hardware = $hw
Show-HLHardware -Hw $hw

# --- Backup --------------------------------------------------------------------
Write-HLStep 'Haciendo backup de configs...'
if ($DryRun) {
    Write-HLSub 'Backup' 'SKIP (DryRun)'
} else {
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
Invoke-HLOptimization -Hardware $hw -SkipWindows:$SkipWindows -SkipNetwork:$SkipNetwork -SkipGame:$SkipGame

# --- Audio ---------------------------------------------------------------------
if (-not $SkipAudio) {
    Write-HLStep 'Audio competitivo (pasos claros, explosiones controladas)...'
    Invoke-HLSafely 'Audio' 'Audio' { Invoke-HLAudioSetup -Hardware $hw -HeadsetId $Headset -Mode $AudioMode }
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
Write-HLOk "Reporte: $report"

$applied = @($HL.Results | Where-Object { $_.Status -eq 'Applied' }).Count
$manual = $HL.Manual.Count
$failed = @($HL.Results | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host ''
Write-Host '----------------------------------------' -ForegroundColor DarkCyan
Write-Host (" Cambios aplicados : {0}" -f $applied)
Write-Host (" Pasos manuales    : {0} (BIOS, Adrenalin, Windows; ver reporte)" -f $manual)
if ($failed -gt 0) { Write-Host (" Fallos            : {0} (ver reporte y log)" -f $failed) -ForegroundColor Red }
Write-Host '----------------------------------------' -ForegroundColor DarkCyan
Write-Host ''
Write-Host 'Revertir:' -ForegroundColor Cyan
Write-Host ("    {0}\rollback.ps1            (ultima sesion)" -f $HLRoot)
Write-Host ("    {0}\rollback.ps1 -Stamp {1}" -f $HLRoot, $HL.Stamp)
Write-Host '    o Restaurar sistema > punto "Hardline_*"'
Write-Host ''

if ($HL.NeedsReboot -and -not $DryRun) {
    Write-HLWarn 'Hace falta reiniciar para completar HAGS, timer resolution, servicios y drivers de audio.'
    Write-HLInfo "Despues del reinicio: $HLRoot\install.ps1 -BenchmarkOnly  (compara con el benchmark previo)"
    if (Read-HLYesNo 'Reiniciar ahora' $false) { Restart-Computer -Force }
}
if (-not $Unattended) { Start-Process notepad.exe -ArgumentList "`"$report`"" -ErrorAction SilentlyContinue }
