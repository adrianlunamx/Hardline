#Requires -Version 5.1
<#
    Hardline - activa/desactiva el EQ de pasos.

    Lo lanza el atajo "Hardline EQ on-off" (Ctrl+Alt+F10) a través de
    eq_toggle.vbs, que lo ejecuta sin ventana para no sacar al juego de primer
    plano. Confirmación por sonido: un pitido agudo = EQ encendido, dos
    graves = apagado.

    Manual:  eq_toggle.ps1 [-State On|Off]
#>
param([string]$Root, [ValidateSet('', 'On', 'Off')] [string]$State = '')

. (Join-Path $PSScriptRoot 'eqswitch.ps1')

try {
    $current = Get-HLEqState
    if ($null -eq $current) { throw 'No hay interruptor de EQ.' }
    $target = switch ($State) { 'On' { $true } 'Off' { $false } default { -not $current } }
    Set-HLEqState -On $target
    if ($target) { [console]::Beep(1200, 120) } else { [console]::Beep(500, 100); Start-Sleep -Milliseconds 60; [console]::Beep(500, 100) }
    if ($Root) {
        $log = Join-Path $Root 'logs\eq_toggle.log'
        Add-Content -Path $log -Value ('{0} EQ {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($target) { 'ON' } else { 'OFF' })) -ErrorAction SilentlyContinue
    }
} catch {
    [console]::Beep(300, 400)
    if ($Root) { Add-Content -Path (Join-Path $Root 'logs\eq_toggle.log') -Value "ERROR $($_.Exception.Message)" -ErrorAction SilentlyContinue }
}
