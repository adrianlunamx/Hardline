#Requires -Version 5.1
<#
    Hardline - test de mando.

    Dos medidas, ~15 s en total, sin cambiar nada del sistema:

      1. Reposo (5 s, sin tocar el mando): cuánto se desvían los sticks del
         centro por sí solos (drift). De ahí sale la zona muerta mínima segura
         para Warzone: por debajo, la mira se mueve sola; por encima, pierdes
         precisión en movimientos finos sin necesidad.
      2. Movimiento (5 s, girando los dos sticks): cada cuánto llega un estado
         nuevo del mando al PC. Es la tasa de actualización real (Hz) y su
         regularidad. Sirve para comparar cable, adaptador y Bluetooth en tu
         propio equipo: mejor más Hz y menos variación entre intervalos.

    Lectura: XInput (mandos Xbox y compatibles, sin depender del foco de la
    ventana). Si no hay ninguno, Windows.Gaming.Input (DualSense, DualShock y
    otros; solo en Windows PowerShell 5.1 y con esta ventana en primer plano).

    Uso:  controller_test.ps1 [-Seconds 5]
#>
param([ValidateRange(2, 30)] [int] $Seconds = 5)

# --------------------------------------------------------------------------
# Cálculo (sin hardware: se prueba en tests\validate.ps1)
# --------------------------------------------------------------------------

# Eje XInput (-32768..32767) a -1..1.
function ConvertFrom-HLXInputAxis {
    param([int]$Value)
    return [Math]::Max(-1.0, [Math]::Min(1.0, $Value / 32767.0))
}

# Eje de Windows.Gaming.Input (0..1, centro 0.5) a -1..1.
function ConvertFrom-HLRawAxis {
    param([double]$Value)
    return [Math]::Max(-1.0, [Math]::Min(1.0, ($Value - 0.5) * 2.0))
}

<#
    Desviación de un stick en reposo. X e Y ya normalizados a -1..1.
    MaxRadius: el peor punto (es lo que decide la zona muerta).
    Offset: distancia media al centro (descentrado constante).
#>
function Measure-HLStickRest {
    param([Parameter(Mandatory)] [double[]] $X, [Parameter(Mandatory)] [double[]] $Y)
    $n = [Math]::Min($X.Count, $Y.Count)
    if ($n -eq 0) { return [pscustomobject]@{ Samples = 0; MaxRadius = 0.0; Offset = 0.0 } }
    $max = 0.0; $sx = 0.0; $sy = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $r = [Math]::Sqrt($X[$i] * $X[$i] + $Y[$i] * $Y[$i])
        if ($r -gt $max) { $max = $r }
        $sx += $X[$i]; $sy += $Y[$i]
    }
    $off = [Math]::Sqrt(($sx / $n) * ($sx / $n) + ($sy / $n) * ($sy / $n))
    return [pscustomobject]@{ Samples = $n; MaxRadius = [Math]::Round($max, 4); Offset = [Math]::Round($off, 4) }
}

<#
    Zona muerta mínima en % (escala 0-100 del menú de Warzone): el peor drift
    medido más 2 puntos de margen (temperatura, desgaste). Worn = el stick
    tiene más drift del que una zona muerta razonable debería tapar.
#>
function Get-HLRecommendedDeadzone {
    param([Parameter(Mandatory)] [double] $MaxRadius)
    $pct = [int][Math]::Ceiling([Math]::Round($MaxRadius * 100, 2)) + 2
    $pct = [Math]::Min(30, [Math]::Max(2, $pct))
    return [pscustomobject]@{ Percent = $pct; Worn = ($MaxRadius -gt 0.15) }
}

<#
    Estadística de los instantes (ms) en que llegó un estado nuevo.
    Hz sale de la mediana del intervalo: no la falsea un hueco aislado.
#>
function Get-HLRateStats {
    param([double[]] $TimestampsMs)
    $t = @($TimestampsMs)
    if ($t.Count -lt 3) { return [pscustomobject]@{ Updates = $t.Count; Hz = 0; MedianMs = 0.0; P95Ms = 0.0; MaxMs = 0.0 } }
    $iv = for ($i = 1; $i -lt $t.Count; $i++) { $t[$i] - $t[$i - 1] }
    $s = @($iv | Sort-Object)
    $med = $s[[int][Math]::Floor(($s.Count - 1) / 2)]
    $p95 = $s[[int][Math]::Ceiling(($s.Count - 1) * 0.95)]
    $hz = if ($med -gt 0) { [int][Math]::Round(1000.0 / $med) } else { 0 }
    return [pscustomobject]@{ Updates = $t.Count; Hz = $hz; MedianMs = [Math]::Round($med, 2); P95Ms = [Math]::Round($p95, 2); MaxMs = [Math]::Round($s[-1], 2) }
}

# Lectura de la tasa para el usuario.
function Get-HLRateVerdict {
    param([Parameter(Mandatory)] $Stats)
    if ($Stats.Hz -le 0) { return 'Sin datos: no llegaron estados nuevos. ¿Moviste los sticks todo el rato?' }
    $jitter = if ($Stats.MedianMs -gt 0) { $Stats.P95Ms / $Stats.MedianMs } else { 0 }
    $base = if ($Stats.Hz -ge 500) { 'Muy alta' } elseif ($Stats.Hz -ge 200) { 'Buena' } elseif ($Stats.Hz -ge 110) { 'Normal (típica de 125 Hz)' } else { 'Baja: revisa conexión (Bluetooth lejos del receptor, hub USB, capa de remapeo)' }
    if ($jitter -gt 2.5) { $base += '; intervalos irregulares (típico de Bluetooth o de un puerto/hub compartido)' }
    return $base
}

# --------------------------------------------------------------------------
# Lectura del mando
# --------------------------------------------------------------------------

function Initialize-HLXInput {
    if ('Hardline.XInputTest' -as [type]) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Hardline {
    public static class XInputTest {
        [StructLayout(LayoutKind.Sequential)]
        public struct State {
            public uint Packet;
            public ushort Buttons;
            public byte LeftTrigger, RightTrigger;
            public short LX, LY, RX, RY;
        }

        [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")] static extern int Get14(int user, out State s);
        [DllImport("xinput9_1_0.dll", EntryPoint = "XInputGetState")] static extern int Get910(int user, out State s);
        static bool legacy;

        public static int GetState(int user, out State s) {
            if (!legacy) {
                try { return Get14(user, out s); }
                catch (DllNotFoundException) { legacy = true; }
                catch (EntryPointNotFoundException) { legacy = true; }
            }
            return Get910(user, out s);
        }

        public static bool IsConnected(int user) { State s; return GetState(user, out s) == 0; }

        // Muestras de los sticks cada ~1 ms: LX, LY, RX, RY seguidos.
        public static short[] SampleSticks(int user, int ms) {
            var list = new List<short>();
            var sw = Stopwatch.StartNew();
            State s;
            while (sw.ElapsedMilliseconds < ms) {
                if (GetState(user, out s) != 0) break;
                list.Add(s.LX); list.Add(s.LY); list.Add(s.RX); list.Add(s.RY);
                Thread.Sleep(1);
            }
            return list.ToArray();
        }

        // Instantes (ms) en que cambia dwPacketNumber, sondeando sin pausa.
        public static double[] PacketTimes(int user, int ms) {
            var list = new List<double>();
            var sw = Stopwatch.StartNew();
            State s;
            if (GetState(user, out s) != 0) return list.ToArray();
            uint last = s.Packet;
            while (sw.ElapsedMilliseconds < ms) {
                if (GetState(user, out s) != 0) break;
                if (s.Packet != last) { last = s.Packet; list.Add(sw.Elapsed.TotalMilliseconds); }
            }
            return list.ToArray();
        }
    }
}
'@
}

function Get-HLXInputSlots {
    try { Initialize-HLXInput } catch { return @() }
    $slots = foreach ($i in 0..3) { try { if ([Hardline.XInputTest]::IsConnected($i)) { $i } } catch { } }
    return @($slots)
}

function Get-HLRawControllers {
    if ($PSVersionTable.PSEdition -eq 'Core') { return @() }
    try {
        $null = [Windows.Gaming.Input.RawGameController, Windows.Gaming.Input, ContentType = WindowsRuntime]
        # La lista se rellena de forma asíncrona tras el primer acceso.
        $sw = [Diagnostics.Stopwatch]::StartNew()
        do {
            $list = @([Windows.Gaming.Input.RawGameController]::RawGameControllers)
            if ($list.Count -gt 0) { break }
            Start-Sleep -Milliseconds 100
        } while ($sw.ElapsedMilliseconds -lt 2000)
        return $list
    } catch { return @() }
}

# Devuelve un scriptblock que lee el mando: @(marca de tiempo en µs, eje0, eje1, ...), ejes en 0..1.
function New-HLRawReader {
    param([Parameter(Mandatory)] $Controller)
    $btn = New-Object bool[] $Controller.ButtonCount
    $sws = New-Object 'Windows.Gaming.Input.GameControllerSwitchPosition[]' $Controller.SwitchCount
    $ax = New-Object double[] $Controller.AxisCount
    return {
        $ts = $Controller.GetCurrentReading($btn, $sws, $ax)
        return , ([double[]](@([double]$ts) + @($ax)))
    }.GetNewClosure()
}

function Write-HLStickResult {
    param([string]$Label, $Rest)
    $dz = Get-HLRecommendedDeadzone -MaxRadius $Rest.MaxRadius
    Write-Host ('    {0,-16} drift máx. {1,5:N1} %   descentrado {2,5:N1} %   ->  zona muerta mínima: {3}' -f $Label, ($Rest.MaxRadius * 100), ($Rest.Offset * 100), $dz.Percent) -ForegroundColor Gray
    if ($dz.Worn) { Write-Host "      Drift alto en $Label. Limpia/recalibra el stick o cambia el módulo: una zona muerta tan grande se nota al apuntar." -ForegroundColor Yellow }
    return $dz
}

function Write-HLCountdown {
    param([string]$Text, [int]$From = 3)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    for ($i = $From; $i -ge 1; $i--) { Write-Host "    $i..." -ForegroundColor DarkGray; Start-Sleep -Seconds 1 }
}

function Invoke-HLControllerTest {
    param([int]$Seconds = 5)
    Write-Host ''
    Write-Host 'HARDLINE - test de mando' -ForegroundColor Cyan
    $ms = $Seconds * 1000

    $slots = @(Get-HLXInputSlots)
    $leftRest = $null; $rightRest = $null; $times = @(); $source = ''

    if ($slots.Count -gt 0) {
        $u = $slots[0]
        $source = "XInput (ranura $($u + 1))"
        if ($slots.Count -gt 1) { Write-Host "Hay $($slots.Count) mandos XInput; se mide el de la ranura $($u + 1). Desconecta los demás para medir otro." -ForegroundColor Yellow }
        Write-Host "Mando: $source"

        Write-HLCountdown "1/2  Suelta el mando sobre la mesa y no lo toques durante $Seconds s."
        Write-Host '    Midiendo reposo...' -ForegroundColor DarkGray
        $raw = [Hardline.XInputTest]::SampleSticks($u, $ms)
        $n = [int]($raw.Count / 4)
        $lx = New-Object double[] $n; $ly = New-Object double[] $n; $rx = New-Object double[] $n; $ry = New-Object double[] $n
        for ($i = 0; $i -lt $n; $i++) {
            $lx[$i] = ConvertFrom-HLXInputAxis $raw[4 * $i]; $ly[$i] = ConvertFrom-HLXInputAxis $raw[4 * $i + 1]
            $rx[$i] = ConvertFrom-HLXInputAxis $raw[4 * $i + 2]; $ry[$i] = ConvertFrom-HLXInputAxis $raw[4 * $i + 3]
        }
        $leftRest = Measure-HLStickRest -X $lx -Y $ly
        $rightRest = Measure-HLStickRest -X $rx -Y $ry

        Write-HLCountdown "2/2  Ahora gira los DOS sticks en círculos, sin parar, durante $Seconds s."
        Write-Host '    Midiendo tasa de actualización...' -ForegroundColor DarkGray
        $times = [Hardline.XInputTest]::PacketTimes($u, $ms)
    } else {
        $pads = @(Get-HLRawControllers)
        if ($pads.Count -eq 0) {
            Write-Host ''
            Write-Host 'No se detecta ningún mando.' -ForegroundColor Yellow
            if ($PSVersionTable.PSEdition -eq 'Core') { Write-Host 'Los mandos PlayStation se leen con Windows.Gaming.Input, que solo existe en Windows PowerShell 5.1 (powershell.exe).' -ForegroundColor Yellow }
            Write-Host 'Conéctalo por cable, comprueba que aparece en "Configurar controladores USB para juegos" (joy.cpl) y repite.'
            return $null
        }
        $pad = $pads[0]
        $source = "Windows.Gaming.Input ($($pad.DisplayName), $($pad.AxisCount) ejes)"
        Write-Host "Mando: $source"
        Write-Host 'Windows solo entrega la entrada de estos mandos a la ventana en primer plano: deja esta ventana delante durante el test.' -ForegroundColor DarkGray
        $read = New-HLRawReader -Controller $pad

        Write-HLCountdown "1/2  Suelta el mando sobre la mesa y no lo toques durante $Seconds s."
        Write-Host '    Midiendo reposo...' -ForegroundColor DarkGray
        $rows = New-Object System.Collections.Generic.List[object]
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $ms) { $rows.Add((& $read)); Start-Sleep -Milliseconds 2 }
        # Ejes de stick: los que reposan cerca del centro (los gatillos reposan en un extremo), en pares.
        $axCount = $pad.AxisCount
        $stickAxes = @(for ($a = 0; $a -lt $axCount; $a++) { if ([Math]::Abs($rows[0][$a + 1] - 0.5) -lt 0.25) { $a } })
        $col = { param($a) [double[]]@(foreach ($r in $rows) { ConvertFrom-HLRawAxis $r[$a + 1] }) }
        if ($stickAxes.Count -ge 2) { $leftRest = Measure-HLStickRest -X (& $col $stickAxes[0]) -Y (& $col $stickAxes[1]) }
        if ($stickAxes.Count -ge 4) { $rightRest = Measure-HLStickRest -X (& $col $stickAxes[2]) -Y (& $col $stickAxes[3]) }

        Write-HLCountdown "2/2  Ahora gira los DOS sticks en círculos, sin parar, durante $Seconds s."
        Write-Host '    Midiendo tasa de actualización...' -ForegroundColor DarkGray
        # La marca de tiempo de cada lectura viene del propio dispositivo (µs).
        $tl = New-Object System.Collections.Generic.List[double]
        $last = [double]-1
        $sw.Restart()
        while ($sw.ElapsedMilliseconds -lt $ms) {
            $ts = (& $read)[0]
            if ($ts -ne $last) { if ($last -ge 0) { $tl.Add($ts / 1000.0) }; $last = $ts }
        }
        $times = $tl.ToArray()
    }

    $rate = Get-HLRateStats -TimestampsMs $times
    Write-Host ''
    Write-Host "Resultado ($source)" -ForegroundColor Cyan
    $dzL = $null; $dzR = $null
    if ($leftRest) { $dzL = Write-HLStickResult 'Stick izquierdo' $leftRest }
    if ($rightRest) { $dzR = Write-HLStickResult 'Stick derecho' $rightRest }
    if (-not $leftRest -and -not $rightRest) { Write-Host '    No se pudieron identificar los ejes de los sticks.' -ForegroundColor Yellow }
    Write-Host ('    {0,-16} {1} Hz  (intervalo mediano {2} ms, p95 {3} ms, máx. {4} ms, {5} estados)' -f 'Actualización', $rate.Hz, $rate.MedianMs, $rate.P95Ms, $rate.MaxMs, $rate.Updates) -ForegroundColor Gray
    Write-Host "      $(Get-HLRateVerdict -Stats $rate)" -ForegroundColor Gray
    Write-Host ''
    Write-Host 'En Warzone > Mando > Sticks:' -ForegroundColor Cyan
    if ($dzL) { Write-Host "    Zona muerta mínima stick izquierdo: $($dzL.Percent)" }
    if ($dzR) { Write-Host "    Zona muerta mínima stick derecho:   $($dzR.Percent)" }
    Write-Host '    Si la mira se mueve sola en el campo de tiro, sube 1 punto el stick afectado.'
    Write-Host '    Repite el test por cable y por inalámbrico para comparar la tasa en tu equipo.' -ForegroundColor DarkGray

    return [pscustomobject]@{ Source = $source; Left = $leftRest; Right = $rightRest; LeftDeadzone = $dzL; RightDeadzone = $dzR; Rate = $rate }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-HLControllerTest -Seconds $Seconds | Out-Null
}
