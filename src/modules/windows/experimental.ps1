#Requires -Version 5.1
<#
    Hardline - tweaks experimentales.

    Desactivados por defecto. Circulan en casi todas las guías de "baja
    latencia", pero la evidencia es débil o mixta: en unos equipos se mide
    una mejora pequeña, en otros nada. Se ofrecen porque mucha gente los pide,
    con su explicación honesta y revertibles. El benchmark antes/después
    (jitter de Sleep(1)) y LatencyMon son la forma de comprobar si en TU
    equipo aportan algo; si no, revierte.

      disabledynamictick       El kernel deja de "saltarse" ticks del timer en
                               reposo. Pensado para ahorrar batería; en
                               escritorio, desactivarlo puede dar un timer más
                               regular. Se salta si hay BitLocker.
      Mouse/KeyboardDataQueueSize
                               Tamaño del búfer de eventos de ratón/teclado
                               (100 por defecto). Las guías bajan a 16-20; con
                               ratones de 4000-8000 Hz eso puede perder
                               eventos. Hardline usa 50: margen de sobra.
      Win32PrioritySeparation  0x26: quantum corto y variable con boost al
                               proceso en primer plano. Muy cercano al
                               comportamiento por defecto en Windows cliente.
#>

function Test-HLBitLocker {
    try {
        $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        return ("$($v.ProtectionStatus)" -eq 'On')
    } catch {
        $out = (& manage-bde.exe -status $env:SystemDrive 2>$null) -join ' '
        # La salida está traducida; el porcentaje de cifrado y "Protection On" / "Protección activada" no.
        return ($out -match 'Protection On|Protecci.n activada')
    }
}

function Set-HLDynamicTick {
    if (Test-HLBitLocker) {
        Write-HLSub 'disabledynamictick' 'SKIP (BitLocker activo)'
        Add-HLResult -Module 'Experimental' -Item 'disabledynamictick' -Status Skipped -Detail 'BitLocker activo: cambiar el BCD puede pedir la clave de recuperación al arrancar'
        return
    }
    # El nombre del elemento aparece igual en cualquier idioma; el valor (Yes/Sí) no.
    $cur = (& bcdedit.exe /enum '{current}' 2>$null) -join "`n"
    if ($cur -match '(?im)^\s*disabledynamictick\s+(\S+)') {
        Write-HLSub 'disabledynamictick' 'OK (ya definido)'
        Add-HLResult -Module 'Experimental' -Item 'disabledynamictick' -Status Skipped -Detail "Ya definido ($($Matches[1])); no se toca"
        return
    }
    if ($HL.DryRun) { Write-HLSub 'disabledynamictick' 'SKIP (DryRun)'; return }
    & bcdedit.exe /set '{current}' disabledynamictick yes | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bcdedit devolvió $LASTEXITCODE" }
    Add-HLManifestEntry -Type 'Bcd' -Data @{ Element = 'disabledynamictick'; Created = $true }
    $HL.NeedsReboot = $true
    Write-HLSub 'disabledynamictick = yes' 'OK'
    Add-HLResult -Module 'Experimental' -Item 'disabledynamictick' -Status Applied -Detail 'Efectivo tras reiniciar. Compara el jitter de Sleep(1) con -BenchmarkOnly.'
}

function Invoke-HLExperimental {
    param($Hardware)
    Write-HLStep 'Tweaks experimentales...'
    Write-HLWarn 'Evidencia débil o mixta. Mide antes/después y revierte si no notas nada.'

    Invoke-HLSafely 'Experimental' 'disabledynamictick' { Set-HLDynamicTick }

    $reg = @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters'; Name = 'MouseDataQueueSize'; Value = 50; Why = 'Búfer de eventos del ratón 100 -> 50' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters'; Name = 'KeyboardDataQueueSize'; Value = 50; Why = 'Búfer de eventos del teclado 100 -> 50' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Value = 38; Why = 'Quantum corto/variable con boost al primer plano (0x26)' }
    )
    foreach ($r in $reg) {
        Invoke-HLSafely 'Experimental' $r.Name {
            $changed = Set-HLRegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type DWord -Reason "Experimental: $($r.Why)"
            if ($changed) {
                $HL.NeedsReboot = $true
                Write-HLSub "$($r.Name) = $($r.Value)" 'OK'
                Add-HLResult -Module 'Experimental' -Item $r.Name -Status Applied -Detail "$($r.Why). Efectivo tras reiniciar."
            } else {
                Add-HLResult -Module 'Experimental' -Item $r.Name -Status Skipped -Detail 'Ya tenía ese valor'
            }
        }
    }
}
