<#
.SYNOPSIS
    Hardline - optimizador de Windows/AMD/audio/red para Warzone.

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
    Abre la interfaz grafica en lugar del modo consola. Con "irm | iex" sin
    parametros es lo que se abre por defecto.
.PARAMETER Console
    Con "irm | iex" sin otros parametros, usa el modo consola en lugar de
    abrir la interfaz.
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
    Compresor del canal del juego, de menos a mas: suave, normal, pasos
    ("Fuerte": disparos y explosiones mucho mas bajos, pasos muy altos) o
    rush (tiroteos seguidos). Sin el, se mantiene el ultimo elegido.
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
    [ValidateSet('', 'suave', 'normal', 'pasos', 'rush')] [string] $AudioDynamics = '',
    [switch] $Update,
    [switch] $UpdateOnly,
    [switch] $GameplayBenchOnly,
    [switch] $ControllerTestOnly,
    [switch] $Gui,
    [switch] $Console,
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
)

# Sin '#Requires' en este archivo: con "irm | iex" no hay archivo de script y
# Windows PowerShell 5.1 lo trata distinto. Se comprueba a mano.
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host '[x] Hardline necesita PowerShell 5.1 o superior (incluido en Windows 10/11).' -ForegroundColor Red
    return
}

$ErrorActionPreference = 'Stop'
$HLRepoOwner = 'adrianlunamx'
$HLRepoName = 'Hardline'
$HLRawInstaller = "https://raw.githubusercontent.com/$HLRepoOwner/$HLRepoName/$Branch/install.ps1"

# Variables de entorno como alternativa a los parametros (utiles con irm | iex).
if ($env:HARDLINE_DRYRUN -eq '1') { $DryRun = $true }
if ($env:HARDLINE_UNATTENDED -eq '1') { $Unattended = $true }
if ($env:HARDLINE_HEADSET) { $Headset = $env:HARDLINE_HEADSET }
if ($env:HARDLINE_BRANCH) { $Branch = $env:HARDLINE_BRANCH; $Channel = 'main' }
if ($env:HARDLINE_CHANNEL) { $Channel = $env:HARDLINE_CHANNEL }
if ($env:HARDLINE_CONSOLE -eq '1') { $Console = $true }
if ($PSBoundParameters.ContainsKey('Branch')) { $Channel = 'main' }

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
    # La interfaz grafica no necesita ventana de consola detras.
    $winOpt = if ($Gui) { '-WindowStyle Hidden' } else { '-NoExit' }
    if ($localRoot) {
        $fwd = (Get-HLForwardArgs $bound -Style File) -join ' '
        $argLine = "-NoProfile -ExecutionPolicy Bypass $winOpt -File `"$(Join-Path $localRoot 'install.ps1')`" $fwd"
    } else {
        $fwd = (Get-HLForwardArgs $bound) -join ' '
        $argLine = "-NoProfile -ExecutionPolicy Bypass $winOpt -Command `"& ([scriptblock]::Create((irm '$HLRawInstaller'))) $fwd`""
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs | Out-Null
    } catch {
        Write-Host '[x] Elevacion cancelada. Abre PowerShell como administrador y vuelve a ejecutar el comando.' -ForegroundColor Red
    }
    return
}

# -Update desde la copia local: mismo camino que "irm | iex", sobre esta carpeta.
# Se quita de los parametros reenviados para que el install.ps1 nuevo no vuelva a actualizar.
if ($Update -or $UpdateOnly) {
    if ($localRoot) {
        if (-not $InstallDir) { $InstallDir = $localRoot }
        $localRoot = $null
    }
    [void]$bound.Remove('Update')
}

# ---------------------------------------------------------------------------
# 2. Bootstrap: si viene de "irm | iex", descargar el repo completo
# ---------------------------------------------------------------------------
if (-not $localRoot) {
    if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Hardline' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ("hardline_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'hardline.zip'
    $source = $null
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # la barra de IWR en PS 5.1 multiplica el tiempo de descarga
    try {
        # Canal stable: ultima release publicada, con SHA256 verificado.
        if ($Channel -eq 'stable') {
            $rel = $null
            try {
                $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$HLRepoOwner/$HLRepoName/releases/latest" `
                    -Headers @{ 'User-Agent' = 'Hardline-installer'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20 -UseBasicParsing
            } catch {
                # Fail-closed: sin release verificable no se descarga codigo sin
                # verificar. Quien quiera la rama main debe pedirla explicita.
                Write-Host '[x] No hay release publicada o GitHub no responde.' -ForegroundColor Red
                Write-Host '    Instalacion cancelada: Hardline no descarga codigo sin verificar.' -ForegroundColor Red
                Write-Host '    Si confias en el repositorio, usa -Channel main para instalar la rama sin verificacion.' -ForegroundColor Red
                return
            }
            if ($rel) {
                $zipAsset = @($rel.assets | Where-Object { $_.name -match '^hardline-.*\.zip$' }) | Select-Object -First 1
                $shaAsset = @($rel.assets | Where-Object { $_.name -match '^hardline-.*\.zip\.sha256$' }) | Select-Object -First 1
                if ($zipAsset -and $shaAsset) {
                    Write-Host "[*] Descargando Hardline $($rel.tag_name) en $InstallDir ..." -ForegroundColor Cyan
                    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing
                    $shaText = (Invoke-WebRequest -Uri $shaAsset.browser_download_url -UseBasicParsing).Content
                    if ($shaText -is [byte[]]) { $shaText = [Text.Encoding]::ASCII.GetString($shaText) }
                    $expected = ("$shaText".Trim() -split '\s+')[0].ToUpperInvariant()
                    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
                    if ($expected -ne $actual) {
                        # No se cae a main en silencio: un hash distinto es un ZIP corrupto o manipulado.
                        Write-Host "[x] SHA256 no coincide (esperado $expected, obtenido $actual). Instalacion cancelada." -ForegroundColor Red
                        return
                    }
                    Write-Host "[+] SHA256 verificado: $actual" -ForegroundColor Green
                    $source = "release $($rel.tag_name)"
                } else {
                    Write-Host '[x] La release no trae ZIP + .sha256 verificables.' -ForegroundColor Red
                    Write-Host '    Instalacion cancelada: Hardline no descarga codigo sin verificar.' -ForegroundColor Red
                    Write-Host '    Si confias en el repositorio, usa -Channel main para instalar la rama sin verificacion.' -ForegroundColor Red
                    return
                }
            }
        }
        # Canal main (o sin release): ZIP de la rama, sin verificacion.
        if (-not $source) {
            Write-Host "[*] Descargando Hardline (rama $Branch) en $InstallDir ..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://github.com/$HLRepoOwner/$HLRepoName/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
            $source = "rama $Branch"
        }
    } catch {
        Write-Host "[x] Descarga fallida: $($_.Exception.Message)" -ForegroundColor Red
        return
    } finally {
        $ProgressPreference = $oldProgress
    }

    # El ZIP de la rama trae una carpeta raiz (Hardline-main\); el de la release, no.
    $x = Join-Path $tmp 'x'
    Expand-Archive -Path $zip -DestinationPath $x -Force
    $extracted = if (Test-Path (Join-Path $x 'install.ps1')) { Get-Item $x } else {
        Get-ChildItem $x -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'install.ps1') } | Select-Object -First 1
    }
    if (-not $extracted) { Write-Host '[x] El ZIP descargado no contiene install.ps1.' -ForegroundColor Red; return }

    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    # Se conserva lo generado en ejecuciones anteriores (backups, reports, logs, headsets, config).
    $keep = @('backups', 'reports', 'logs', 'headsets', 'config', 'tools')
    Get-ChildItem $extracted.FullName -Force | Where-Object { $_.Name -notin $keep } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $InstallDir -Recurse -Force
    }
    foreach ($d in $keep) {
        $p = Join-Path $InstallDir $d
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
        # Archivos nuevos de la version (plantillas, notas) sin pisar los del usuario.
        $srcDir = Join-Path $extracted.FullName $d
        if (Test-Path $srcDir) {
            Get-ChildItem $srcDir -File -Force | Where-Object { $_.Name -ne '.gitkeep' } | ForEach-Object {
                $dst = Join-Path $p $_.Name
                if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
            }
        }
    }
    Set-Content -Path (Join-Path $InstallDir '.hardline-source') -Value ("{0} | {1:yyyy-MM-dd HH:mm}" -f $source, (Get-Date)) -Encoding ASCII
    Get-ChildItem $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    # Archivos de versiones anteriores que ya no se usan (lista en src\obsolete.txt).
    . (Join-Path $InstallDir 'src\core\common.ps1')
    $gone = @(Remove-HLObsoleteFiles -Root $InstallDir)
    if ($gone.Count -gt 0) { Write-Host ("[+] Limpieza: {0} archivos de versiones anteriores borrados." -f $gone.Count) -ForegroundColor Green }
    if (Install-HLAppShortcut -Root $InstallDir) { Write-Host '[+] Acceso directo: Inicio > Hardline.' -ForegroundColor Green }
    Write-Host "[+] Instalado ($source). Para revertir mas tarde: $InstallDir\rollback.ps1" -ForegroundColor Green

    # Solo actualizar: los archivos nuevos ya estan; nada mas que ejecutar.
    if ($UpdateOnly) {
        $newVer = Select-String -Path (Join-Path $InstallDir 'src\core\common.ps1') -Pattern "HLVersion = '([^']+)'" | Select-Object -First 1
        if ($newVer) { Write-Host ("[+] Hardline actualizado a v{0}." -f $newVer.Matches[0].Groups[1].Value) -ForegroundColor Green }
        return
    }
    # "irm | iex" a secas: la interfaz, que guia mejor que la consola. -Console para la consola.
    [void]$bound.Remove('Console')
    if ($bound.Count -eq 0 -and -not $Console) {
        Write-Host '[*] Abriendo la interfaz de Hardline... (modo consola: -Console)' -ForegroundColor Cyan
        $bound['Gui'] = $true
    }
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
. (Join-Path $HLRoot 'src\core\news.ps1')

$ErrorActionPreference = 'Continue'
if (-not $DryRun) { [void](Remove-HLObsoleteFiles -Root $HLRoot) }

if ($Gui) {
    Install-HLAppShortcut -Root $HLRoot | Out-Null
    try {
        & (Join-Path $HLRoot 'src\gui\app.ps1') -Root $HLRoot
    } catch {
        # La ventana se lanza sin consola: sin esto, un fallo no se ve.
        $msg = "$($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
        try { Add-Content -Path (Join-Path $HLRoot 'logs\gui_error.log') -Value ("{0}`r`n{1}`r`n" -f (Get-Date -Format 's'), $msg) } catch { Write-Verbose 'Sin log' }
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("La interfaz no pudo abrirse:`r`n`r`n$msg`r`n`r`nDetalle en logs\gui_error.log", 'Hardline') | Out-Null
    }
    return
}

if ($GameplayBenchOnly) {
    & (Join-Path $HLRoot 'src\modules\game\gameplay_bench.ps1') -Root $HLRoot
    if (-not $Unattended) { Read-Host 'Pulsa Enter para cerrar' | Out-Null }
    return
}

if ($ControllerTestOnly) {
    & (Join-Path $HLRoot 'src\modules\input\controller_test.ps1')
    if (-not $Unattended) { Read-Host 'Pulsa Enter para cerrar' | Out-Null }
    return
}

if ($NetDiagOnly) {
    Initialize-HLSession -Root $HLRoot -Unattended -NoBackup
    Show-HLBanner
    Write-HLStep 'Detectando red...'
    $hw = Get-HLHardware
    Invoke-HLNetDiagnosis -Hardware $hw | Out-Null
    $report = Write-HLReportHtml -Hardware $hw
    Write-HLOk "Reporte: $report"
    return
}

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
Show-HLUpdateNotice
if (-not $DryRun -and (Install-HLAppShortcut -Root $HLRoot)) { Write-HLInfo 'Interfaz grafica: Inicio > Hardline > Hardline (o install.ps1 -Gui).' }

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
        if ($HL.Unattended) {
            Write-HLErr 'Sin restore point el modo desatendido no continua. Ejecutalo sin -Unattended para decidir, o pasa -NoRestorePoint si aceptas el riesgo.'
            return
        }
        if (-not (Read-HLYesNo 'Continuar sin restore point' $false)) { return }
    } finally {
        if ($freqPrev.Exists) {
            New-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -Value $freqPrev.Value -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        }
    }
}

# --- Que aplicar ---------------------------------------------------------------
# Con cualquier -Skip* o -GameSession explicito se respeta la linea de comandos;
# si no, se muestra el menu (en modo desatendido devuelve los valores por defecto).
$explicit = $PSBoundParameters.Keys | Where-Object { $_ -like 'Skip*' -or $_ -in @('GameSession', 'Experimental') }
if (-not $explicit) {
    $menu = Read-HLChecklist -Title 'Que quieres aplicar' -Items @(
        [pscustomobject]@{ Key = 'windows';   Label = 'Windows: servicios, registro, plan de energia, timer'; Default = $true }
        [pscustomobject]@{ Key = 'display';   Label = 'Pantalla: refresco maximo del monitor, optimizaciones de ventana, overlays'; Default = $true }
        [pscustomobject]@{ Key = 'platforms'; Label = 'Plataformas: cerrar las que no usas (Battle.net, Steam, Xbox)'; Default = $true }
        [pscustomobject]@{ Key = 'session';   Label = 'Modo partida: pausar lo innecesario solo con Warzone abierto'; Default = $true }
        [pscustomobject]@{ Key = 'latency';   Label = 'Latencia avanzada: modo MSI (GPU, red, USB), interrupciones de la NIC'; Default = $true }
        [pscustomobject]@{ Key = 'network';   Label = 'Red: DNS, ahorro de energia de la NIC, QoS'; Default = $true }
        [pscustomobject]@{ Key = 'netdiag';   Label = 'Diagnostico de red: perdida, jitter, bufferbloat, MTU (~40 s)'; Default = $true }
        [pscustomobject]@{ Key = 'game';      Label = 'Warzone: ajustes graficos'; Default = $true }
        [pscustomobject]@{ Key = 'controller'; Label = 'Mando: energia USB del mando, capas de remapeo, ajustes de mando de Warzone'; Default = $true }
        [pscustomobject]@{ Key = 'audio';     Label = 'Audio: EQ de pasos y compresor'; Default = $true }
        [pscustomobject]@{ Key = 'bench';     Label = 'Benchmark antes/despues (~40 s)'; Default = $true }
        [pscustomobject]@{ Key = 'exp';       Label = 'EXPERIMENTAL: disabledynamictick, colas de raton/teclado, prioridad (evidencia debil)'; Default = $false }
    )
    $SkipWindows = -not $menu['windows']
    $SkipPlatforms = -not $menu['platforms']
    $SkipDisplay = -not $menu['display']
    $GameSession = if ($menu['session']) { 'Yes' } else { 'No' }
    $SkipNetwork = -not $menu['network']
    $SkipLatency = -not $menu['latency']
    $SkipNetDiag = -not $menu['netdiag']
    $Experimental = [bool]$menu['exp']
    $SkipGame = -not $menu['game']
    $SkipController = -not $menu['controller']
    $SkipAudio = -not $menu['audio']
    $SkipBenchmark = -not $menu['bench']
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
$newManual = 0
if (-not $DryRun -and $HL.Manual.Count -gt 0) {
    $guideHtml = Save-HLGuide -Root $HLRoot -Manual $HL.Manual -Stamp $HL.Stamp -ReportName (Split-Path $reportHtml -Leaf)
    $newManual = @(Get-HLGuideNewSteps -Root $HLRoot).Count
    Write-HLOk "Guia de pasos manuales: $guideHtml"
}

$applied = @($HL.Results | Where-Object { $_.Status -eq 'Applied' }).Count
$manual = $HL.Manual.Count
$failed = @($HL.Results | Where-Object { $_.Status -eq 'Failed' }).Count
if (-not $DryRun) {
    # Aviso en Hardline EQ: que se aplico, cuantos pasos nuevos y si hay que reiniciar.
    $mods = @($HL.Results | Where-Object { $_.Status -eq 'Applied' -and $_.Module -ne 'Sistema' } | ForEach-Object { $_.Module } | Select-Object -Unique)
    try { Save-HLApplySummary -Root $HLRoot -Stamp $HL.Stamp -Applied $applied -Manual $manual -NewManual $newManual -Failed $failed -NeedsReboot ([bool]$HL.NeedsReboot) -Modules $mods } catch { Write-HLLog WARN "Sin resumen para Hardline EQ: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host '----------------------------------------' -ForegroundColor DarkCyan
Write-Host (" Cambios aplicados : {0}" -f $applied)
Write-Host (" Pasos manuales    : {0}, {1} nuevos (guia: Inicio > Hardline > Guia de pasos)" -f $manual, $newManual)
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
# Cada paso se ensena una sola vez: si no hay nuevos, no se vuelve a ofrecer.
if ($guideHtml -and -not $Unattended -and $newManual -gt 0) {
    Start-Process -FilePath $guideHtml -ErrorAction SilentlyContinue
    if (Read-HLYesNo "Te guio ahora por los $newManual pasos nuevos, uno a uno? (a = te abro el panel de Windows de cada paso)" $true) {
        Invoke-HLGuideConsole -Root $HLRoot -OnlyNew
    }
} elseif ($guideHtml -and -not $Unattended) {
    Write-HLInfo 'Sin pasos nuevos. Los pendientes siguen en Inicio > Hardline > Guia de pasos.'
}

if ($HL.NeedsReboot -and -not $DryRun) {
    Write-HLWarn 'Hace falta reiniciar para completar HAGS, timer resolution, servicios y drivers de audio.'
    Write-HLInfo "Despues del reinicio: $HLRoot\install.ps1 -BenchmarkOnly  (compara con el benchmark previo)"
    if (Read-HLYesNo 'Reiniciar ahora' $false) { Restart-Computer -Force }
}
if (-not $Unattended -and -not $guideHtml) { Start-Process -FilePath $reportHtml -ErrorAction SilentlyContinue }
