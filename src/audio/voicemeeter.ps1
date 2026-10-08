#Requires -Version 5.1
<#
    Hardline - control de Voicemeeter vía Remote API.

    Usa la DLL oficial que instala Voicemeeter (VoicemeeterRemote64.dll).
    Documentación: VoicemeeterRemoteAPI.pdf en la carpeta de instalación, o
    https://github.com/vburel2018/Voicemeeter-SDK
#>

function Get-HLVoicemeeterDir {
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\VB:Voicemeeter {17359A74-1236-5467}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VB:Voicemeeter {17359A74-1236-5467}'
    )
    foreach ($k in $keys) {
        $u = (Get-ItemProperty $k -ErrorAction SilentlyContinue).UninstallString
        if ($u) {
            $dir = Split-Path ($u.Trim('"')) -Parent
            if (Test-Path (Join-Path $dir 'VoicemeeterRemote64.dll')) { return $dir }
        }
    }
    foreach ($d in @("${env:ProgramFiles(x86)}\VB\Voicemeeter", "$env:ProgramFiles\VB\Voicemeeter")) {
        if (Test-Path (Join-Path $d 'VoicemeeterRemote64.dll')) { return $d }
    }
    return $null
}

function Initialize-HLVoicemeeterApi {
    param([Parameter(Mandatory)] [string] $Dir)

    if ('Hardline.VMR' -as [type]) { return }
    $dll = if ([Environment]::Is64BitProcess) { 'VoicemeeterRemote64.dll' } else { 'VoicemeeterRemote.dll' }
    $src = @"
using System;
using System.Runtime.InteropServices;
namespace Hardline {
    public static class VMR {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr LoadLibrary(string path);
        [DllImport("$dll")] public static extern int VBVMR_Login();
        [DllImport("$dll")] public static extern int VBVMR_Logout();
        [DllImport("$dll")] public static extern int VBVMR_RunVoicemeeter(int type);
        [DllImport("$dll")] public static extern int VBVMR_GetVoicemeeterType(out int type);
        [DllImport("$dll")] public static extern int VBVMR_IsParametersDirty();
        [DllImport("$dll", CharSet = CharSet.Ansi)] public static extern int VBVMR_SetParameters(string script);
        [DllImport("$dll", CharSet = CharSet.Ansi)] public static extern int VBVMR_GetParameterFloat(string name, out float value);
    }
}
"@
    Add-Type -TypeDefinition $src -Language CSharp
    # Cargar la DLL por ruta completa primero: los DllImport posteriores
    # resuelven contra el módulo ya cargado.
    $h = [Hardline.VMR]::LoadLibrary((Join-Path $Dir $dll))
    if ($h -eq [IntPtr]::Zero) { throw "No se pudo cargar $dll desde $Dir" }
}

<#
    Edición instalada, para VBVMR_RunVoicemeeter: 1/4 = Voicemeeter, 2/5 =
    Banana, 3/6 = Potato (4-6 = x64). La mejor disponible; 0 si no hay ninguna.
    Abrir una edición que no está instalada deja al programa esperando.
#>
$script:HLVoicemeeterEditions = @(
    @{ Exe = 'voicemeeter8x64.exe'; T = 6 }, @{ Exe = 'voicemeeter8.exe'; T = 3 }, @{ Exe = 'voicemeeterpro_x64.exe'; T = 5 },
    @{ Exe = 'voicemeeterpro.exe'; T = 2 }, @{ Exe = 'voicemeeter_x64.exe'; T = 4 }, @{ Exe = 'voicemeeter.exe'; T = 1 }
)

function Get-HLVoicemeeterRunType {
    param([string[]] $Files)
    $f = @($Files | ForEach-Object { "$_".ToLowerInvariant() })
    foreach ($c in $script:HLVoicemeeterEditions) {
        if ($c.Exe -in $f) { return $c.T }
    }
    return 0
}

<#
    Ruta del ejecutable de la mejor edición instalada en $Dir, o $null.
    Para el arranque con Windows: apuntar a una edición que no está instalada
    (p. ej. voicemeeter8.exe con solo Voicemeeter básico) deja el audio sin
    Voicemeeter tras reiniciar.
#>
function Get-HLVoicemeeterExe {
    param([Parameter(Mandatory)] [string] $Dir)
    foreach ($c in $script:HLVoicemeeterEditions) {
        $p = Join-Path $Dir $c.Exe
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Connect-HLVoicemeeter {
    param([Parameter(Mandatory)] [string] $Dir, [switch] $NoLaunch)

    Initialize-HLVoicemeeterApi -Dir $Dir
    $r = [Hardline.VMR]::VBVMR_Login()
    if ($r -lt 0) { throw "VBVMR_Login devolvió $r" }
    if ($r -eq 1 -and $NoLaunch) {
        [void][Hardline.VMR]::VBVMR_Logout()
        throw 'Voicemeeter no está abierto.'
    }
    if ($r -eq 1) {
        # 1 = API OK pero Voicemeeter no está abierto: se abre la edición instalada.
        $type = Get-HLVoicemeeterRunType -Files @(Get-ChildItem $Dir -Filter 'voicemeeter*.exe' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($type -eq 0) { throw 'No se encontró el ejecutable de Voicemeeter.' }
        [void][Hardline.VMR]::VBVMR_RunVoicemeeter($type)
        Start-Sleep -Seconds 3
    }
    $t = Get-HLRunningVoicemeeterType
    # Abierta una edición peor que la instalada (p. ej. Voicemeeter básico con Potato
    # instalado encima): se cierra y se abre la mejor. Si no, la API configura la
    # que está abierta y el compresor completo de Potato no se usa.
    $best = Get-HLVoicemeeterRunType -Files @(Get-ChildItem $Dir -Filter 'voicemeeter*.exe' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $bestEdition = if ($best -gt 0) { (($best - 1) % 3) + 1 } else { 0 }
    if (-not $NoLaunch -and $t -gt 0 -and $bestEdition -gt $t) {
        Write-HLLog INFO "Voicemeeter abierto: edición $t; instalada: $bestEdition. Se cambia a la instalada."
        [void][Hardline.VMR]::VBVMR_Logout()
        Get-Process -Name 'voicemeeter*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        [void][Hardline.VMR]::VBVMR_Login()
        [void][Hardline.VMR]::VBVMR_RunVoicemeeter($best)
        Start-Sleep -Seconds 3
        $t = Get-HLRunningVoicemeeterType -Expect $bestEdition
    }
    # 1 = Voicemeeter, 2 = Banana, 3 = Potato
    return $t
}

# Edición abierta según la Remote API (espera hasta 10 s, o a la esperada).
function Get-HLRunningVoicemeeterType {
    param([int] $Expect = 0)
    $t = 0
    for ($i = 0; $i -lt 20; $i++) {
        if ([Hardline.VMR]::VBVMR_GetVoicemeeterType([ref]$t) -eq 0 -and ($Expect -eq 0 -or $t -eq $Expect)) { break }
        Start-Sleep -Milliseconds 500
    }
    return $t
}

function Disconnect-HLVoicemeeter {
    if ('Hardline.VMR' -as [type]) { [void][Hardline.VMR]::VBVMR_Logout() }
}

function Wait-HLVoicemeeterSync {
    for ($i = 0; $i -lt 40; $i++) {
        [void][Hardline.VMR]::VBVMR_IsParametersDirty()
        Start-Sleep -Milliseconds 50
    }
}

<#
    Construye el script de parámetros a partir de voicemeeter_comp.xml y de los
    valores del headset. Devuelve una lista de sentencias "Param=valor;".
#>
# Perfiles de dinámica del canal del juego (strip 0).
# De menos a más compresión: es el orden del deslizador del panel del EQ.
$script:HLDynamicsProfiles = [ordered]@{
    suave  = 'Suave: suena casi natural, solo recorta los picos más fuertes'
    normal = 'Normal: explosiones controladas, pasos claros'
    pasos  = 'Fuerte: disparos y explosiones mucho más bajos, pasos muy altos'
    rush   = 'Rush: para tiroteos seguidos; recupera el volumen entre disparo y disparo'
}
$script:HLDynamicsModes = @($script:HLDynamicsProfiles.Keys)

function Limit-HLRange { param([double]$Value, [double]$Min, [double]$Max) return [Math]::Min($Max, [Math]::Max($Min, $Value)) }

<#
    Valores de gate, compresor y limitador para el canal del juego.

    PreampDb: el preamp negativo del EQ (p. ej. -20 dB). Todo llega a
    Voicemeeter así de más bajo, así que los umbrales se desplazan lo mismo:
    sin esto, el gate (calibrado para audio sin EQ) se cerraba con los pasos
    lejanos y el compresor casi no actuaba. Parte de esa pérdida se recupera
    con la ganancia de salida del compresor; el limitador evita saturar.

    Rangos de Voicemeeter Potato: Gate.Threshold -60..-10, Comp.Ratio 1..8,
    Comp.Threshold -40..-3, Comp.GainOut -24..24, Limit -40..12.
#>
function Get-HLDynamicsValues {
    param([Parameter(Mandatory)] $Config, $Overrides, [ValidateSet('suave', 'normal', 'pasos', 'rush')] [string] $Mode = 'normal', [double] $PreampDb = 0)
    $gate = $Config.Gate; $comp = $Config.Compressor
    $pre = [Math]::Min([double]0, [double]$PreampDb)
    $o = @{}
    if ($Overrides) { foreach ($k in @('gate_threshold_db', 'comp_ratio', 'comp_threshold_db', 'comp_attack_ms', 'comp_release_ms', 'comp_makeup_db')) { if ($null -ne $Overrides.$k) { $o[$k] = [double]$Overrides.$k } } }
    $get = { param($k, $def) if ($o.ContainsKey($k)) { $o[$k] } else { [double]$def } }

    if ($Mode -eq 'suave') {
        # 2:1 desde arriba: solo los picos (explosiones, tu arma) bajan algo. Sin gate.
        return [pscustomobject]@{
            GateKnob = 0; GateThr = -60; GateDamping = -20; GateAttack = [double]$gate.attack_ms; GateHold = [double]$gate.hold_ms; GateRelease = [double]$gate.release_ms
            CompKnob = 3; Ratio = 2; Threshold = (Limit-HLRange (-14 + $pre) -40 -3); Attack = 10; Release = 120; Knee = 0.7; AutoMakeup = 0
            GainOut = (Limit-HLRange (2 - $pre / 2) 0 24); Limit = $(if ($pre -lt 0) { -3 } else { 12 })
        }
    }
    if ($Mode -eq 'rush') {
        # Tiroteos seguidos: un arma automática dispara cada 60-100 ms. Con el release de
        # "Fuerte" (50 ms) el volumen no llega a recuperarse entre disparos y los pasos
        # quedan hundidos. Release de 20 ms: vuelve antes del siguiente disparo. El
        # umbral más alto evita que los pasos (más flojos) activen el compresor.
        return [pscustomobject]@{
            GateKnob = 0; GateThr = -60; GateDamping = -20; GateAttack = [double]$gate.attack_ms; GateHold = [double]$gate.hold_ms; GateRelease = [double]$gate.release_ms
            CompKnob = 10; Ratio = 8; Threshold = (Limit-HLRange (-16 + $pre) -40 -3); Attack = 0.5; Release = 20; Knee = 0.2; AutoMakeup = 0
            GainOut = (Limit-HLRange (6 - $pre) 0 24); Limit = -6
        }
    }
    if ($Mode -eq 'pasos') {
        # Todo lo que supera el umbral (disparos, explosiones, granadas) baja 8:1 casi al
        # instante; lo que queda por debajo (pasos, recargas, equipo) sube con la ganancia.
        return [pscustomobject]@{
            GateKnob = 0; GateThr = -60; GateDamping = -20; GateAttack = [double]$gate.attack_ms; GateHold = [double]$gate.hold_ms; GateRelease = [double]$gate.release_ms
            CompKnob = 10; Ratio = 8; Threshold = (Limit-HLRange (-20 + $pre) -40 -3); Attack = 1; Release = 50; Knee = 0.3; AutoMakeup = 0
            GainOut = (Limit-HLRange (4 - $pre) 0 24); Limit = -6
        }
    }
    return [pscustomobject]@{
        GateKnob = [double]$gate.knob; GateThr = (Limit-HLRange ((& $get 'gate_threshold_db' $gate.threshold_db) + $pre) -60 -10)
        # Damping suave: atenúa el fondo sin borrar del todo lo que quede justo por debajo.
        GateDamping = -20; GateAttack = [double]$gate.attack_ms; GateHold = [double]$gate.hold_ms; GateRelease = [double]$gate.release_ms
        CompKnob = [double]$comp.knob; Ratio = (Limit-HLRange (& $get 'comp_ratio' $comp.ratio) 1 8)
        Threshold = (Limit-HLRange ((& $get 'comp_threshold_db' $comp.threshold_db) + $pre) -40 -3)
        Attack = (& $get 'comp_attack_ms' $comp.attack_ms); Release = (& $get 'comp_release_ms' $comp.release_ms); Knee = [double]$comp.knee; AutoMakeup = [int]$comp.auto_makeup
        GainOut = (Limit-HLRange ((& $get 'comp_makeup_db' $comp.makeup_db) + (-$pre / 2)) 0 24); Limit = $(if ($pre -lt 0) { -3 } else { 12 })
    }
}

# Sentencias de la Remote API para la dinámica de una strip.
function New-HLDynamicsStatements {
    param([Parameter(Mandatory)] $Values, [int] $Strip = 0, [int] $VoicemeeterType = 3)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $f = { param($v) ([double]$v).ToString('0.###', $inv) }
    $v = $Values
    $out = New-Object System.Collections.Generic.List[string]
    # Knobs primero (activan el bloque), parámetros avanzados después.
    $out.Add(('Strip[{0}].Gate={1};' -f $Strip, (& $f $v.GateKnob)))
    $out.Add(('Strip[{0}].Comp={1};' -f $Strip, (& $f $v.CompKnob)))
    if ($VoicemeeterType -ge 2) { $out.Add(('Strip[{0}].Limit={1};' -f $Strip, (& $f $v.Limit))) }
    if ($VoicemeeterType -ge 3) {
        # Parámetros avanzados: solo Potato los expone por API.
        $out.Add(('Strip[{0}].Gate.Threshold={1};' -f $Strip, (& $f $v.GateThr)))
        $out.Add(('Strip[{0}].Gate.Damping={1};' -f $Strip, (& $f $v.GateDamping)))
        $out.Add(('Strip[{0}].Gate.Attack={1};' -f $Strip, (& $f $v.GateAttack)))
        $out.Add(('Strip[{0}].Gate.Hold={1};' -f $Strip, (& $f $v.GateHold)))
        $out.Add(('Strip[{0}].Gate.Release={1};' -f $Strip, (& $f $v.GateRelease)))
        $out.Add(('Strip[{0}].Comp.Ratio={1};' -f $Strip, (& $f $v.Ratio)))
        $out.Add(('Strip[{0}].Comp.Threshold={1};' -f $Strip, (& $f $v.Threshold)))
        $out.Add(('Strip[{0}].Comp.Attack={1};' -f $Strip, (& $f $v.Attack)))
        $out.Add(('Strip[{0}].Comp.Release={1};' -f $Strip, (& $f $v.Release)))
        $out.Add(('Strip[{0}].Comp.Knee={1};' -f $Strip, (& $f $v.Knee)))
        $out.Add(('Strip[{0}].Comp.MakeUp={1};' -f $Strip, $v.AutoMakeup))
        $out.Add(('Strip[{0}].Comp.GainOut={1};' -f $Strip, (& $f $v.GainOut)))
    }
    return $out
}

<#
    Construye el script de parámetros a partir de voicemeeter_comp.xml y de los
    valores del headset. Devuelve una lista de sentencias "Param=valor;".
#>
function New-HLVoicemeeterScript {
    param(
        [Parameter(Mandatory)] [string] $XmlPath,
        [Parameter(Mandatory)] [string] $HeadsetDevice,
        $Overrides,
        [int]$VoicemeeterType = 3,
        [ValidateSet('suave', 'normal', 'pasos', 'rush')] [string] $Dynamics = 'normal',
        [double] $PreampDb = 0
    )
    [xml]$x = Get-Content -Path $XmlPath -Raw -Encoding UTF8
    $root = $x.HardlineVoicemeeter

    $g = [int]$root.GameStrip.index
    # Entrada virtual (VAIO) según la edición: Voicemeeter 2, Banana 3, Potato 5.
    $s = switch ($VoicemeeterType) { 1 { 2 } 2 { 3 } default { [int]$root.SystemStrip.index } }
    $b = [int]$root.OutputBus.index
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add(('Bus[{0}].device.{1}="{2}";' -f $b, $root.OutputBus.driver, $HeadsetDevice))
    $lines.Add(('Strip[{0}].device.{1}="{2}";' -f $g, $root.GameStrip.driver, $root.GameStrip.device))
    $lines.Add(('Strip[{0}].Label="{1}";' -f $g, $root.GameStrip.label))
    foreach ($send in $root.GameStrip.Send) { $lines.Add(('Strip[{0}].{1}={2};' -f $g, $send.bus, $send.on)) }
    $lines.Add(('Strip[{0}].Label="{1}";' -f $s, $root.SystemStrip.label))
    foreach ($send in $root.SystemStrip.Send) { $lines.Add(('Strip[{0}].{1}={2};' -f $s, $send.bus, $send.on)) }

    $vals = Get-HLDynamicsValues -Config $root -Overrides $Overrides -Mode $Dynamics -PreampDb $PreampDb
    foreach ($l in (New-HLDynamicsStatements -Values $vals -Strip $g -VoicemeeterType $VoicemeeterType)) { $lines.Add($l) }
    return $lines
}

function Set-HLVoicemeeterConfig {
    param(
        [Parameter(Mandatory)] [string] $XmlPath,
        [Parameter(Mandatory)] [string] $HeadsetDevice,
        $Overrides,
        [ValidateSet('suave', 'normal', 'pasos', 'rush')] [string] $Dynamics = 'normal',
        [double] $PreampDb = 0
    )
    $dir = Get-HLVoicemeeterDir
    if (-not $dir) { throw 'Voicemeeter no está instalado.' }

    $type = Connect-HLVoicemeeter -Dir $dir
    try {
        if ($type -lt 3) { Write-HLWarn "Voicemeeter tipo $type (no Potato): solo se configuran los knobs, sin parámetros avanzados del compresor." }
        $stmts = New-HLVoicemeeterScript -XmlPath $XmlPath -HeadsetDevice $HeadsetDevice -Overrides $Overrides -VoicemeeterType $type -Dynamics $Dynamics -PreampDb $PreampDb
        $failed = @()
        foreach ($stmt in $stmts) {
            $r = [Hardline.VMR]::VBVMR_SetParameters($stmt)
            Write-HLLog DEBUG "VBVMR_SetParameters '$stmt' -> $r"
            if ($r -ne 0) { $failed += "$stmt ($r)" }
        }
        Wait-HLVoicemeeterSync

        # Verificación: leer el ratio aplicado.
        $ratio = [single]0
        if ($type -ge 3 -and [Hardline.VMR]::VBVMR_GetParameterFloat('Strip[0].Comp.Ratio', [ref]$ratio) -eq 0) {
            Write-HLLog INFO "Verificación: Strip[0].Comp.Ratio = $ratio"
        }
        return [pscustomobject]@{ Type = $type; Failed = $failed; Statements = $stmts.Count; VerifiedRatio = $ratio }
    } finally {
        Disconnect-HLVoicemeeter
    }
}

<#
    Cambia solo la dinámica del canal del juego con Voicemeeter abierto (panel
    del EQ). No toca dispositivos ni rutas. No necesita administrador.
#>
function Set-HLVoicemeeterDynamics {
    param([Parameter(Mandatory)] [string] $XmlPath, [ValidateSet('suave', 'normal', 'pasos', 'rush')] [string] $Mode = 'normal', [double] $PreampDb = 0, $Overrides)
    $dir = Get-HLVoicemeeterDir
    if (-not $dir) { throw 'Voicemeeter no está instalado.' }
    [xml]$x = Get-Content -Path $XmlPath -Raw -Encoding UTF8
    $root = $x.HardlineVoicemeeter
    $type = Connect-HLVoicemeeter -Dir $dir -NoLaunch
    try {
        $vals = Get-HLDynamicsValues -Config $root -Overrides $Overrides -Mode $Mode -PreampDb $PreampDb
        $failed = 0
        foreach ($stmt in (New-HLDynamicsStatements -Values $vals -Strip ([int]$root.GameStrip.index) -VoicemeeterType $type)) {
            if ([Hardline.VMR]::VBVMR_SetParameters($stmt) -ne 0) { $failed++ }
        }
        Wait-HLVoicemeeterSync
        return [pscustomobject]@{ Type = $type; Failed = $failed; Values = $vals }
    } finally {
        Disconnect-HLVoicemeeter
    }
}

# config\audio.json: perfil de dinámica, preamp real del EQ y ajustes del headset.
# Lo usan la fase tras reiniciar y el panel del EQ.
function Get-HLAudioSettings {
    param([Parameter(Mandatory)] [string] $Root)
    $f = Join-Path $Root 'config\audio.json'
    $d = $null
    if (Test-Path $f) { try { $d = Get-Content $f -Raw | ConvertFrom-Json } catch { $d = $null } }
    $dyn = if ($d -and "$($d.Dynamics)" -in @('suave', 'normal', 'pasos', 'rush')) { "$($d.Dynamics)" } else { 'normal' }
    $pre = 0.0
    if ($d -and $null -ne $d.PreampDb) { [void][double]::TryParse("$($d.PreampDb)", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pre) }
    return [pscustomobject]@{ Dynamics = $dyn; PreampDb = $pre; Overrides = $(if ($d) { $d.Overrides } else { $null }); HeadsetId = $(if ($d) { "$($d.HeadsetId)" } else { '' }) }
}

function Save-HLAudioSettings {
    param([Parameter(Mandatory)] [string] $Root, [hashtable] $Set)
    $cur = Get-HLAudioSettings -Root $Root
    $o = [ordered]@{ HeadsetId = $cur.HeadsetId; Dynamics = $cur.Dynamics; PreampDb = $cur.PreampDb; Overrides = $cur.Overrides }
    foreach ($k in $Set.Keys) { $o[$k] = $Set[$k] }
    $dir = Join-Path $Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]$o | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'audio.json') -Encoding UTF8
}
