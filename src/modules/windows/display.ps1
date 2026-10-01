#Requires -Version 5.1
<#
    Hardline - pantalla.

    Lo que más se nota al jugar y más a menudo está mal:

      1. Refresco. Un monitor de 144/165/240 Hz funcionando a 60 Hz porque
         Windows lo dejó así al instalarlo o al cambiar de cable. Se compara el
         refresco activo con el máximo que el driver ofrece a esa resolución y,
         si es menor, se sube (revertible). Es la diferencia más grande que
         puede notar alguien: más imágenes por segundo y menos retraso visual.
      2. Optimizaciones para juegos en ventana (Windows 11): el modo "ventana
         sin bordes" usa el mismo modelo de presentación que pantalla completa
         (flip), con la misma latencia. Y VRR para juegos DX11 en ventana.
      3. Overlays: Discord, RivaTuner, Overwolf, Medal... se inyectan en el
         juego y cuestan FPS o añaden un frame de retraso. Se detectan y se
         dice cuál quitar; no se cierran solos.
#>

$script:HLDisplayModule = $PSCommandPath

function Initialize-HLDisplayApi {
    if ('Hardline.DisplayApi' -as [type]) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Hardline {
    public static class DisplayApi {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);

        const int ENUM_CURRENT = -1, ATTACHED = 1, PRIMARY = 4;
        const int DM_WIDTH = 0x80000, DM_HEIGHT = 0x100000, DM_FREQ = 0x400000;
        const int CDS_UPDATEREGISTRY = 1, CDS_TEST = 2;

        static DEVMODE NewMode() { var m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return m; }

        // Pantallas activas: nombre de dispositivo, monitor, principal (1/0).
        public static string[][] Displays() {
            var list = new List<string[]>();
            for (int i = 0; ; i++) {
                var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
                if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
                if ((dd.StateFlags & ATTACHED) == 0) continue;
                var mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(mon);
                string monName = EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0) ? mon.DeviceString : "";
                list.Add(new[] { dd.DeviceName, monName, (dd.StateFlags & PRIMARY) != 0 ? "1" : "0", dd.DeviceString });
            }
            return list.ToArray();
        }

        // Modo actual: ancho, alto, Hz, bits, flags.
        public static int[] Current(string dev) {
            var m = NewMode();
            if (!EnumDisplaySettings(dev, ENUM_CURRENT, ref m)) return new int[0];
            return new[] { m.dmPelsWidth, m.dmPelsHeight, m.dmDisplayFrequency, m.dmBitsPerPel, m.dmDisplayFlags };
        }

        // Todos los modos que ofrece el driver, de 5 en 5 enteros.
        public static int[] Modes(string dev) {
            var list = new List<int>();
            var m = NewMode();
            for (int i = 0; EnumDisplaySettings(dev, i, ref m); i++) {
                list.Add(m.dmPelsWidth); list.Add(m.dmPelsHeight); list.Add(m.dmDisplayFrequency); list.Add(m.dmBitsPerPel); list.Add(m.dmDisplayFlags);
                m = NewMode();
            }
            return list.ToArray();
        }

        // 0 = correcto. Se prueba (CDS_TEST) antes de aplicar.
        public static int SetRefresh(string dev, int width, int height, int hz) {
            var m = NewMode();
            if (!EnumDisplaySettings(dev, ENUM_CURRENT, ref m)) return -100;
            m.dmPelsWidth = width; m.dmPelsHeight = height; m.dmDisplayFrequency = hz;
            m.dmFields = DM_WIDTH | DM_HEIGHT | DM_FREQ;
            int t = ChangeDisplaySettingsEx(dev, ref m, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
            if (t != 0) return t;
            return ChangeDisplaySettingsEx(dev, ref m, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
'@
}

# --------------------------------------------------------------------------
# Cálculo (sin hardware: se prueba en tests\validate.ps1)
# --------------------------------------------------------------------------

<#
    Refresco más alto que ofrece el driver para la resolución actual.
    $Modes: objetos con Width, Height, Hz, Bpp, Flags. Se ignoran los modos
    entrelazados (Flags & 2) y los de menos de 24 bits de color.
#>
function Get-HLBestRefresh {
    param([Parameter(Mandatory)] $Modes, [Parameter(Mandatory)] [int] $Width, [Parameter(Mandatory)] [int] $Height)
    $ok = @($Modes | Where-Object { $_.Width -eq $Width -and $_.Height -eq $Height -and $_.Bpp -ge 24 -and -not ($_.Flags -band 2) -and $_.Hz -gt 1 })
    if ($ok.Count -eq 0) { return 0 }
    return [int](($ok | Measure-Object -Property Hz -Maximum).Maximum)
}

<#
    ¿Merece la pena subir el refresco? Solo si la diferencia es real (59 -> 60
    no cuenta: son el mismo modo con distinto redondeo).
#>
function Test-HLRefreshUpgrade {
    param([int]$CurrentHz, [int]$BestHz)
    return ($BestHz -ge 75 -and ($BestHz - $CurrentHz) -ge 5)
}

# Límite de FPS con FreeSync/G-SYNC: 3 por debajo del refresco, para no salir del rango VRR.
function Get-HLFpsCap {
    param([Parameter(Mandatory)] [int] $Hz)
    if ($Hz -le 0) { return 0 }
    return [Math]::Max(30, $Hz - 3)
}

<#
    DirectXUserGlobalSettings es una cadena "Clave=valor;Clave=valor;". Se
    cambian solo las claves pedidas y se conservan las demás (Auto HDR, etc.).
#>
function Merge-HLDxSettings {
    param([string]$Current, [Parameter(Mandatory)] [hashtable] $Set)
    $pairs = [ordered]@{}
    foreach ($p in ("$Current" -split ';')) {
        if ($p -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') { $pairs[$Matches[1]] = $Matches[2] }
    }
    foreach ($k in $Set.Keys) { $pairs[$k] = "$($Set[$k])" }
    return ((@($pairs.Keys | ForEach-Object { '{0}={1}' -f $_, $pairs[$_] }) -join ';') + ';')
}

# Programas que se inyectan en el juego o compiten por la GPU.
$script:HLOverlays = @(
    @{ Process = 'Discord';               Name = 'Discord';            Advice = 'Discord: Ajustes > Superposición del juego > desactivar "Habilitar superposición". Y Ajustes > Avanzado > desactivar "Aceleración por hardware" si tu GPU va justa.' }
    @{ Process = 'RTSS';                  Name = 'RivaTuner (RTSS)';   Advice = 'RivaTuner: se inyecta en el juego. Si lo usas para limitar FPS, usa el límite del propio Warzone (o Reflex): el de RTSS añade latencia. Ciérralo si no lo necesitas.' }
    @{ Process = 'MSIAfterburner';        Name = 'MSI Afterburner';    Advice = 'MSI Afterburner: si no usas su OSD ni tu curva de undervolt, ciérralo al jugar (arranca RivaTuner con él).' }
    @{ Process = 'Overwolf';              Name = 'Overwolf';           Advice = 'Overwolf: overlay y grabación inyectados en el juego. Ciérralo al jugar Warzone.' }
    @{ Process = 'Medal';                 Name = 'Medal';              Advice = 'Medal: graba en segundo plano y usa GPU y disco. Ciérralo o desactiva la grabación en segundo plano.' }
    @{ Process = 'NVIDIA Overlay';        Name = 'Overlay de NVIDIA';  Advice = 'NVIDIA App: desactiva "Overlay en el juego" e "Instant Replay" si no grabas clips.' }
    @{ Process = 'obs64';                 Name = 'OBS';                Advice = 'OBS: grabar con "Captura de juego" cuesta FPS. Si no estás grabando o emitiendo, ciérralo.' }
    @{ Process = 'GameBar';               Name = 'Xbox Game Bar';      Advice = 'Xbox Game Bar está abierta. Hardline ya desactiva su captura; ciérrala desde el Administrador de tareas si sigue activa.' }
    @{ Process = 'Wallpaper32';           Name = 'Wallpaper Engine';   Advice = 'Wallpaper Engine: configúralo para pausarse con aplicaciones en pantalla completa (Ajustes > Rendimiento > Otra aplicación en pantalla completa: Pausar).' }
    @{ Process = 'wallpaper64';           Name = 'Wallpaper Engine';   Advice = 'Wallpaper Engine: configúralo para pausarse con aplicaciones en pantalla completa (Ajustes > Rendimiento > Otra aplicación en pantalla completa: Pausar).' }
)

# Overlays presentes en una lista de nombres de proceso (sin .exe).
function Get-HLOverlayMatches {
    param([string[]] $ProcessNames)
    $set = @{}
    foreach ($n in $ProcessNames) { if ($n) { $set[$n.ToLowerInvariant()] = $true } }
    $seen = @{}
    foreach ($o in $script:HLOverlays) {
        if ($set.ContainsKey($o.Process.ToLowerInvariant()) -and -not $seen.ContainsKey($o.Name)) {
            $seen[$o.Name] = $true
            $o
        }
    }
}

# --------------------------------------------------------------------------
# Sistema
# --------------------------------------------------------------------------

function Get-HLDisplays {
    Initialize-HLDisplayApi
    foreach ($d in [Hardline.DisplayApi]::Displays()) {
        $c = [Hardline.DisplayApi]::Current($d[0])
        if ($c.Count -lt 5) { continue }
        $raw = [Hardline.DisplayApi]::Modes($d[0])
        $modes = for ($i = 0; $i + 4 -lt $raw.Count; $i += 5) {
            [pscustomobject]@{ Width = $raw[$i]; Height = $raw[$i + 1]; Hz = $raw[$i + 2]; Bpp = $raw[$i + 3]; Flags = $raw[$i + 4] }
        }
        [pscustomobject]@{
            Device = $d[0]; Monitor = $d[1]; Primary = ($d[2] -eq '1'); Adapter = $d[3]
            Width = $c[0]; Height = $c[1]; Hz = $c[2]; Bpp = $c[3]
            BestHz = (Get-HLBestRefresh -Modes @($modes) -Width $c[0] -Height $c[1])
        }
    }
}

# Cambia el refresco y lo anota en el manifiesto (rollback lo devuelve al anterior).
function Set-HLDisplayRefresh {
    param([Parameter(Mandatory)] $Display, [Parameter(Mandatory)] [int] $Hz)
    if ($HL.DryRun) { Write-HLLog INFO "DRYRUN refresco $($Display.Device) $($Display.Hz) -> $Hz Hz"; return $true }
    Initialize-HLDisplayApi
    $r = [Hardline.DisplayApi]::SetRefresh($Display.Device, $Display.Width, $Display.Height, $Hz)
    if ($r -ne 0) { throw "Windows rechazó el modo $($Display.Width)x$($Display.Height) a $Hz Hz (código $r)." }
    Add-HLManifestEntry -Type 'DisplayMode' -Data @{
        Device = $Display.Device; Width = $Display.Width; Height = $Display.Height
        PrevHz = $Display.Hz; NewHz = $Hz; ModulePath = $script:HLDisplayModule
    }
    return $true
}

function Invoke-HLDisplay {
    param([Parameter(Mandatory)] $Hardware)
    Write-HLStep 'Pantalla...'

    # 1. Refresco
    $displays = @()
    try { $displays = @(Get-HLDisplays) } catch { Write-HLWarn "No se pudo leer la configuración de pantalla: $($_.Exception.Message)" }
    $maxHz = 0
    foreach ($d in $displays) {
        $label = '{0}{1} {2}x{3}' -f $(if ($d.Monitor) { $d.Monitor } else { $d.Device }), $(if ($d.Primary) { ' (principal)' } else { '' }), $d.Width, $d.Height
        Write-HLSub ("{0}: {1} Hz (máximo {2} Hz)" -f $label, $d.Hz, $d.BestHz)
        if (Test-HLRefreshUpgrade -CurrentHz $d.Hz -BestHz $d.BestHz) {
            Write-HLWarn "$label funciona a $($d.Hz) Hz y admite $($d.BestHz) Hz."
            if (Read-HLYesNo "¿Subir $label a $($d.BestHz) Hz? (si la pantalla se queda en negro, espera: el rollback lo devuelve a $($d.Hz) Hz)" $true) {
                Invoke-HLSafely 'Pantalla' "Refresco $label" {
                    Set-HLDisplayRefresh -Display $d -Hz $d.BestHz | Out-Null
                    Write-HLSub "Refresco $($d.Hz) -> $($d.BestHz) Hz" 'OK'
                    Add-HLResult -Module 'Pantalla' -Item "Refresco $label" -Status Applied -Detail "$($d.Hz) Hz -> $($d.BestHz) Hz"
                    $d.Hz = $d.BestHz
                }
            } else {
                Add-HLResult -Module 'Pantalla' -Item "Refresco $label" -Status Manual -Detail "A $($d.Hz) Hz pudiendo ir a $($d.BestHz) Hz"
                Add-HLManualStep 'Pantalla' "Configuración > Pantalla > Pantalla avanzada > Frecuencia de actualización: $($d.BestHz) Hz en $label."
            }
        } else {
            Add-HLResult -Module 'Pantalla' -Item "Refresco $label" -Status Skipped -Detail "Ya al máximo ($($d.Hz) Hz)"
        }
        if ($d.Hz -le 60 -and $d.BestHz -le 60 -and $d.Primary) {
            Add-HLManualStep 'Pantalla' "Tu pantalla principal solo ofrece 60 Hz a $($d.Width)x$($d.Height). Si el monitor es de más Hz, el cable o el puerto lo limitan: usa DisplayPort o un HDMI 2.0/2.1 conectado a la tarjeta gráfica, no a la placa."
        }
        if ($d.Primary) { $maxHz = $d.Hz }
    }
    if ($maxHz -gt 0) {
        $HL.DisplayHz = $maxHz
        $cap = Get-HLFpsCap -Hz $maxHz
        Add-HLManualStep 'Pantalla' "Si tu monitor tiene FreeSync/G-SYNC: actívalo en el menú del monitor y en el panel de la GPU, y limita los FPS de Warzone a $cap (3 por debajo de $maxHz Hz). Así no sales del rango VRR: sin tearing y sin la latencia de V-Sync."
    }

    # 2. Optimizaciones para juegos en ventana + VRR (por usuario)
    Invoke-HLSafely 'Pantalla' 'Optimizaciones de ventana' {
        $key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $cur = (Get-HLRegistryValue -Path $key -Name 'DirectXUserGlobalSettings').Value
        $set = @{ VRROptimizeEnable = '1' }
        if ($Hardware.OS.Build -ge 22000) { $set['SwapEffectUpgradeEnable'] = '1' }
        $new = Merge-HLDxSettings -Current $cur -Set $set
        if (Set-HLRegistryValue -Path $key -Name 'DirectXUserGlobalSettings' -Value $new -Type String -Reason 'Optimizaciones para juegos en ventana y VRR') {
            Write-HLSub 'Optimizaciones para juegos en ventana y VRR' 'OK'
            Add-HLResult -Module 'Pantalla' -Item 'Optimizaciones de ventana' -Status Applied -Detail $new
        } else {
            Add-HLResult -Module 'Pantalla' -Item 'Optimizaciones de ventana' -Status Skipped -Detail 'Ya activas'
        }
    }

    # 3. Overlays
    $names = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    $found = @(Get-HLOverlayMatches -ProcessNames $names)
    foreach ($o in $found) {
        Write-HLWarn "$($o.Name) en ejecución: se inyecta en el juego o compite por la GPU."
        Add-HLManualStep 'Overlays' $o.Advice
        Add-HLResult -Module 'Pantalla' -Item $o.Name -Status Manual -Detail 'Overlay o grabación en ejecución'
    }
    if ($found.Count -eq 0) { Write-HLSub 'Overlays inyectados en el juego' 'OK (ninguno abierto)' }
    if ("$($Hardware.Game.Primary)" -match 'steamapps') {
        Add-HLManualStep 'Overlays' 'Steam: Propiedades de Call of Duty > General > desactivar "Activar la interfaz de Steam en el juego".'
    }
}
