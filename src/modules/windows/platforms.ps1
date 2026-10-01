#Requires -Version 5.1
<#
    Hardline - plataformas de juego (Battle.net, Steam, Xbox app).

    Warzone se lanza desde una sola plataforma. Las demás siguen arrancando con
    Windows y dejando procesos residentes (webhelpers, agentes de actualización,
    servicios de Xbox) que ocupan RAM y CPU sin aportar nada a la partida.

    Para cada plataforma instalada que NO uses:
      - Se cierran sus procesos ahora.
      - Se quita su arranque automático (claves Run / tarea de inicio AppX).
      - Se deshabilitan sus servicios (Xbox, Steam Client Service).
    Todo va al manifiesto: rollback.ps1 lo devuelve a su estado. La
    plataforma no se desinstala; puedes abrirla a mano cuando quieras (salvo
    Xbox/Game Pass, que necesita sus servicios: ver la nota de Xbox abajo).
#>

function Get-HLPlatformCatalog {
    @(
        [pscustomobject]@{
            Id        = 'battlenet'
            Name      = 'Battle.net'
            Processes = @('Battle.net', 'Agent', 'BlizzardError')
            RunMatch  = 'Battle\.net'
            Services  = @()
            Note      = 'Agent.exe (Blizzard Update Agent) se relanza solo cuando abres Battle.net.'
        }
        [pscustomobject]@{
            Id        = 'steam'
            Name      = 'Steam'
            Processes = @('steam', 'steamwebhelper', 'steamservice')
            RunMatch  = 'steam\.exe'
            Services  = @('Steam Client Service')
            Note      = 'steamwebhelper suele ocupar 300-600 MB entre sus procesos.'
        }
        [pscustomobject]@{
            Id        = 'xbox'
            Name      = 'Xbox app / Game Pass'
            Processes = @('XboxPcApp', 'XboxPcAppFT', 'XboxPcTray', 'GameBar', 'GameBarFTServer')
            RunMatch  = 'Xbox'
            # XboxGipSvc (accesorios: mandos Xbox, Elite) NO se toca: solo arranca
            # al conectar un accesorio y sin él no se actualiza el firmware del mando.
            Services  = @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'GamingServices', 'GamingServicesNet')
            Note      = 'Sin estos servicios no funcionan los juegos de Game Pass ni de la Microsoft Store que usan Xbox Live (Minecraft, Forza...).'
        }
    )
}

function Test-HLPlatformInstalled {
    param([Parameter(Mandatory)] [string] $Id)
    switch ($Id) {
        'battlenet' {
            if (Test-Path "${env:ProgramFiles(x86)}\Battle.net\Battle.net.exe") { return $true }
            foreach ($r in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
                $hit = Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                    Where-Object { $_.DisplayName -eq 'Battle.net' }
                if ($hit) { return $true }
            }
            return $false
        }
        'steam' {
            $exe = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe
            return [bool]($exe -and (Test-Path $exe))
        }
        'xbox' {
            if (Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction SilentlyContinue) { return $true }
            return [bool](Get-Service -Name 'XblAuthManager' -ErrorAction SilentlyContinue)
        }
    }
    return $false
}

# Plataforma desde la que está instalado Warzone, según dónde se encontró cod.exe.
function Get-HLGamePlatform {
    param($Hardware)
    if (-not $Hardware -or -not $Hardware.Game.Primary) { return $null }
    $p = $Hardware.Game.Primary
    if ($p -match '\\steamapps\\') { return 'steam' }
    if ($p -match '\\XboxGames\\') { return 'xbox' }
    return 'battlenet'
}

# Arranque automático clásico: valores Run en HKCU/HKLM (32 y 64 bits).
function Disable-HLRunEntries {
    param([Parameter(Mandatory)] [string] $Pattern, [string] $Label)
    $removed = @()
    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($k in $keys) {
        $item = Get-Item $k -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($name in $item.GetValueNames()) {
            if ($name -like 'Hardline*') { continue }
            $data = "$($item.GetValue($name))"
            if ($name -match $Pattern -or $data -match $Pattern) {
                if (Remove-HLRegistryValue -Path $k -Name $name -Reason "Arranque automático de $Label") { $removed += $name }
            }
        }
    }
    return $removed
}

# Arranque automático de apps AppX (Xbox app): State 1 = deshabilitado, 2 = habilitado.
function Disable-HLAppxStartupTask {
    param([Parameter(Mandatory)] [string] $PackageFamily)
    $base = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$PackageFamily"
    $changed = @()
    foreach ($sub in @(Get-ChildItem $base -ErrorAction SilentlyContinue)) {
        $state = (Get-ItemProperty $sub.PSPath -ErrorAction SilentlyContinue).State
        if ($null -ne $state -and [int]$state -eq 2) {
            $path = $sub.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_CURRENT_USER', 'HKCU:'
            if (Set-HLRegistryValue -Path $path -Name 'State' -Value 1 -Type DWord -Reason "Inicio automático de $PackageFamily") { $changed += $sub.PSChildName }
        }
    }
    return $changed
}

function Disable-HLPlatform {
    param([Parameter(Mandatory)] $Platform)

    $done = @()

    # 1. Procesos
    $procs = @(Get-Process -Name $Platform.Processes -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        $mb = [math]::Round((($procs | Measure-Object WorkingSet64 -Sum).Sum) / 1MB)
        if (-not $HL.DryRun) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue }
        $done += "$($procs.Count) procesos cerrados (~$mb MB)"
    }

    # 2. Arranque automático
    $run = @(Disable-HLRunEntries -Pattern $Platform.RunMatch -Label $Platform.Name)
    if ($Platform.Id -eq 'xbox') { $run += @(Disable-HLAppxStartupTask -PackageFamily 'Microsoft.GamingApp_8wekyb3d8bbwe') }
    if ($run.Count -gt 0) { $done += "arranque automático off ($($run -join ', '))" }

    # 3. Servicios
    $svcDone = @(); $svcFail = @()
    foreach ($s in $Platform.Services) {
        try {
            $r = Set-HLServiceStart -Name $s -StartType Disabled -Reason "Plataforma $($Platform.Name) no usada"
            if ($r -eq 'Changed') { $svcDone += $s }
        } catch {
            # GamingServices tiene ACL restringida en algunas builds.
            $svcFail += $s
            Write-HLLog WARN "Servicio $s : $($_.Exception.Message)"
        }
    }
    if ($svcDone.Count -gt 0) { $done += "servicios deshabilitados ($($svcDone -join ', '))" }
    if ($svcFail.Count -gt 0) { $done += "no modificables: $($svcFail -join ', ')" }

    if ($done.Count -eq 0) {
        Write-HLSub "$($Platform.Name): nada activo" 'OK'
        Add-HLResult -Module 'Plataformas' -Item $Platform.Name -Status Skipped -Detail 'Sin procesos, arranque ni servicios activos'
    } else {
        Write-HLSub "$($Platform.Name): $($done -join '; ')" 'OK'
        Add-HLResult -Module 'Plataformas' -Item $Platform.Name -Status Applied -Detail (($done -join '; ') + ". $($Platform.Note)")
    }
}

function Invoke-HLPlatforms {
    param($Hardware, [ValidateSet('', 'battlenet', 'steam', 'xbox')] [string] $Platform = '', [switch] $DisableOthers)

    $catalog = Get-HLPlatformCatalog
    $installed = @($catalog | Where-Object { Test-HLPlatformInstalled -Id $_.Id })
    if ($installed.Count -eq 0) {
        Add-HLResult -Module 'Plataformas' -Item 'Detección' -Status Skipped -Detail 'Ninguna plataforma conocida instalada'
        return
    }

    Write-HLSub ('Plataformas instaladas: ' + (($installed | ForEach-Object { $_.Name }) -join ', '))

    # Plataforma principal: parámetro > pregunta (preseleccionada según dónde está cod.exe).
    if (-not $Platform) {
        $guess = Get-HLGamePlatform -Hardware $Hardware
        $default = 0
        for ($i = 0; $i -lt $catalog.Count; $i++) { if ($catalog[$i].Id -eq $guess) { $default = $i } }
        $i = Read-HLChoice -Prompt '¿Desde qué plataforma juegas Warzone?' -Options @($catalog | ForEach-Object { $_.Name }) -Default $default
        $Platform = $catalog[$i].Id
    }
    $main = $catalog | Where-Object { $_.Id -eq $Platform }
    Write-HLSub "Plataforma de Warzone: $($main.Name) (no se toca)" 'OK'
    Add-HLResult -Module 'Plataformas' -Item 'Principal' -Status Info -Detail $main.Name

    foreach ($p in ($installed | Where-Object { $_.Id -ne $Platform })) {
        # En modo desatendido se conservan: cerrar una plataforma que el usuario
        # usa para otros juegos no es algo que decidir sin preguntar.
        $keep = if ($DisableOthers) { $false } else {
            Read-HLYesNo "¿Usas $($p.Name) para otros juegos? (si no, se cierran sus procesos y se quita su arranque automático)" ([bool]$HL.Unattended)
        }
        if ($keep) {
            Add-HLResult -Module 'Plataformas' -Item $p.Name -Status Skipped -Detail 'El usuario la usa'
            continue
        }
        if ($p.Id -eq 'xbox') { Write-HLInfo $p.Note }
        Invoke-HLSafely 'Plataformas' $p.Name { Disable-HLPlatform -Platform $p }
    }
}
