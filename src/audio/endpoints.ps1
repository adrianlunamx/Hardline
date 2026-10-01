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

    public static class AudioEndpoints {
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant pv);
        static readonly PropKey DeviceDesc = new PropKey("a45c254e-df1c-4efd-8020-67d146a850e0", 2);
        static readonly PropKey InterfaceName = new PropKey("026e516e-b814-414b-83cd-856d6fef4822", 2);
        const int VT_LPWSTR = 31, ACTIVE = 1, STGM_READ = 0, STGM_READWRITE = 2;

        static string Read(IPropertyStore s, PropKey k) {
            PropVariant v;
            if (s.GetValue(ref k, out v) != 0) return "";
            try { return v.vt == VT_LPWSTR ? Marshal.PtrToStringUni(v.p) : ""; } finally { PropVariantClear(ref v); }
        }

        // Dispositivos activos: id, flujo (0 = reproducción, 1 = grabación), nombre, nombre del driver.
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
                    list.Add(new[] { id, flow.ToString(), Read(s, DeviceDesc), Read(s, InterfaceName) });
                }
            }
            return list.ToArray();
        }

        // 0 = correcto; si no, el HRESULT (acceso denegado sin administrador).
        public static int Rename(string id, string name) {
            var e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice d; int hr = e.GetDevice(id, out d); if (hr != 0) return hr;
            IPropertyStore s; hr = d.OpenPropertyStore(STGM_READWRITE, out s); if (hr != 0) return hr;
            var v = new PropVariant(); v.vt = VT_LPWSTR; v.p = Marshal.StringToCoTaskMemUni(name);
            var k = DeviceDesc;
            try { hr = s.SetValue(ref k, ref v); if (hr == 0) hr = s.Commit(); }
            finally { Marshal.FreeCoTaskMem(v.p); }
            return hr;
        }
    }
}
'@
}

<#
    Nombre que le corresponde a un dispositivo de VB-CABLE según su driver y
    flujo, o '' si no es de VB-CABLE. Solo el cable principal: los de
    Voicemeeter (VAIO, AUX) y los cables A/B tienen otro nombre de driver.
#>
function Get-HLCableDefaultName {
    param([string] $InterfaceName, [int] $Flow)
    if ($InterfaceName -ne 'VB-Audio Virtual Cable') { return '' }
    if ($Flow -eq 0) { return 'CABLE Input' } else { return 'CABLE Output' }
}

# Dispositivos de VB-CABLE renombrados: Id, Flow, Name, Default.
function Get-HLRenamedCables {
    Initialize-HLEndpointApi
    foreach ($d in [Hardline.AudioEndpoints]::List()) {
        $def = Get-HLCableDefaultName -InterfaceName $d[3] -Flow ([int]$d[1])
        if ($def -and $d[2] -ne $def) { [pscustomobject]@{ Id = $d[0]; Flow = [int]$d[1]; Name = $d[2]; Default = $def } }
    }
}

function Set-HLEndpointName {
    param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Name, [string] $PrevName = '')
    if ($HL.DryRun) { return $true }
    Initialize-HLEndpointApi
    $hr = [Hardline.AudioEndpoints]::Rename($Id, $Name)
    if ($hr -ne 0) { throw ("Windows no dejó cambiar el nombre (0x{0:X8})." -f $hr) }
    Add-HLManifestEntry -Type 'AudioEndpointName' -Data @{ Id = $Id; PrevName = $PrevName; NewName = $Name; ModulePath = $script:HLEndpointModule }
    return $true
}

# Devuelve a VB-CABLE sus nombres de fábrica. Si no se puede, queda como paso manual.
# Devuelve cuántos se renombraron.
function Restore-HLCableNames {
    $renamed = @()
    $count = 0
    try { $renamed = @(Get-HLRenamedCables) } catch { Write-HLLog WARN "No se pudieron leer los nombres de audio: $($_.Exception.Message)"; return 0 }
    foreach ($c in $renamed) {
        try {
            Set-HLEndpointName -Id $c.Id -Name $c.Default -PrevName $c.Name | Out-Null
            $count++
            Write-HLSub "Nombre de VB-CABLE: ""$($c.Name)"" -> ""$($c.Default)""" 'OK'
            Add-HLResult -Module 'Audio' -Item "Nombre de $($c.Default)" -Status Applied -Detail "Se llamaba ""$($c.Name)"" (lo renombró otro programa). El rollback lo devuelve."
        } catch {
            Add-HLResult -Module 'Audio' -Item "Nombre de $($c.Default)" -Status Manual -Detail $_.Exception.Message
            $panel = if ($c.Flow -eq 0) { 'Salida' } else { 'Entrada' }
            Add-HLManualStep 'Audio' ("Configuración > Sistema > Sonido > {0}: ""{1}"" es tu {2}. Ábrelo y en Cambiar nombre pon ""{2}"" para que coincida con las instrucciones." -f $panel, $c.Name, $c.Default)
        }
    }
    return $count
}
