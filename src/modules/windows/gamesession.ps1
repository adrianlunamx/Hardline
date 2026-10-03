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
    return (Read-HLYesNo '¿Activar el modo partida?' $false)
}

<#
    Endurece gamesession_watcher.ps1: la tarea Hardline-GameSession lo ejecuta
    con -RunLevel Highest al iniciar sesión, pero el script vive en
    %LOCALAPPDATA%\Hardline, escribible por el usuario sin elevar. Sin esto,
    cualquier proceso como usuario estándar podría modificarlo y obtener
    ejecución silenciosa como administrador (bypass de UAC).

    Se quita la herencia y se deja: SYSTEM y Administradores con control
    total, BUILTIN\Users con solo lectura+ejecución. La ACL previa queda en
    el manifiesto (tipo FileAcl) para que el rollback la restaure.
    El watcher no carga ningún otro .ps1 con dot-sourcing (verificado):
    basta con proteger este archivo.
#>
function Protect-HLGameSessionWatcher {
    param([Parameter(Mandatory)] [string] $Path)
    if ($HL.DryRun) { return }
    $acl = Get-Acl -LiteralPath $Path
    $usersSid = 'S-1-5-32-545'  # BUILTIN\Users
    $writeMask = [Security.AccessControl.FileSystemRights]'Write, Modify, FullControl, Delete, ChangePermissions, TakeOwnership'
    $userCanWrite = $false
    foreach ($r in $acl.Access) {
        try { $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $sid = '' }
        if ($sid -eq $usersSid -and $r.AccessControlType -eq 'Allow' -and ($r.FileSystemRights -band $writeMask)) {
            $userCanWrite = $true; break
        }
    }
    if (-not $userCanWrite -and $acl.AreAccessRulesProtected) {
        Write-HLLog DEBUG "Watcher ya endurecido: $Path"
        return
    }
    $prevSddl = $acl.Sddl
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')), 'FullControl', 'Allow')))
    $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')), 'FullControl', 'Allow')))
    $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        (New-Object Security.Principal.SecurityIdentifier($usersSid)), 'ReadAndExecute', 'Allow')))
    Set-Acl -LiteralPath $Path -AclObject $acl
    Add-HLManifestEntry -Type 'FileAcl' -Data @{
        Path = $Path; PrevSddl = $prevSddl
        Reason = 'Solo-lectura para no-admins: el watcher corre elevado al iniciar sesión'
    }
    Write-HLLog INFO "Watcher endurecido (solo-lectura no-admins): $Path"
}

function Install-HLGameSession {
    param($Hardware)

    $watcher = Join-Path $HL.Root 'src\modules\windows\gamesession_watcher.ps1'
    if (-not (Test-Path $watcher)) { throw "No se encuentra $watcher" }

    # Se endurece en cada instalación/actualización aunque la tarea ya exista.
    Protect-HLGameSessionWatcher -Path $watcher

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
