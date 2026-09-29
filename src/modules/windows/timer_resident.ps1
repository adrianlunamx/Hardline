#Requires -Version 5.1
<#
    Hardline - proceso residente de resolución de timer.

    Lo lanza la tarea programada "Hardline-TimerResolution" al iniciar sesión.
    Pide al kernel una resolución de timer de 0.5 ms y se queda dormido. La
    petición dura lo que viva el proceso: si lo matas, Windows vuelve a la
    resolución por defecto (15.6 ms, o la que pida otra app).

    Consumo: ~30 MB de RAM (runtime de PowerShell), 0% CPU.

    Parámetro -Resolution en unidades de 100 ns: 5000 = 0.5 ms, 10000 = 1 ms.
#>
param([int]$Resolution = 5000)

Add-Type -Namespace Hardline -Name Ntdll -MemberDefinition @'
[DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);
[DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint Minimum, out uint Maximum, out uint Current);
'@

$min = 0; $max = 0; $cur = 0
[void][Hardline.Ntdll]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur)
# "Maximum" es la resolución más fina que soporta el hardware (normalmente 5000).
$target = [uint32][Math]::Max($Resolution, $max)

$actual = 0
$status = [Hardline.Ntdll]::NtSetTimerResolution($target, $true, [ref]$actual)
if ($status -ne 0) { exit 1 }

# Dormir indefinidamente sin consumir CPU.
[System.Threading.Thread]::Sleep([System.Threading.Timeout]::Infinite)
