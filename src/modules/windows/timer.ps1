#Requires -Version 5.1
<#
    Hardline - resolución de timer a 0.5 ms.

    Por qué: el scheduler de Windows despierta hilos en múltiplos del periodo
    del timer global. Casi todos los motores piden 1 ms mientras corren;
    0.5 ms reduce el jitter de Sleep()/waits cortos que usan el render thread
    y los limitadores de FPS por software.

    Cómo:
      1. GlobalTimerResolutionRequests = 1. Desde Windows 10 2004 las peticiones
         de timer son por proceso: lo que pide un proceso en segundo plano no
         afecta al juego. Windows 11 añadió esta clave para restaurar el
         comportamiento global. En Win10 2004+ la clave no existe, así que ahí
         Hardline NO instala la tarea (no tendría efecto) y lo dice.
      2. Tarea programada al iniciar sesión que lanza timer_resident.ps1.

    Verificación: el benchmark pre/post mide la resolución actual y el jitter
    real de Sleep(1). Si en tu sistema 0.5 ms no mejora el jitter frente a 1 ms,
    cámbialo con -Resolution 10000 en la tarea.

    Referencia: https://learn.microsoft.com/windows/win32/api/timeapi/nf-timeapi-timebeginperiod
#>

$script:HLTimerTask = 'Hardline-TimerResolution'

function Install-HLTimerResolution {
    param($Hardware)

    $build = if ($Hardware) { $Hardware.OS.Build } else { Get-HLOSBuild }
    if ($build -ge 19041 -and $build -lt 22000) {
        Write-HLSub 'Timer resolution 0.5ms' 'SKIP (Win10 2004+ no permite peticiones globales)'
        Add-HLResult -Module 'Timer' -Item 'Resolución 0.5 ms' -Status Skipped -Detail 'Windows 10 2004+: la resolución es por proceso y no existe GlobalTimerResolutionRequests.'
        return
    }

    Set-HLRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' `
        -Name 'GlobalTimerResolutionRequests' -Value 1 -Type DWord `
        -Reason 'Las peticiones de resolución de timer vuelven a ser globales (Win11 22H2+).' | Out-Null

    $resident = Join-Path $HL.Root 'src\modules\windows\timer_resident.ps1'
    if (-not (Test-Path $resident)) { throw "No se encuentra $resident" }

    if (Get-ScheduledTask -TaskName $script:HLTimerTask -ErrorAction SilentlyContinue) {
        Write-HLSub 'Timer resolution 0.5ms' 'OK (tarea ya instalada)'
        Add-HLResult -Module 'Timer' -Item 'Resolución 0.5 ms' -Status Skipped -Detail 'La tarea ya existía'
        return
    }
    if ($HL.DryRun) { Write-HLSub 'Timer resolution 0.5ms' 'SKIP (DryRun)'; return }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Resolution 5000' -f $resident
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $script:HLTimerTask -Action $action -Trigger $trigger -Settings $settings `
        -Principal $principal -Description 'Hardline: mantiene la resolución del timer en 0.5 ms.' -Force | Out-Null
    Add-HLManifestEntry -Type 'ScheduledTask' -Data @{ Name = $script:HLTimerTask; ProcessMatch = 'timer_resident.ps1' }

    Start-ScheduledTask -TaskName $script:HLTimerTask
    Write-HLSub 'Timer resolution 0.5ms' 'OK'
    Add-HLResult -Module 'Timer' -Item 'Resolución 0.5 ms' -Status Applied -Detail "Tarea '$script:HLTimerTask' al iniciar sesión + GlobalTimerResolutionRequests=1"
    if ($build -ge 22000) { $HL.NeedsReboot = $true }   # la clave del kernel se lee al arrancar
}
