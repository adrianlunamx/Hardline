#Requires -Version 5.1
<#
    Hardline - detección de hardware.

    Solo lectura. Nada aquí modifica el sistema.
    Fuente principal: CIM/WMI (nombres de clase no localizados, funciona igual
    en Windows en español o inglés). Donde WMI miente (VRAM > 4 GB, reloj real
    de CPU) se usa la fuente correcta y se comenta por qué.
#>

function Get-HLCpuInfo {
    $p = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
    $cpu = $p[0]
    $name = ($cpu.Name -replace '\s+', ' ').Trim()
    $cores = ($p | Measure-Object NumberOfCores -Sum).Sum
    $threads = ($p | Measure-Object NumberOfLogicalProcessors -Sum).Sum

    # MaxClockSpeed es el reloj base. El reloj efectivo se obtiene multiplicando
    # por "% Processor Performance" (contador que sí refleja boost). Se usa la
    # clase WMI del contador y no Get-Counter, porque Get-Counter usa nombres
    # localizados y falla en Windows en español.
    $effective = $null
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
        if ($perf.PercentProcessorPerformance -gt 0) {
            $effective = [int]($cpu.MaxClockSpeed * $perf.PercentProcessorPerformance / 100)
        }
    } catch { }

    $family = 'Unknown'
    $isRyzen = $name -match 'Ryzen'
    if ($isRyzen -and $name -match 'Ryzen\s+(?:\d+\s+)?(?:PRO\s+)?(\d)(\d)\d\d') {
        $gen = [int]$Matches[1]
        $family = switch ($gen) { 9 { 'Zen5' } 7 { 'Zen4' } 5 { 'Zen3' } 3 { 'Zen2' } default { 'Ryzen' } }
    } elseif ($name -match 'Intel') {
        $family = 'Intel'
    }

    [pscustomobject]@{
        Name         = $name
        Vendor       = if ($cpu.Manufacturer -match 'AMD') { 'AMD' } elseif ($cpu.Manufacturer -match 'Intel') { 'Intel' } else { $cpu.Manufacturer }
        Cores        = [int]$cores
        Threads      = [int]$threads
        SMT          = ($threads -gt $cores)
        BaseMHz      = [int]$cpu.MaxClockSpeed
        EffectiveMHz = $effective
        Family       = $family
        IsRyzen      = $isRyzen
        IsX3D        = ($name -match 'X3D')
        HasIGPU      = ($isRyzen -and $family -in @('Zen4', 'Zen5') -and $name -notmatch '\d{4}F\b')
    }
}

function Get-HLGpuInfo {
    $controllers = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)

    # Win32_VideoController.AdapterRAM es uint32: se satura en 4 GB.
    # La VRAM real está en la clave de clase del adaptador (QWORD).
    $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $classKeys = @(Get-ChildItem $classRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })

    $list = foreach ($c in $controllers) {
        $vramBytes = [uint64]0
        $classKey = $null
        foreach ($k in $classKeys) {
            $props = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.DriverDesc -eq $c.Name) {
                $classKey = $k.PSPath
                $q = $props.'HardwareInformation.qwMemorySize'
                if ($q) { $vramBytes = [uint64]$q }
                break
            }
        }
        if ($vramBytes -eq 0 -and $c.AdapterRAM) { $vramBytes = [uint64]$c.AdapterRAM }

        $vendor = if ($c.Name -match 'Radeon|AMD') { 'AMD' } elseif ($c.Name -match 'NVIDIA|GeForce') { 'NVIDIA' } elseif ($c.Name -match 'Intel') { 'Intel' } else { 'Other' }
        # La iGPU de Ryzen 7000 se llama "AMD Radeon(TM) Graphics" sin número de modelo.
        $integrated = ($c.Name -match '^AMD Radeon\(TM\) Graphics$|Radeon Graphics$|Intel.*(UHD|Iris|HD Graphics)')

        $driverDate = $null
        if ($c.DriverDate) { $driverDate = [datetime]$c.DriverDate }

        [pscustomobject]@{
            Name          = $c.Name
            Vendor        = $vendor
            VRAMGB        = [math]::Round($vramBytes / 1GB, 0)
            DriverVersion = $c.DriverVersion
            DriverDate    = $driverDate
            Integrated    = $integrated
            ClassKey      = $classKey
            PnpId         = $c.PNPDeviceID
            Active        = ($c.CurrentHorizontalResolution -gt 0)
        }
    }

    $list = @($list)
    $primary = $list | Where-Object { -not $_.Integrated } | Sort-Object VRAMGB -Descending | Select-Object -First 1
    if (-not $primary) { $primary = $list | Select-Object -First 1 }

    [pscustomobject]@{
        All          = $list
        Primary      = $primary
        HasIGPUActive = [bool]($list | Where-Object { $_.Integrated })
    }
}

function Get-HLMemoryInfo {
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $totalBytes = [uint64](($mods | Measure-Object Capacity -Sum).Sum)

    # SMBIOSMemoryType: 26 = DDR4, 34 = DDR5 (SMBIOS 3.x).
    $smbType = ($mods | Select-Object -First 1).SMBIOSMemoryType
    $type = switch ($smbType) { 34 { 'DDR5' } 26 { 'DDR4' } 24 { 'DDR3' } default { 'Desconocido' } }

    $configured = ($mods | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
    $rated = ($mods | Measure-Object Speed -Maximum).Maximum

    # Heurística de EXPO/XMP: JEDEC en AM5 es 4800-5200 MT/s y en DDR4 2133-3200.
    # Por encima de eso, el perfil está activo (o hay OC manual).
    $jedecMax = if ($type -eq 'DDR5') { 5200 } elseif ($type -eq 'DDR4') { 3200 } else { 0 }
    $memProfile = if ($jedecMax -eq 0) { 'Desconocido' } elseif ($configured -gt $jedecMax) { 'Activo' } else { 'Inactivo' }

    [pscustomobject]@{
        TotalGB    = [math]::Round($totalBytes / 1GB, 0)
        Type       = $type
        SpeedMTs   = [int]$configured
        RatedMTs   = [int]$rated
        Modules    = $mods.Count
        Profile    = $memProfile
        PartNumber = (($mods | Select-Object -First 1).PartNumber -as [string]).Trim()
        Maker      = (($mods | Select-Object -First 1).Manufacturer -as [string]).Trim()
    }
}

function Get-HLStorageInfo {
    $sysLetter = $env:SystemDrive.TrimEnd(':')
    $result = [ordered]@{ SystemBus = 'Desconocido'; SystemMedia = 'Desconocido'; SystemModel = '' }
    try {
        $part = Get-Partition -DriveLetter $sysLetter -ErrorAction Stop
        $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
        $phys = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq "$($disk.Number)" } | Select-Object -First 1
        $result.SystemBus = "$($disk.BusType)"
        $result.SystemModel = "$($disk.FriendlyName)".Trim()
        if ($phys) { $result.SystemMedia = "$($phys.MediaType)" }
    } catch { }
    [pscustomobject]$result
}

function Get-HLBoardInfo {
    $b = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $maker = "$($b.Manufacturer)"
    $vendor = switch -Regex ($maker) {
        'ASUS' { 'ASUS' } 'Micro-Star|MSI' { 'MSI' } 'Gigabyte' { 'Gigabyte' } 'ASRock' { 'ASRock' } default { $maker }
    }
    [pscustomobject]@{
        Vendor      = $vendor
        Product     = "$($b.Product)".Trim()
        BiosVersion = "$($bios.SMBIOSBIOSVersion)".Trim()
        BiosDate    = $bios.ReleaseDate
    }
}

function Get-HLAudioEndpoints {
    # Endpoints de reproducción: SWD\MMDEVAPI\{0.0.0.00000000}.{guid}
    # Endpoints de captura:      SWD\MMDEVAPI\{0.0.1.00000000}.{guid}
    $eps = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue)
    foreach ($e in $eps) {
        [pscustomobject]@{
            Name   = $e.FriendlyName
            Render = ($e.InstanceId -like '*{0.0.0.00000000}*')
            Status = "$($e.Status)"
        }
    }
}

function Find-HLHeadset {
    param([Parameter(Mandatory)] $Profiles, $Endpoints)
    $names = @($Endpoints | Where-Object { $_.Render } | ForEach-Object { $_.Name })
    # Algunos headsets USB solo exponen el nombre del modelo en el dispositivo MEDIA.
    $names += @(Get-PnpDevice -Class MEDIA -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $_.FriendlyName })
    foreach ($h in $Profiles) {
        foreach ($pattern in @($h.match)) {
            $hit = $names | Where-Object { $_ -match $pattern } | Select-Object -First 1
            if ($hit) { return [pscustomobject]@{ Id = $h.id; DeviceName = $hit } }
        }
    }
    return $null
}

function Get-HLNetworkInfo {
    $routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
    $adapters = foreach ($r in $routes) {
        $a = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        if (-not $a -or $a.Status -ne 'Up') { continue }
        [pscustomobject]@{
            Name           = $a.Name
            Description    = $a.InterfaceDescription
            InterfaceIndex = $a.ifIndex
            Guid           = $a.InterfaceGuid
            Wireless       = ($a.PhysicalMediaType -match '802\.11|Wireless' -or $a.NdisPhysicalMedium -eq 9)
            LinkSpeed      = $a.LinkSpeed
            Gateway        = $r.NextHop
            Virtual        = ($a.Virtual -or $a.InterfaceDescription -match 'Hyper-V|VirtualBox|VMware|TAP-|WireGuard|Tailscale|ZeroTier')
        }
    }
    $adapters = @($adapters | Where-Object { -not $_.Virtual })
    [pscustomobject]@{
        Adapters = $adapters
        Primary  = $adapters | Select-Object -First 1
    }
}

<#
    Busca el ejecutable del juego. Warzone se lanza como cod.exe desde el
    launcher unificado de Call of Duty (Battle.net, Steam o Xbox app).
#>
function Find-HLWarzone {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Battle.net: la entrada de desinstalación trae InstallLocation.
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.DisplayName -match '^Call of Duty' -and $p.InstallLocation) {
                $candidates.Add((Join-Path $p.InstallLocation '_retail_\cod.exe'))
                $candidates.Add((Join-Path $p.InstallLocation 'cod.exe'))
            }
        }
    }

    # Steam: todas las bibliotecas declaradas en libraryfolders.vdf.
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $libs = @($steam -replace '/', '\')
        $vdf = Join-Path $libs[0] 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object {
                $libs += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\')
            }
        }
        foreach ($l in ($libs | Select-Object -Unique)) {
            foreach ($folder in @('Call of Duty HQ', 'Call of Duty')) {
                $candidates.Add((Join-Path $l "steamapps\common\$folder\cod.exe"))
            }
        }
    }

    # Rutas por defecto en cada unidad fija (Battle.net y Xbox app).
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $d = $_.DeviceID
        $candidates.Add("$d\Program Files (x86)\Call of Duty\_retail_\cod.exe")
        $candidates.Add("$d\Program Files\Call of Duty\_retail_\cod.exe")
        $candidates.Add("$d\XboxGames\Call of Duty\Content\cod.exe")
    }

    $found = @($candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
    [pscustomobject]@{
        Paths     = $found
        Primary   = $found | Select-Object -First 1
        GamePass  = [bool]($found | Where-Object { $_ -like '*XboxGames*' })
        ConfigDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Call of Duty\players'
    }
}

function Get-HLHardware {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    [pscustomobject]@{
        CPU     = Get-HLCpuInfo
        GPU     = Get-HLGpuInfo
        RAM     = Get-HLMemoryInfo
        Storage = Get-HLStorageInfo
        Board   = Get-HLBoardInfo
        Audio   = @(Get-HLAudioEndpoints)
        Network = Get-HLNetworkInfo
        Game    = Find-HLWarzone
        OS      = [pscustomobject]@{ Caption = "$($os.Caption)".Trim(); Build = Get-HLOSBuild; IsWin11 = ((Get-HLOSBuild) -ge 22000) }
    }
}

function Show-HLHardware {
    param([Parameter(Mandatory)] $Hw)

    $c = $Hw.CPU
    $clock = if ($c.EffectiveMHz) { '{0:N1}GHz' -f ($c.EffectiveMHz / 1000) } else { '{0:N1}GHz base' -f ($c.BaseMHz / 1000) }
    Write-HLOk ('CPU: {0} ({1}C/{2}T) @ {3}' -f $c.Name, $c.Cores, $c.Threads, $clock)

    $g = $Hw.GPU.Primary
    if ($g) {
        Write-HLOk ('GPU: {0} {1}GB (driver {2})' -f $g.Name, $g.VRAMGB, $g.DriverVersion)
        if ($Hw.GPU.HasIGPUActive -and -not $g.Integrated) { Write-HLInfo 'iGPU activa además de la dedicada.' }
    } else {
        Write-HLWarn 'GPU: no detectada'
    }

    $r = $Hw.RAM
    $profileLabel = switch ($r.Profile) { 'Activo' { 'EXPO/XMP activo' } 'Inactivo' { 'EXPO/XMP INACTIVO' } default { 'perfil desconocido' } }
    $line = 'RAM: {0}GB {1} @ {2} MT/s ({3})' -f $r.TotalGB, $r.Type, $r.SpeedMTs, $profileLabel
    if ($r.Profile -eq 'Inactivo') { Write-HLWarn $line } else { Write-HLOk $line }

    $s = $Hw.Storage
    $verdict = if ($s.SystemBus -eq 'NVMe') { 'good' } elseif ($s.SystemMedia -eq 'SSD') { 'ok' } elseif ($s.SystemMedia -eq 'HDD') { 'lento' } else { '?' }
    Write-HLOk ('Storage: {0} {1} ({2})' -f $s.SystemBus, $s.SystemModel, $verdict)

    Write-HLOk ('Placa: {0} {1} (BIOS {2})' -f $Hw.Board.Vendor, $Hw.Board.Product, $Hw.Board.BiosVersion)
    Write-HLOk ('OS: {0} (build {1})' -f $Hw.OS.Caption, $Hw.OS.Build)

    $n = $Hw.Network.Primary
    if ($n) {
        $kind = if ($n.Wireless) { 'Wi-Fi' } else { 'Ethernet' }
        Write-HLOk ('Red: {0} - {1} ({2})' -f $kind, $n.Description, $n.LinkSpeed)
    }

    if ($Hw.Game.Primary) { Write-HLOk "Warzone: $($Hw.Game.Primary)" }
    else { Write-HLWarn 'Warzone: cod.exe no encontrado (los ajustes por-ejecutable se omiten)' }
}
