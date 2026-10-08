#Requires -Version 5.1
<#
    Hardline - nombres de los dispositivos de audio.

    Algunos programas de audio (Art Tune, por ejemplo) renombran los
    dispositivos de VB-CABLE en Windows: "CABLE Input" pasa a llamarse
    "Art Tune +" y "CABLE Output" a "Art Tune Unified Output". Después las
    instrucciones de Hardline ("marca CABLE Input") no coinciden con lo que ves
    y no sabes qué dispositivo es cuál.

    Aquí se leen y se cambian los nombres con la API de audio de Windows
    (IMMDevice / IPropertyStore, la misma que usa "Cambiar nombre" en
    Configuración > Sonido). Hace falta administrador. El nombre anterior
    queda en el manifiesto y el rollback lo devuelve.
#>

$script:HLEndpointModule = $PSCommandPath

function Initialize-HLEndpointApi {
    if ('Hardline.AudioEndpoints' -as [type]) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Hardline {
    [StructLayout(LayoutKind.Sequential)]
    public struct PropKey { public Guid fmtid; public int pid; public PropKey(string g, int p) { fmtid = new Guid(g); pid = p; } }

    // PROPVARIANT: 16 bytes en 32 bits, 24 en 64 bits.
    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr p;
        [FieldOffset(8)] public long pad1;
        [FieldOffset(16)] public long pad2;
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out int count);
        int GetAt(int index, out PropKey key);
        int GetValue(ref PropKey key, out PropVariant value);
        int SetValue(ref PropKey key, ref PropVariant value);
        int Commit();
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
        int OpenPropertyStore(int access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int flow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    // IPolicyConfig: la interfaz que usa el panel de Sonido de Windows para
    // "Permitir / No permitir" un dispositivo. No está documentada, pero es
    // estable desde Windows 7 (la usan SoundSwitch, EarTrumpet, nircmd...).
    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig {
        int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr fmt);
        int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int def, IntPtr fmt);
        int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
        int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr a, IntPtr b);
        int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, int def, IntPtr a, IntPtr b);
        int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr a);
        int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr m);
        int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr m);
        int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr pv);
        int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr pv);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
        int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
    }

    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    class PolicyConfigCom { }

    public static class AudioEndpoints {
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant pv);
        static readonly PropKey DeviceDesc = new PropKey("a45c254e-df1c-4efd-8020-67d146a850e0", 2);
        static readonly PropKey InterfaceName = new PropKey("026e516e-b814-414b-83cd-856d6fef4822", 2);
        static readonly PropKey IconPath = new PropKey("259abffc-50a7-47ce-af08-68c9a7d73366", 12);
        const int VT_LPWSTR = 31, ACTIVE = 1, STGM_READ = 0, STGM_READWRITE = 2;

        static string Read(IPropertyStore s, PropKey k) {
            PropVariant v;
            if (s.GetValue(ref k, out v) != 0) return "";
            try { return v.vt == VT_LPWSTR ? Marshal.PtrToStringUni(v.p) : ""; } finally { PropVariantClear(ref v); }
        }

        // Dispositivos activos: id, flujo (0 = reproducción, 1 = grabación), nombre, nombre del driver, icono.
        public static string[][] List() {
            var list = new List<string[]>();
            var e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            for (int flow = 0; flow <= 1; flow++) {
                IMMDeviceCollection c;
                if (e.EnumAudioEndpoints(flow, ACTIVE, out c) != 0) continue;
                int n; c.GetCount(out n);
                for (int i = 0; i < n; i++) {
                    IMMDevice d; if (c.Item(i, out d) != 0) continue;
                    string id; d.GetId(out id);
                    IPropertyStore s; if (d.OpenPropertyStore(STGM_READ, out s) != 0) continue;
                    list.Add(new[] { id, flow.ToString(), Read(s, DeviceDesc), Read(s, InterfaceName), Read(s, IconPath) });
                }
            }
            return list.ToArray();
        }

        // Salida predeterminada de Windows (rol consola): "nombre (driver)", o "".
        public static string DefaultRender() {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice d; if (e.GetDefaultAudioEndpoint(0, 0, out d) != 0) return "";
            IPropertyStore s; if (d.OpenPropertyStore(STGM_READ, out s) != 0) return "";
            string desc = Read(s, DeviceDesc), iface = Read(s, InterfaceName);
            return iface.Length > 0 ? desc + " (" + iface + ")" : desc;
        }

        // Id del predeterminado: flow 0/1, role 0 = general, 2 = comunicaciones. "" si no hay.
        public static string DefaultId(int flow, int role) {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice d; if (e.GetDefaultAudioEndpoint(flow, role, out d) != 0) return "";
            string id; d.GetId(out id); return id;
        }

        // "Permitir" / "No permitir" del panel de Sonido. 0 = correcto.
        public static int SetVisibility(string id, bool visible) {
            var p = (IPolicyConfig)new PolicyConfigCom();
            return p.SetEndpointVisibility(id, visible ? 1 : 0);
        }

        // 0 = correcto; si no, el HRESULT (acceso denegado sin administrador).
        public static int Rename(string id, string name) { return SetString(id, DeviceDesc, name); }

        // Icono ("ruta,índice"), el que Configuración > Sonido muestra junto al nombre.
        public static int SetIcon(string id, string path) { return SetString(id, IconPath, path); }

        static int SetString(string id, PropKey key, string value) {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice d; int hr = e.GetDevice(id, out d); if (hr != 0) return hr;
            IPropertyStore s; hr = d.OpenPropertyStore(STGM_READWRITE, out s); if (hr != 0) return hr;
            var v = new PropVariant(); v.vt = VT_LPWSTR; v.p = Marshal.StringToCoTaskMemUni(value);
            var k = key;
            try { hr = s.SetValue(ref k, ref v); if (hr == 0) hr = s.Commit(); }
            finally { Marshal.FreeCoTaskMem(v.p); }
            return hr;
        }
    }
}
'@
}

<#
    Nombre de fábrica de un dispositivo virtual de VB-Audio según su driver y
    flujo, o '' si no es uno que Hardline use. VB-CABLE principal y la
    entrada principal de Voicemeeter (VAIO): son los nombres que citan las
    instrucciones. AUX, VAIO3 y los cables A/B no se tocan.
#>
function Get-HLCableDefaultName {
    param([string] $InterfaceName, [int] $Flow)
    switch ($InterfaceName) {
        'VB-Audio Virtual Cable'    { if ($Flow -eq 0) { return 'CABLE Input' } else { return 'CABLE Output' } }
        'VB-Audio Voicemeeter VAIO' { if ($Flow -eq 0) { return 'Voicemeeter Input' } else { return 'Voicemeeter Output' } }
        default { return '' }
    }
}

<#
    Icono de fábrica de VB-CABLE: el que trae su propio driver (dos iconos,
    -100 y -101). '' si no se encuentra el driver.
#>
function Get-HLCableDefaultIcon {
    param([int] $Flow, [string] $DriverStore = (Join-Path $env:windir 'System32\DriverStore\FileRepository'))
    $sys = @(Get-ChildItem $DriverStore -Directory -Filter 'vbmmecable64*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
            ForEach-Object { Get-ChildItem $_.FullName -Filter 'vbaudio_cable64*.sys' -File -ErrorAction SilentlyContinue }) | Select-Object -First 1
    if (-not $sys) { return '' }
    $idx = if ($Flow -eq 0) { -100 } else { -101 }
    return ('{0},{1}' -f $sys.FullName, $idx)
}

# ¿El icono ("ruta,índice") apunta a un archivo que ya no existe?
function Test-HLIconMissing {
    param([string] $Icon)
    if (-not $Icon) { return $false }
    $path = [Environment]::ExpandEnvironmentVariables(($Icon -replace ',\s*-?\d+\s*$', '').Trim('"'))
    if (-not [IO.Path]::IsPathRooted($path)) { return $false }
    return (-not (Test-Path -LiteralPath $path))
}

function Get-HLDefaultRenderName {
    try { Initialize-HLEndpointApi; return [Hardline.AudioEndpoints]::DefaultRender() } catch { return '' }
}

<#
    Puntuación de una salida para A1 de Voicemeeter (el headset). Sin nadie que
    conteste, la primera de la lista suele ser el HDMI del monitor: aquí el
    headset detectado y la salida predeterminada de Windows van primero y las
    salidas de monitor (HDMI / DisplayPort) al final.
#>
function Get-HLRenderDeviceScore {
    param([Parameter(Mandatory)] [string] $Name, [string[]] $HeadsetPatterns = @(), [string] $WindowsDefault = '')
    $score = 0
    foreach ($p in $HeadsetPatterns) { if ($p -and $Name -match $p) { $score += 100; break } }
    if ($WindowsDefault -and $Name -eq $WindowsDefault) { $score += 50 }
    if ($Name -match 'Headphone|Headset|Auricular|Cascos|Speakers|Altavoces|USB|Sound ?Blaster|Realtek|Line Out|Salida') { $score += 10 }
    if ($Name -match 'HDMI|DisplayPort|\bDP\b|AMD High Definition|NVIDIA High Definition|Intel\(R\) Display|Monitor|\bTV\b') { $score -= 100 }
    return $score
}

<#
    Dispositivos de VB-CABLE / VAIO renombrados: Id, Flow, Name, Default.
    $List: filas de [Hardline.AudioEndpoints]::List() (id, flujo, nombre, driver).

    VAIO: Banana y Potato registran varios dispositivos con el mismo driver
    ("Voicemeeter In 1", "Voicemeeter Out B2", "Voicemeeter AUX Input"...):
    cada uno tiene su nombre y no se puede saber cuál era el principal. Solo
    se renombra con un único dispositivo VAIO en ese sentido (edición
    básica) y si su nombre no empieza por "Voicemeeter"; un nombre de
    Voicemeeter nunca se cambia.
#>
function Select-HLRenamedEndpoints {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $List)
    foreach ($d in $List) {
        $flow = [int]$d[1]
        $def = Get-HLCableDefaultName -InterfaceName $d[3] -Flow $flow
        if (-not $def -or $d[2] -eq $def) { continue }
        if ($d[3] -eq 'VB-Audio Voicemeeter VAIO') {
            if ($d[2] -match '^Voicemeeter') { continue }
            $same = @($List | Where-Object { $_[3] -eq $d[3] -and [int]$_[1] -eq $flow }).Count
            if ($same -ne 1) { continue }
        }
        [pscustomobject]@{ Id = $d[0]; Flow = $flow; Name = $d[2]; Default = $def }
    }
}

<#
    Dispositivos virtuales de Voicemeeter que nadie usa. Banana y Potato crean
    hasta 15 (In 1-5, AUX, VAIO3, Out A1-A5, B1-B3) que llenan las listas de
    Windows, Discord y el juego. Se conservan:
      - "Voicemeeter Input": el sonido del sistema (Discord, navegador) entra
        por ahí a Voicemeeter;
      - "Voicemeeter Out B1" / "Voicemeeter Output": la salida virtual
        principal, la que se usa como micrófono si pasas tu voz por Voicemeeter;
      - cualquiera que sea predeterminado en Windows (general o comunicaciones).
    $List: filas de List(); $DefaultIds: ids de los predeterminados.
#>
function Select-HLUnusedVaioEndpoints {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $List, [string[]] $DefaultIds = @())
    $keep = @('Voicemeeter Input', 'Voicemeeter Out B1', 'Voicemeeter Output')
    foreach ($d in $List) {
        if ($d[3] -notlike 'VB-Audio Voicemeeter*') { continue }
        if ($d[2] -in $keep) { continue }
        if ($DefaultIds -contains $d[0]) { continue }
        [pscustomobject]@{ Id = $d[0]; Flow = [int]$d[1]; Name = $d[2] }
    }
}

<#
    Los oculta como "No permitir" en el panel de Sonido (lo mismo que harías
    a mano). Deshabilitarlos en el Administrador de dispositivos no basta: el
    sistema de audio los sigue dando por activos y siguen en las listas. Solo
    se tocan los que están activos: si ya los ocultaste tú, no hace nada.
    Revertible: el rollback los vuelve a permitir. Hace falta administrador.
    Devuelve cuántos se ocultaron.
#>
function Hide-HLUnusedVaioEndpoints {
    if ($HL.DryRun) { return 0 }
    try {
        Initialize-HLEndpointApi
        $list = @([Hardline.AudioEndpoints]::List())
        $defaults = @(foreach ($f in 0, 1) { foreach ($r in 0, 2) { [Hardline.AudioEndpoints]::DefaultId($f, $r) } }) | Where-Object { $_ }
    } catch { Write-HLLog WARN "No se pudieron leer los dispositivos de audio: $($_.Exception.Message)"; return 0 }
    $hidden = @()
    foreach ($e in @(Select-HLUnusedVaioEndpoints -List $list -DefaultIds $defaults)) {
        # Se registra antes de cambiar: si falla a medias, el undo solo vuelve a permitirlo.
        Add-HLManifestEntry -Type 'EndpointVisibility' -Data @{ Id = $e.Id; Name = $e.Name; ModulePath = $script:HLEndpointModule }
        $hr = [Hardline.AudioEndpoints]::SetVisibility($e.Id, $false)
        if ($hr -ne 0) { Write-HLLog WARN ("No se pudo ocultar {0} (0x{1:X8})" -f $e.Name, $hr); continue }
        $hidden += $e.Name
    }
    if ($hidden.Count) {
        Write-HLSub "Dispositivos de Voicemeeter sin uso ocultos: $($hidden.Count)" 'OK'
        Add-HLResult -Module 'Audio' -Item 'Voicemeeter: dispositivos sin uso' -Status Applied -Detail ("Ocultos: {0}. Quedan Voicemeeter Input, Out B1 y los predeterminados. El rollback los vuelve a permitir." -f ($hidden -join ', '))
    }
    return $hidden.Count
}

function Get-HLRenamedCables {
    Initialize-HLEndpointApi
    Select-HLRenamedEndpoints -List @([Hardline.AudioEndpoints]::List())
}

function Set-HLEndpointName {
    param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Name, [string] $PrevName = '')
    if ($HL.DryRun) { return $true }
    Initialize-HLEndpointApi
    # Se registra antes de renombrar (mismo patrón que Set-HLRegistryValue):
    # si Rename() falla, el undo devuelve el nombre previo, que es el actual.
    Add-HLManifestEntry -Type 'AudioEndpointName' -Data @{ Id = $Id; PrevName = $PrevName; NewName = $Name; ModulePath = $script:HLEndpointModule }
    $hr = [Hardline.AudioEndpoints]::Rename($Id, $Name)
    if ($hr -ne 0) { throw ("Windows no dejó cambiar el nombre (0x{0:X8})." -f $hr) }
    return $true
}

# Devuelve a VB-CABLE y a Voicemeeter sus nombres de fábrica. Si no se puede,
# queda como paso manual. Devuelve cuántos se renombraron.
function Restore-HLCableNames {
    $renamed = @()
    $count = 0
    try { $renamed = @(Get-HLRenamedCables) } catch { Write-HLLog WARN "No se pudieron leer los nombres de audio: $($_.Exception.Message)"; return 0 }
    foreach ($c in $renamed) {
        try {
            Set-HLEndpointName -Id $c.Id -Name $c.Default -PrevName $c.Name | Out-Null
            $count++
            Write-HLSub "Nombre de audio: ""$($c.Name)"" -> ""$($c.Default)""" 'OK'
            Add-HLResult -Module 'Audio' -Item "Nombre de $($c.Default)" -Status Applied -Detail "Se llamaba ""$($c.Name)"" (lo renombró otro programa). El rollback lo devuelve."
        } catch {
            Add-HLResult -Module 'Audio' -Item "Nombre de $($c.Default)" -Status Manual -Detail $_.Exception.Message
            $tab = if ($c.Flow -eq 0) { 'Reproducción' } else { 'Grabación' }
            $act = if ($c.Flow -eq 0) { 'sound-playback' } else { 'sound-recording' }
            Add-HLManualStep 'Audio' ("En {0}, ""{1}"" es tu {2}: doble clic > pestaña General y cámbiale el nombre a ""{2}"" para que coincida con las instrucciones." -f $tab, $c.Name, $c.Default) '' $act
        }
    }
    return $count
}

<#
    VB-CABLE con un icono que ya no existe (Art Tune les pone los suyos desde
    ProgramData\ArtTune, que la limpieza aparta): vuelve el icono de su
    driver. El anterior queda en el manifiesto. Devuelve cuántos se cambiaron.
#>
function Restore-HLCableIcons {
    if ($HL.DryRun) { return 0 }
    $count = 0
    try { Initialize-HLEndpointApi; $list = @([Hardline.AudioEndpoints]::List()) } catch { Write-HLLog WARN "No se pudieron leer los iconos de audio: $($_.Exception.Message)"; return 0 }
    foreach ($d in $list) {
        if ($d[3] -ne 'VB-Audio Virtual Cable' -or -not (Test-HLIconMissing $d[4])) { continue }
        $icon = Get-HLCableDefaultIcon -Flow ([int]$d[1])
        if (-not $icon) { continue }
        $hr = [Hardline.AudioEndpoints]::SetIcon($d[0], $icon)
        if ($hr -ne 0) { Write-HLLog WARN ("Icono de {0}: 0x{1:X8}" -f $d[2], $hr); continue }
        Add-HLManifestEntry -Type 'AudioEndpointIcon' -Data @{ Id = $d[0]; PrevIcon = $d[4]; NewIcon = $icon; ModulePath = $script:HLEndpointModule }
        Write-HLSub "Icono de $($d[2]): el de VB-CABLE" 'OK'
        $count++
    }
    return $count
}
