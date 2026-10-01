#Requires -Version 5.1
<#
    Hardline - test de pasos.

    Reproduce dos veces la misma escena sintética (~5 s), primero con el EQ
    apagado y después encendido, por el mismo dispositivo que usa Warzone:

      - 4 pasos lejanos a la izquierda (flojos, -14 dB)
      - una explosión cercana
      - 2 pasos más justo después de la explosión

    Con el EQ encendido los pasos deben oírse claramente más y la explosión
    no debe taparlos. El sonido es generado (no hay grabaciones de terceros).

    Dispositivo: en modo Completo, "CABLE Input" (ahí está el EQ y detrás va
    Voicemeeter con el compresor). En modo Solo EQ, el dispositivo por
    defecto. Se puede forzar con -Device "parte del nombre".

    Uso:  footstep_test.ps1 [-Device "CABLE Input"] [-Once] [-SaveWav archivo.wav]
#>
param([string]$Device = '', [switch]$Once, [string]$SaveWav = '')

. (Join-Path $PSScriptRoot 'eqswitch.ps1')

if (-not ('Hardline.FootstepTest' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace Hardline {
    public static class FootstepTest {
        // ---------------- Síntesis ----------------
        class Biquad {
            double b0, b1, b2, a1, a2, x1, x2, y1, y2;
            public Biquad(string type, double fc, double q, int sr) {
                double w0 = 2 * Math.PI * fc / sr, cs = Math.Cos(w0), alpha = Math.Sin(w0) / (2 * q), a0;
                if (type == "bp") { b0 = alpha; b1 = 0; b2 = -alpha; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; }
                else { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2; a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha; } // lp
                b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;
            }
            public double Run(double x) {
                double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
                x2 = x1; x1 = x; y2 = y1; y1 = y; return y;
            }
        }

        static void AddStep(double[] l, double[] r, int sr, double t0, double gain, double pan, Random rnd) {
            // Golpe grave del talón + textura de suela/superficie en 2-4 kHz.
            var bp1 = new Biquad("bp", 2600, 1.4, sr);
            var bp2 = new Biquad("bp", 3800, 2.0, sr);
            int start = (int)(t0 * sr), len = (int)(0.18 * sr);
            for (int i = 0; i < len && start + i < l.Length; i++) {
                double t = (double)i / sr;
                double thud = Math.Sin(2 * Math.PI * 95 * t) * Math.Exp(-t / 0.022) * 0.5;
                double n = rnd.NextDouble() * 2 - 1;
                double scuff = (bp1.Run(n) * 1.6 + bp2.Run(n) * 0.9) * Math.Exp(-t / 0.035);
                double s = (thud + scuff) * gain;
                l[start + i] += s * (1 - Math.Max(0, pan));
                r[start + i] += s * (1 + Math.Min(0, pan));
            }
        }

        static void AddExplosion(double[] l, double[] r, int sr, double t0, double gain, Random rnd) {
            var lp1 = new Biquad("lp", 140, 0.7, sr);
            var lp2 = new Biquad("lp", 140, 0.7, sr);
            var crack = new Biquad("bp", 900, 0.8, sr);
            int start = (int)(t0 * sr), len = (int)(1.6 * sr);
            for (int i = 0; i < len && start + i < l.Length; i++) {
                double t = (double)i / sr;
                double n = rnd.NextDouble() * 2 - 1;
                double rumble = lp2.Run(lp1.Run(n)) * 9.0 * Math.Exp(-t / 0.55) * Math.Min(1, t / 0.004);
                double c = crack.Run(n) * 1.2 * Math.Exp(-t / 0.06);
                double s = (rumble + c) * gain;
                l[start + i] += s; r[start + i] += s;
            }
        }

        // PCM estéreo 16 bit intercalado.
        public static short[] Render(int sr) {
            var rnd = new Random(1234);
            int n = (int)(5.2 * sr);
            double[] l = new double[n], r = new double[n];
            double far = Math.Pow(10, -14.0 / 20);
            for (int k = 0; k < 4; k++) AddStep(l, r, sr, 0.3 + k * 0.42, far, -0.7, rnd);   // pan < 0: izquierda
            AddExplosion(l, r, sr, 2.1, 0.9, rnd);
            AddStep(l, r, sr, 2.75, far, -0.7, rnd);
            AddStep(l, r, sr, 3.17, far, -0.7, rnd);
            double peak = 1e-9;
            for (int i = 0; i < n; i++) peak = Math.Max(peak, Math.Max(Math.Abs(l[i]), Math.Abs(r[i])));
            double g = 0.5 / peak;   // pico a -6 dBFS: deja margen al EQ
            var pcm = new short[n * 2];
            for (int i = 0; i < n; i++) {
                pcm[2 * i] = (short)(l[i] * g * 32767);
                pcm[2 * i + 1] = (short)(r[i] * g * 32767);
            }
            return pcm;
        }

        public static void SaveWav(string path, short[] pcm, int sr) {
            using (var w = new BinaryWriter(File.Create(path))) {
                int bytes = pcm.Length * 2;
                w.Write(new char[] { 'R', 'I', 'F', 'F' }); w.Write(36 + bytes);
                w.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); w.Write(16);
                w.Write((short)1); w.Write((short)2); w.Write(sr); w.Write(sr * 4); w.Write((short)4); w.Write((short)16);
                w.Write(new char[] { 'd', 'a', 't', 'a' }); w.Write(bytes);
                foreach (var s in pcm) w.Write(s);
            }
        }

        // ---------------- Reproducción (winmm waveOut) ----------------
        [StructLayout(LayoutKind.Sequential)]
        struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }
        [StructLayout(LayoutKind.Sequential)]
        struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct WAVEOUTCAPSW { public ushort wMid, wPid; public uint vDriverVersion; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname; public uint dwFormats; public ushort wChannels, wReserved1; public uint dwSupport; }

        [DllImport("winmm.dll")] static extern uint waveOutGetNumDevs();
        [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int waveOutGetDevCapsW(IntPtr id, ref WAVEOUTCAPSW caps, uint size);
        [DllImport("winmm.dll")] static extern int waveOutOpen(out IntPtr hwo, IntPtr id, ref WAVEFORMATEX fmt, IntPtr cb, IntPtr inst, uint flags);
        [DllImport("winmm.dll")] static extern int waveOutPrepareHeader(IntPtr hwo, IntPtr hdr, uint size);
        [DllImport("winmm.dll")] static extern int waveOutUnprepareHeader(IntPtr hwo, IntPtr hdr, uint size);
        [DllImport("winmm.dll")] static extern int waveOutWrite(IntPtr hwo, IntPtr hdr, uint size);
        [DllImport("winmm.dll")] static extern int waveOutClose(IntPtr hwo);

        // Nombres de dispositivo (waveOut los recorta a 31 caracteres).
        public static string[] Devices() {
            uint n = waveOutGetNumDevs();
            var list = new string[n];
            for (uint i = 0; i < n; i++) {
                var caps = new WAVEOUTCAPSW();
                waveOutGetDevCapsW(new IntPtr(i), ref caps, (uint)Marshal.SizeOf(typeof(WAVEOUTCAPSW)));
                list[i] = caps.szPname;
            }
            return list;
        }

        // device = -1: dispositivo por defecto (WAVE_MAPPER).
        public static void Play(short[] pcm, int sr, int device) {
            var fmt = new WAVEFORMATEX { wFormatTag = 1, nChannels = 2, nSamplesPerSec = (uint)sr, wBitsPerSample = 16, nBlockAlign = 4, nAvgBytesPerSec = (uint)(sr * 4), cbSize = 0 };
            IntPtr hwo;
            int rc = waveOutOpen(out hwo, new IntPtr(device), ref fmt, IntPtr.Zero, IntPtr.Zero, 0);
            if (rc != 0) throw new Exception("waveOutOpen falló (" + rc + ")");
            var data = GCHandle.Alloc(pcm, GCHandleType.Pinned);
            int hsize = Marshal.SizeOf(typeof(WAVEHDR));
            IntPtr hdr = Marshal.AllocHGlobal(hsize);
            try {
                var h = new WAVEHDR { lpData = data.AddrOfPinnedObject(), dwBufferLength = (uint)(pcm.Length * 2) };
                Marshal.StructureToPtr(h, hdr, false);
                waveOutPrepareHeader(hwo, hdr, (uint)hsize);
                waveOutWrite(hwo, hdr, (uint)hsize);
                // WHDR_DONE = 1
                var deadline = DateTime.Now.AddSeconds(pcm.Length / 2.0 / sr + 5);
                while (((WAVEHDR)Marshal.PtrToStructure(hdr, typeof(WAVEHDR))).dwFlags % 2 == 0 && DateTime.Now < deadline) Thread.Sleep(50);
                waveOutUnprepareHeader(hwo, hdr, (uint)hsize);
            } finally {
                waveOutClose(hwo);
                Marshal.FreeHGlobal(hdr);
                data.Free();
            }
        }
    }
}
'@
}

$sr = 48000
$pcm = [Hardline.FootstepTest]::Render($sr)
if ($SaveWav) { [Hardline.FootstepTest]::SaveWav($SaveWav, $pcm, $sr); Write-Host "WAV guardado: $SaveWav"; return }

# --- Dispositivo ----------------------------------------------------------------
$devices = @([Hardline.FootstepTest]::Devices())
if (-not $Device) {
    $vmRunning = [bool](Get-Process -Name 'voicemeeter*' -ErrorAction SilentlyContinue)
    if ($vmRunning -and ($devices | Where-Object { $_ -like 'CABLE Input*' })) { $Device = 'CABLE Input' }
}
$index = -1
if ($Device) {
    for ($i = 0; $i -lt $devices.Count; $i++) { if ($devices[$i] -like "*$Device*") { $index = $i; break } }
    if ($index -lt 0) { Write-Host "[!] No hay dispositivo que contenga '$Device'. Disponibles: $($devices -join ' | ')" -ForegroundColor Yellow; return }
}
$label = if ($index -ge 0) { $devices[$index] } else { 'dispositivo por defecto' }
Write-Host "[*] Test de pasos por: $label" -ForegroundColor Cyan

# --- A/B ------------------------------------------------------------------------
$switch = Get-HLEqSwitchPath
$original = Get-HLEqState -SwitchPath $switch
if ($Once -or $null -eq $original) {
    if ($null -eq $original) { Write-Host '[!] Sin interruptor de EQ: se reproduce una vez, tal cual.' -ForegroundColor Yellow }
    [Hardline.FootstepTest]::Play($pcm, $sr, $index)
    return
}
try {
    Write-Host '    1/2  EQ APAGADO   (fíjate en los pasos de la izquierda antes y después de la explosión)'
    Set-HLEqState -On $false -SwitchPath $switch
    Start-Sleep -Milliseconds 400   # Equalizer APO recarga la config al detectar el cambio
    [Hardline.FootstepTest]::Play($pcm, $sr, $index)
    Start-Sleep -Milliseconds 600
    Write-Host '    2/2  EQ ENCENDIDO'
    Set-HLEqState -On $true -SwitchPath $switch
    Start-Sleep -Milliseconds 400
    [Hardline.FootstepTest]::Play($pcm, $sr, $index)
} finally {
    Set-HLEqState -On $original -SwitchPath $switch
}
Write-Host '[+] Si en la 2/2 los pasos no destacan claramente: sube la intensidad o revisa que Equalizer APO esté instalado en ese dispositivo.' -ForegroundColor Green
