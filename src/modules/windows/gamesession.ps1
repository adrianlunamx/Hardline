#Requires -Version 5.1
<#
    Hardline - modo partida (instalación).

    En lugar de dejar cambios permanentes en segundo plano, una tarea al
    iniciar sesión vigila si Warzone está abierto y solo entonces pausa
    servicios, baja la prioridad de procesos de fondo y activa el plan de
    energía máximo. Al cerrar el juego, todo vuelve a como estaba.

    Detalle del comportamiento: gamesession_watcher.ps1.
    Configuración editable: config\gamesession.json.
#>

$script:HLGameSessionTask = 'Hardline-GameSession'

function Get-HLGameSessionConfigPath {
    $dir = Join-Path $HL.Root 'config'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir 'gamesession.json'
    if (-not (Test-Path $path)) {
        Copy-Item (Join-Path $HL.Root 'src\modules\windows\configs\gamesession.default.json') $path
    }
    return $path
}

# Decide si se instala el modo partida. Devuelve $true/$false.
function Get-HLGameSessionChoice {
    param([ValidateSet('', 'Yes', 'No')] [string] $Choice = '')
    if ($Choice -eq 'Yes') { return $true }
    if ($Choice -eq 'No') { return $false }
    if (Get-ScheduledTask -TaskName $script:HLGameSessionTask -ErrorAction SilentlyContinue) { return $true }
    Write-HLInfo 'Modo partida: con Warzone abierto pausa servicios de fondo, baja la prioridad de navegadores/launchers y activa el plan de energía máximo. Al cerrar el juego, todo vuelve a su estado.'
    return (Read-HLYesNo '¿Activar el modo partida?' $true)
}

function Install-HLGameSession {
    param($Hardware)

    $watcher = Join-Path $HL.Root 'src\modules\windows\gamesession_watcher.ps1'
    if (-not (Test-Path $watcher)) { throw "No se encuentra $watcher" }

    if (Get-ScheduledTask -TaskName $script:HLGameSessionTask -ErrorAction SilentlyContinue) {
        Write-HLSub 'Modo partida' 'OK (ya instalado)'
        Add-HLResult -Module 'Modo partida' -Item 'Tarea' -Status Skipped -Detail 'Ya estaba instalado'
        return
    }
    if ($HL.DryRun) { Write-HLSub 'Modo partida' 'SKIP (DryRun)'; return }

    $cfg = Get-HLGameSessionConfigPath
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Root "{1}"' -f $watcher, $HL.Root
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
    # Highest: detener/arrancar servicios requiere privilegios de administrador.
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $script:HLGameSessionTask -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Description 'Hardline: modo partida (pausa servicios y procesos de fondo mientras Warzone está abierto).' -Force | Out-Null
    Add-HLManifestEntry -Type 'ScheduledTask' -Data @{ Name = $script:HLGameSessionTask; ProcessMatch = 'gamesession_watcher.ps1'; RestoreScript = $watcher; RestoreRoot = $HL.Root }
    Start-ScheduledTask -TaskName $script:HLGameSessionTask

    Write-HLSub 'Modo partida' 'OK'
    Add-HLResult -Module 'Modo partida' -Item 'Tarea' -Status Applied -Detail "Activo al iniciar sesión. Configuración: $cfg. Registro: logs\gamesession.log"
}
