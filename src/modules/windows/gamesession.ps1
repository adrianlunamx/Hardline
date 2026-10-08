#Requires -Version 5.1
<#
    Hardline - modo partida (instalación).

    En lugar de dejar cambios permanentes en segundo plano, una tarea al
    iniciar sesión vigila si Warzone está abierto y solo entonces pausa
    servicios, baja la prioridad de procesos de fondo y activa el plan de
    energía máximo. Al cerrar el juego, todo vuelve a como estaba.

    Detalle del comportamiento: gamesession_watcher.ps1.
    Configuración editable: config\gamesession.json (se copia a la carpeta
    protegida cada vez que aplicas).
#>

$script:HLGameSessionTask = 'Hardline-GameSession'

<#
    Carpeta desde la que corre el modo partida. La tarea se ejecuta elevada
    al iniciar sesión, así que el script, su configuración, su estado y su
    log viven donde solo escriben los administradores. Archivos de programa y
    no ProgramData: en ProgramData cualquier usuario puede crear carpetas y
    adelantarse a Hardline con una suya.

    Hasta la 1.11.0 el script corría desde %LOCALAPPDATA%\Hardline. Proteger
    solo el archivo no bastaba: con control total sobre la carpeta, el
    usuario podía borrarlo y poner otro con el mismo nombre, que Windows
    ejecutaba como administrador sin preguntar (bypass de UAC).
#>
function Get-HLGameSessionDir { return (Join-Path $env:ProgramFiles 'Hardline\gamesession') }

# Copia del usuario: la que se edita. Se crea a partir de la plantilla.
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
    return (Read-HLYesNo '¿Activar el modo partida?' $false)
}

# ¿Pueden los usuarios sin elevar escribir, borrar o cambiar permisos en $Path?
function Test-HLUsersCanWrite {
    param([Parameter(Mandatory)] [string] $Path)
    $writeMask = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
    # BUILTIN\Users, Authenticated Users, Everyone, INTERACTIVE.
    $broad = @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0', 'S-1-5-4')
    foreach ($r in (Get-Acl -LiteralPath $Path).Access) {
        try { $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
        if ($sid -in $broad -and $r.AccessControlType -eq 'Allow' -and ($r.FileSystemRights -band $writeMask)) { return $true }
    }
    return $false
}

<#
    Copia el watcher y su configuración a la carpeta protegida. La config es
    la del usuario (config\gamesession.json) si es un JSON válido con al
    menos un proceso; si no, la plantilla. Devuelve la carpeta.
#>
function Sync-HLGameSessionFiles {
    $dir = Get-HLGameSessionDir
    if (-not (Test-Path $dir)) {
        $top = Split-Path $dir -Parent
        $topCreated = -not (Test-Path $top)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        # Se deshace después de quitar la tarea (el manifiesto se recorre al revés).
        Add-HLManifestEntry -Type 'Directory' -Data @{ Path = $(if ($topCreated) { $top } else { $dir }); Reason = 'Carpeta protegida del modo partida' }
    }
    # Fail-closed: si la carpeta heredó permisos de escritura para usuarios, no se usa.
    if (Test-HLUsersCanWrite -Path $dir) { throw "Los usuarios pueden escribir en $dir; el modo partida no se instala ahí." }

    $src = Join-Path $HL.Root 'src\modules\windows'
    Copy-Item (Join-Path $src 'gamesession_watcher.ps1') (Join-Path $dir 'gamesession_watcher.ps1') -Force
    Copy-Item (Join-Path $src 'configs\gamesession.default.json') (Join-Path $dir 'gamesession.default.json') -Force

    $userCfg = Get-HLGameSessionConfigPath
    $cfgOk = $false
    try { $cfgOk = @((Get-Content $userCfg -Raw -Encoding UTF8 | ConvertFrom-Json).process | Where-Object { $_ }).Count -gt 0 } catch { Write-HLLog WARN "gamesession.json ilegible: $($_.Exception.Message)" }
    if ($cfgOk) {
        Copy-Item $userCfg (Join-Path $dir 'gamesession.json') -Force
    } else {
        Write-HLWarn "config\gamesession.json no es válido: el modo partida usa la configuración por defecto."
        Copy-Item (Join-Path $src 'configs\gamesession.default.json') (Join-Path $dir 'gamesession.json') -Force
    }
    return $dir
}

function Install-HLGameSession {
    param($Hardware)

    $dir = Get-HLGameSessionDir
    $watcher = Join-Path $dir 'gamesession_watcher.ps1'
    $task = Get-ScheduledTask -TaskName $script:HLGameSessionTask -ErrorAction SilentlyContinue
    $current = $task -and ("$($task.Actions[0].Arguments)" -like "*$dir*")

    if ($HL.DryRun) {
        Write-HLSub 'Modo partida' $(if ($current) { 'OK (ya instalado)' } elseif ($task) { 'SKIP (DryRun: se movería a la carpeta protegida)' } else { 'SKIP (DryRun)' })
        return
    }

    # Cada vez que se aplica: script nuevo y config del usuario, aunque la tarea ya exista.
    [void](Sync-HLGameSessionFiles)
    if ($current) {
        Write-HLSub 'Modo partida' 'OK (ya instalado, configuración actualizada)'
        Add-HLResult -Module 'Modo partida' -Item 'Tarea' -Status Skipped -Detail "Ya estaba instalado. Configuración copiada a $dir"
        return
    }

    if ($task) {
        # Versión anterior: la tarea apunta al script de %LOCALAPPDATA%. Se sustituye.
        Stop-ScheduledTask -TaskName $script:HLGameSessionTask -ErrorAction SilentlyContinue
        Write-HLLog INFO 'Modo partida: tarea anterior (carpeta del usuario) sustituida por la de la carpeta protegida'
    }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Root "{1}"' -f $watcher, $dir
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
    # Highest: detener/arrancar servicios requiere privilegios de administrador.
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $script:HLGameSessionTask -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Description 'Hardline: modo partida (pausa servicios y procesos de fondo mientras Warzone está abierto).' -Force | Out-Null
    Add-HLManifestEntry -Type 'ScheduledTask' -Data @{ Name = $script:HLGameSessionTask; ProcessMatch = 'gamesession_watcher.ps1'; RestoreScript = $watcher; RestoreRoot = $dir }
    Start-ScheduledTask -TaskName $script:HLGameSessionTask

    Write-HLSub 'Modo partida' $(if ($task) { 'OK (movido a la carpeta protegida)' } else { 'OK' })
    Add-HLResult -Module 'Modo partida' -Item 'Tarea' -Status Applied -Detail "Activo al iniciar sesión. Edita config\gamesession.json y vuelve a aplicar para cambiarlo. Registro: $dir\gamesession.log"
}
