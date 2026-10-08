#Requires -Version 5.1
<#
    Hardline - modo partida (proceso residente).

    Lo lanza la tarea programada "Hardline-GameSession" al iniciar sesión, con
    privilegios elevados (hacen falta para detener servicios). Cada pocos
    segundos comprueba si Warzone está abierto:

      Al abrirse:  detiene los servicios de la lista que estaban en marcha,
                   baja la prioridad de los procesos de fondo, cierra los de
                   close_processes y activa el plan de energía de Hardline.
      Al cerrarse: deshace todo lo anterior.

    Desde la 1.12.0 corre desde una carpeta protegida (Archivos de programa\
    Hardline\gamesession) donde están también su configuración, su estado y
    su log: un proceso elevado no debe leer ni escribir nada que el usuario
    pueda cambiar sin UAC. Las sesiones de versiones anteriores le pasan la
    carpeta de instalación y se respeta su estructura (config\, logs\) para
    que el rollback restaure lo que dejaron pendiente.

    El estado de la sesión se guarda en gamesession.state.json. Si el
    proceso muere a mitad de partida (o el PC se apaga), al volver a arrancar
    restaura lo pendiente antes de hacer nada más.

    No toca el proceso del juego: ni prioridad ni afinidad.

    Uso manual (como administrador):
      gamesession_watcher.ps1 -Root <carpeta del modo partida>           (bucle)
      gamesession_watcher.ps1 -Root <carpeta del modo partida> -RestoreOnly
#>
param(
    [Parameter(Mandatory)] [string] $Root,
    [switch] $RestoreOnly
)

$ErrorActionPreference = 'Continue'
if (Test-Path (Join-Path $Root 'config') -PathType Container) {
    # Carpeta de instalación (versiones anteriores a la 1.12.0).
    $configPath = Join-Path $Root 'config\gamesession.json'
    $defaultPath = Join-Path $Root 'src\modules\windows\configs\gamesession.default.json'
    $statePath = Join-Path $Root 'config\gamesession.state.json'
    $logPath = Join-Path $Root 'logs\gamesession.log'
} else {
    $configPath = Join-Path $Root 'gamesession.json'
    $defaultPath = Join-Path $Root 'gamesession.default.json'
    $statePath = Join-Path $Root 'gamesession.state.json'
    $logPath = Join-Path $Root 'gamesession.log'
}
$planName = 'Hardline Ultimate Performance'
$guidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Write-GSLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        # Log acotado: si pasa de 1 MB se rota.
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) { Move-Item $logPath "$logPath.old" -Force }
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch { }
}

function Get-GSConfig {
    $path = if (Test-Path $configPath) { $configPath } else { $defaultPath }
    $c = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $c.poll_seconds -or $c.poll_seconds -lt 2) { $c.poll_seconds = 5 }
    return $c
}

function Get-GSActiveScheme {
    $out = (& powercfg.exe /getactivescheme) -join ' '
    if ($out -match $guidRx) { return $Matches[0] }
    return $null
}

function Find-GSScheme {
    foreach ($line in (& powercfg.exe /list)) {
        if ($line -match "($guidRx)\s+\((.+?)\)" -and $Matches[2] -eq $planName) { return $Matches[1] }
    }
    return $null
}

# Get-Process -Name @() falla al validar el parámetro: lista vacía = ningún proceso.
function Get-GSProcesses {
    param($Names)
    $list = @($Names | Where-Object { $_ })
    if ($list.Count -eq 0) { return @() }
    return @(Get-Process -Name $list -ErrorAction SilentlyContinue)
}

function Save-GSState { param($State) $State | ConvertTo-Json -Depth 5 | Set-Content -Path $statePath -Encoding UTF8 }

# Baja la prioridad de los procesos de la lista que aún no se hayan tocado.
function Set-GSLowPriority {
    param($Config, $State)
    $changed = $false
    foreach ($p in (Get-GSProcesses $Config.lower_priority)) {
        $key = "$($p.Id)"
        if (@($State.Priorities | Where-Object { $_.Id -eq $key }).Count -gt 0) { continue }
        try {
            $orig = "$($p.PriorityClass)"
            if ($orig -in @('Normal', 'AboveNormal', 'High')) {
                $p.PriorityClass = 'BelowNormal'
                $State.Priorities += [pscustomobject]@{ Id = $key; Name = $p.ProcessName; Start = $p.StartTime.ToString('o'); Original = $orig }
                $changed = $true
            }
        } catch { }   # procesos protegidos o de otro usuario
    }
    return $changed
}

function Enter-GSSession {
    param($Config, [string]$GameName)
    $state = [pscustomobject]@{
        Started    = (Get-Date).ToString('o')
        Game       = $GameName
        Services   = @()
        Priorities = @()
        PrevScheme = $null
    }

    foreach ($name in @($Config.pause_services)) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            try { Stop-Service -Name $name -Force -ErrorAction Stop; $state.Services += $name } catch { Write-GSLog "  servicio $name no se pudo detener: $($_.Exception.Message)" }
        }
    }

    [void](Set-GSLowPriority -Config $Config -State $state)

    foreach ($p in (Get-GSProcesses $Config.close_processes)) {
        try { $p.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 500; if (-not $p.HasExited) { $p.Kill() } } catch { }
    }

    if ($Config.power_plan) {
        $plan = Find-GSScheme
        $cur = Get-GSActiveScheme
        if ($plan -and $cur -and $plan -ne $cur) {
            & powercfg.exe /setactive $plan | Out-Null
            $state.PrevScheme = $cur
        }
    }

    Save-GSState $state
    Write-GSLog ("INICIO {0}: servicios detenidos [{1}], prioridad baja en {2} procesos, plan {3}" -f $GameName,
        ($state.Services -join ', '), @($state.Priorities).Count, $(if ($state.PrevScheme) { 'Hardline' } else { 'sin cambios' }))
    return $state
}

function Exit-GSSession {
    param($State)
    if (-not $State) { return }

    foreach ($name in @($State.Services)) {
        try { Start-Service -Name $name -ErrorAction Stop } catch { Write-GSLog "  servicio $name no se pudo arrancar: $($_.Exception.Message)" }
    }
    $restored = 0
    foreach ($e in @($State.Priorities)) {
        $p = Get-Process -Id ([int]$e.Id) -ErrorAction SilentlyContinue
        # Mismo PID y misma hora de inicio: es el mismo proceso, no uno nuevo que reutilizó el PID.
        if ($p -and $p.StartTime.ToString('o') -eq $e.Start) {
            try { $p.PriorityClass = $e.Original; $restored++ } catch { }
        }
    }
    if ($State.PrevScheme) { & powercfg.exe /setactive $State.PrevScheme | Out-Null }
    Remove-Item $statePath -Force -ErrorAction SilentlyContinue
    Write-GSLog ("FIN: servicios reanudados [{0}], prioridad restaurada en {1} procesos{2}" -f ($State.Services -join ', '), $restored,
        $(if ($State.PrevScheme) { ", plan $($State.PrevScheme)" } else { '' }))
}

function Get-GSRunningGame {
    param($Config)
    $p = Get-GSProcesses $Config.process | Select-Object -First 1
    if ($p) { return $p.ProcessName }
    return $null
}

# --- Recuperación de una sesión interrumpida ---------------------------------
$config = Get-GSConfig
$session = $null
if (Test-Path $statePath) {
    $pending = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($RestoreOnly -or -not (Get-GSRunningGame -Config $config)) {
        Write-GSLog 'Sesión anterior interrumpida: restaurando.'
        Exit-GSSession -State $pending
    } else {
        $session = $pending
        if (-not $session.Priorities) { $session.Priorities = @() }
    }
}
if ($RestoreOnly) { return }

# Una sola instancia por usuario.
$mutex = New-Object System.Threading.Mutex($false, 'Local\HardlineGameSession')
if (-not $mutex.WaitOne(0)) { return }

Write-GSLog "Watcher iniciado (juego: $(@($config.process) -join ', '), cada $($config.poll_seconds) s)"
try {
    while ($true) {
        $game = Get-GSRunningGame -Config $config
        if ($game -and -not $session) {
            $config = Get-GSConfig   # recarga por si el usuario editó la config
            $session = Enter-GSSession -Config $config -GameName $game
        } elseif ($game -and $session) {
            # Procesos de fondo abiertos durante la partida (un navegador, por ejemplo).
            if (Set-GSLowPriority -Config $config -State $session) { Save-GSState $session }
        } elseif (-not $game -and $session) {
            Exit-GSSession -State $session
            $session = $null
        }
        Start-Sleep -Seconds $config.poll_seconds
    }
} finally {
    if ($session) { Exit-GSSession -State $session }
    $mutex.ReleaseMutex()
}
