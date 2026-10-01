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
function Get-HLVoicemeeterRunType {
    param([string[]] $Files)
    $f = @($Files | ForEach-Object { "$_".ToLowerInvariant() })
    foreach ($c in @(@{ Exe = 'voicemeeter8x64.exe'; T = 6 }, @{ Exe = 'voicemeeter8.exe'; T = 3 }, @{ Exe = 'voicemeeterpro_x64.exe'; T = 5 },
            @{ Exe = 'voicemeeterpro.exe'; T = 2 }, @{ Exe = 'voicemeeter_x64.exe'; T = 4 }, @{ Exe = 'voicemeeter.exe'; T = 1 })) {
        if ($c.Exe -in $f) { return $c.T }
    }
    return 0
}

function Connect-HLVoicemeeter {
    param([Parameter(Mandatory)] [string] $Dir)

    Initialize-HLVoicemeeterApi -Dir $Dir
    $r = [Hardline.VMR]::VBVMR_Login()
    if ($r -lt 0) { throw "VBVMR_Login devolvió $r" }
    if ($r -eq 1) {
        # 1 = API OK pero Voicemeeter no está abierto: se abre la edición instalada.
        $type = Get-HLVoicemeeterRunType -Files @(Get-ChildItem $Dir -Filter 'voicemeeter*.exe' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($type -eq 0) { throw 'No se encontró el ejecutable de Voicemeeter.' }
        [void][Hardline.VMR]::VBVMR_RunVoicemeeter($type)
        Start-Sleep -Seconds 3
    }
    $t = 0
    for ($i = 0; $i -lt 20; $i++) {
        if ([Hardline.VMR]::VBVMR_GetVoicemeeterType([ref]$t) -eq 0) { break }
        Start-Sleep -Milliseconds 500
    }
    # 1 = Voicemeeter, 2 = Banana, 3 = Potato
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
function New-HLVoicemeeterScript {
    param(
        [Parameter(Mandatory)] [string] $XmlPath,
        [Parameter(Mandatory)] [string] $HeadsetDevice,
        $Overrides,
        [int]$VoicemeeterType = 3
    )
    [xml]$x = Get-Content -Path $XmlPath -Raw -Encoding UTF8
    $root = $x.HardlineVoicemeeter
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fmt = { param($v) ([double]$v).ToString('0.###', $inv) }

    $gate = $root.Gate
    $comp = $root.Compressor
    $gateThr = $gate.threshold_db; $ratio = $comp.ratio; $thr = $comp.threshold_db
    $att = $comp.attack_ms; $rel = $comp.release_ms; $mk = $comp.makeup_db
    if ($Overrides) {
        if ($null -ne $Overrides.gate_threshold_db) { $gateThr = $Overrides.gate_threshold_db }
        if ($null -ne $Overrides.comp_ratio)        { $ratio = $Overrides.comp_ratio }
        if ($null -ne $Overrides.comp_threshold_db) { $thr = $Overrides.comp_threshold_db }
        if ($null -ne $Overrides.comp_attack_ms)    { $att = $Overrides.comp_attack_ms }
        if ($null -ne $Overrides.comp_release_ms)   { $rel = $Overrides.comp_release_ms }
        if ($null -ne $Overrides.comp_makeup_db)    { $mk = $Overrides.comp_makeup_db }
    }

    $g = [int]$root.GameStrip.index
    $s = [int]$root.SystemStrip.index
    $b = [int]$root.OutputBus.index
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add(('Bus[{0}].device.{1}="{2}";' -f $b, $root.OutputBus.driver, $HeadsetDevice))
    $lines.Add(('Strip[{0}].device.{1}="{2}";' -f $g, $root.GameStrip.driver, $root.GameStrip.device))
    $lines.Add(('Strip[{0}].Label="{1}";' -f $g, $root.GameStrip.label))
    foreach ($send in $root.GameStrip.Send) { $lines.Add(('Strip[{0}].{1}={2};' -f $g, $send.bus, $send.on)) }
    $lines.Add(('Strip[{0}].Label="{1}";' -f $s, $root.SystemStrip.label))
    foreach ($send in $root.SystemStrip.Send) { $lines.Add(('Strip[{0}].{1}={2};' -f $s, $send.bus, $send.on)) }

    # Knobs primero (activan el bloque), parámetros avanzados después.
    $lines.Add(('Strip[{0}].Gate={1};' -f $g, (& $fmt $gate.knob)))
    $lines.Add(('Strip[{0}].Comp={1};' -f $g, (& $fmt $comp.knob)))

    if ($VoicemeeterType -ge 3) {
        # Parámetros avanzados: solo Potato los expone por API.
        $lines.Add(('Strip[{0}].Gate.Threshold={1};' -f $g, (& $fmt $gateThr)))
        $lines.Add(('Strip[{0}].Gate.Damping={1};' -f $g, (& $fmt $gate.damping_db)))
        $lines.Add(('Strip[{0}].Gate.Attack={1};' -f $g, (& $fmt $gate.attack_ms)))
        $lines.Add(('Strip[{0}].Gate.Hold={1};' -f $g, (& $fmt $gate.hold_ms)))
        $lines.Add(('Strip[{0}].Gate.Release={1};' -f $g, (& $fmt $gate.release_ms)))
        $lines.Add(('Strip[{0}].Comp.Ratio={1};' -f $g, (& $fmt $ratio)))
        $lines.Add(('Strip[{0}].Comp.Threshold={1};' -f $g, (& $fmt $thr)))
        $lines.Add(('Strip[{0}].Comp.Attack={1};' -f $g, (& $fmt $att)))
        $lines.Add(('Strip[{0}].Comp.Release={1};' -f $g, (& $fmt $rel)))
        $lines.Add(('Strip[{0}].Comp.Knee={1};' -f $g, (& $fmt $comp.knee)))
        $lines.Add(('Strip[{0}].Comp.MakeUp={1};' -f $g, $comp.auto_makeup))
        $lines.Add(('Strip[{0}].Comp.GainOut={1};' -f $g, (& $fmt $mk)))
    }
    return $lines
}

function Set-HLVoicemeeterConfig {
    param(
        [Parameter(Mandatory)] [string] $XmlPath,
        [Parameter(Mandatory)] [string] $HeadsetDevice,
        $Overrides
    )
    $dir = Get-HLVoicemeeterDir
    if (-not $dir) { throw 'Voicemeeter no está instalado.' }

    $type = Connect-HLVoicemeeter -Dir $dir
    try {
        if ($type -lt 3) { Write-HLWarn "Voicemeeter tipo $type (no Potato): solo se configuran los knobs, sin parámetros avanzados del compresor." }
        $stmts = New-HLVoicemeeterScript -XmlPath $XmlPath -HeadsetDevice $HeadsetDevice -Overrides $Overrides -VoicemeeterType $type
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
