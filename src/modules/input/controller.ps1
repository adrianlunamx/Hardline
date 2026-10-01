#Requires -Version 5.1
<#
    Hardline - mando.

    Qué retrasa de verdad a un mando en PC, por orden de impacto:

      1. La conexión. Bluetooth añade latencia y jitter frente a cable o al
         adaptador inalámbrico oficial. Se detecta y se avisa.
      2. Capas intermedias. DS4Windows, reWASD, x360ce, InputMapper o Steam
         Input traducen el mando a otro mando virtual: cada traducción es un
         salto más. Warzone soporta Xbox, DualSense y DualShock de forma
         nativa, así que en la mayoría de casos sobran. Se detectan y se avisa.
      3. Ahorro de energía USB. Windows puede suspender el puerto del mando o
         su hub; al despertar hay microcortes o un primer input retrasado. Se
         desactiva para el mando y su hub (revertible).
      4. Zona muerta. Demasiado alta = el stick no responde a movimientos
         finos; demasiado baja = drift. El test de mando mide el drift real de
         tus sticks y te dice el mínimo seguro (controller_test.ps1).

    Lo que NO se hace: "overclock" de la tasa de sondeo (hidusbf y similares).
    Exige un driver sin firmar o el modo de prueba de Windows, y eso puede
    entrar en conflicto con el anticheat.
#>

# Fabricantes de mandos por VID USB.
$script:HLControllerVendors = @{
    '045E' = 'Microsoft (Xbox)'; '054C' = 'Sony (PlayStation)'; '057E' = 'Nintendo'; '2DC8' = '8BitDo'
    '0E6F' = 'PDP'; '24C6' = 'PowerA'; '0F0D' = 'Hori'; '2E95' = 'SCUF'; '1532' = 'Razer'; '0738' = 'Mad Catz'; '20D6' = 'PowerA'
}

# Programas que interponen un mando virtual entre el mando real y el juego.
$script:HLControllerRemappers = @(
    @{ Process = 'DS4Windows';   Name = 'DS4Windows' }
    @{ Process = 'reWASD*';      Name = 'reWASD' }
    @{ Process = 'x360ce*';      Name = 'x360ce' }
    @{ Process = 'InputMapper';  Name = 'InputMapper' }
    @{ Process = 'JoyToKey';     Name = 'JoyToKey' }
    @{ Process = 'DSX';          Name = 'DSX (DualSenseX)' }
    @{ Process = 'BetterJoy*';   Name = 'BetterJoy' }
)

<#
    Clasifica dispositivos PnP como mandos. Recibe objetos con FriendlyName,
    InstanceId y Class (lo que devuelve Get-PnpDevice) para poder probarlo sin
    hardware. Devuelve un mando por dispositivo físico.
#>
function Get-HLControllerFromPnp {
    param([Parameter(Mandatory)] $Devices)
    $nameRx = 'controller|gamepad|mando|DualSense|DualShock|Xbox|XINPUT|8BitDo|SCUF|PowerA|Pro Controller'
    $exclude = 'Bluetooth.*Radio|Adapter for Windows|Wireless Adapter|Root Hub|Host Controller|Audio|Keyboard|Mouse|Headset|Teclado|Rat.n'
    $out = @{}
    foreach ($d in $Devices) {
        $name = "$($d.FriendlyName)"; $id = "$($d.InstanceId)"
        if ($name -match $exclude) { continue }
        # Bluetooth: VID&0002054c (0001/0002 = origen del ID, luego el VID). USB/HID: VID_054C.
        $vid = if ($id -match 'VID&000[12]([0-9A-Fa-f]{4})') { $Matches[1].ToUpperInvariant() } elseif ($id -match 'VID[_&]([0-9A-Fa-f]{4})') { $Matches[1].ToUpperInvariant() } else { '' }
        $pid_ = if ($id -match 'PID[_&]([0-9A-Fa-f]{4})') { $Matches[1].ToUpperInvariant() } else { '' }
        $knownVid = $vid -and $script:HLControllerVendors.ContainsKey($vid)
        $looksLike = $name -match $nameRx -or "$($d.Class)" -in @('XnaComposite', 'XboxComposite')
        if (-not ($looksLike -and ($knownVid -or $name -match $nameRx))) { continue }
        # Los mandos de Microsoft comparten VID con ratones/teclados: exigir nombre de mando.
        if ($vid -eq '045E' -and $name -notmatch $nameRx) { continue }

        $conn = if ($id -match '^(BTHENUM|BTHLEDEVICE|BTHLE)\\' -or $id -match '\{00001124-0000-1000-8000-00805F9B34FB\}') { 'Bluetooth' }
        elseif ($id -match '^USB\\' -or $id -match '^HID\\VID') { 'USB' }
        elseif ($id -match 'XBOXGIP|GIP') { 'Adaptador Xbox' }
        else { 'Otro' }
        $brand = if ($knownVid) { $script:HLControllerVendors[$vid] } elseif ($name -match 'DualSense|DualShock|Wireless Controller') { 'Sony (PlayStation)' } else { 'Desconocido' }
        # Un mando aparece como varios nodos (USB, HID, XINPUT): uno por VID+PID+conexión.
        $key = if ($vid) { '{0}|{1}|{2}' -f $vid, $pid_, $conn } else { '{0}|{1}' -f $name, $conn }
        if (-not $out.ContainsKey($key) -or $id -match '^USB\\') {
            $out[$key] = [pscustomobject]@{ Name = $name; Brand = $brand; Vid = $vid; Connection = $conn; InstanceId = $id; PlayStation = ($vid -eq '054C' -or $name -match 'DualSense|DualShock') }
        }
    }
    return @($out.Values)
}

function Get-HLControllers {
    $devs = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { "$($_.Class)" -in @('HIDClass', 'XnaComposite', 'XboxComposite', 'USB', 'Bluetooth') })
    return @(Get-HLControllerFromPnp -Devices $devs)
}

function Get-HLParentDevice {
    param([string]$InstanceId)
    try { return "$((Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop).Data)" } catch { return '' }
}

<#
    "Permitir que el equipo apague este dispositivo para ahorrar energía", por
    registro, para el nodo USB del mando y su hub padre.
#>
function Disable-HLControllerUsbPower {
    param([Parameter(Mandatory)] $Controller)
    $targets = @()
    if ($Controller.InstanceId -like 'USB\*') { $targets += $Controller.InstanceId }
    $parent = Get-HLParentDevice -InstanceId $Controller.InstanceId
    if ($parent -like 'USB\*') { $targets += $parent }
    $changed = 0
    foreach ($t in ($targets | Select-Object -Unique)) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Enum\$t\Device Parameters"
        if (-not (Test-Path $key)) { continue }
        foreach ($v in @('EnhancedPowerManagementEnabled', 'AllowIdleIrpInD3', 'SelectiveSuspendEnabled')) {
            if (Set-HLRegistryValue -Path $key -Name $v -Value 0 -Type DWord -Reason "Ahorro de energía USB del mando ($($Controller.Name))") { $changed++ }
        }
    }
    return $changed
}

# Ajustes de mando de Warzone, mismo motor que la configuración gráfica.
function Get-HLWarzoneControllerRules {
    @(
        @{ Label = 'Zona muerta de gatillos (L2/R2)'; Target = '0';   Keys = @('TriggerDeadzone', 'GamepadTriggerDeadzone', 'TriggerDeadZone', 'LeftTriggerDeadzone', 'RightTriggerDeadzone') }
        @{ Label = 'Efecto de gatillo (DualSense)';   Target = 'off'; Keys = @('TriggerEffect', 'DualSenseTriggerEffect', 'AdaptiveTriggers', 'TriggerEffects') }
        @{ Label = 'Vibración del mando';             Target = 'off'; Keys = @('GamepadVibration', 'ControllerVibration', 'Vibration', 'GamepadRumble') }
    )
}

function Invoke-HLController {
    param([Parameter(Mandatory)] $Hardware)
    Write-HLStep 'Mando...'

    $pads = @(Get-HLControllers)
    if ($pads.Count -eq 0) {
        Write-HLSub 'Ningún mando conectado' 'SKIP'
        Add-HLResult -Module 'Mando' -Item 'Detección' -Status Skipped -Detail 'Conecta el mando y vuelve a ejecutar (o usa el test de mando)'
        return
    }

    foreach ($p in $pads) {
        Write-HLSub ("{0} [{1}] por {2}" -f $p.Name, $p.Brand, $p.Connection)
        Add-HLResult -Module 'Mando' -Item $p.Name -Status Info -Detail "$($p.Brand), conexión $($p.Connection)"

        if ($p.Connection -eq 'Bluetooth') {
            Write-HLWarn "$($p.Name) va por Bluetooth: más latencia y jitter que por cable."
            Add-HLManualStep 'Mando' ("{0}: juega por cable USB (o con el adaptador inalámbrico oficial). Bluetooth comparte radio con el Wi-Fi y añade latencia variable." -f $p.Name)
        }
        if ($p.Connection -eq 'USB') {
            Invoke-HLSafely 'Mando' "Energía USB ($($p.Name))" {
                $n = Disable-HLControllerUsbPower -Controller $p
                if ($n -gt 0) {
                    $HL.NeedsReboot = $true
                    Write-HLSub 'Ahorro de energía USB del mando y su hub' 'OK'
                    Add-HLResult -Module 'Mando' -Item "Energía USB ($($p.Name))" -Status Applied -Detail "Suspensión selectiva desactivada en el mando y su hub ($n valores). Efectivo al reconectar o reiniciar."
                } else {
                    Add-HLResult -Module 'Mando' -Item "Energía USB ($($p.Name))" -Status Skipped -Detail 'Ya desactivado'
                }
            }
            Add-HLManualStep 'Mando' 'Conecta el mando a un USB trasero de la placa, no a un hub ni al panel frontal: menos saltos y alimentación más estable.'
        }
    }

    # Capas intermedias
    foreach ($r in $script:HLControllerRemappers) {
        if (Get-Process -Name $r.Process -ErrorAction SilentlyContinue) {
            Write-HLWarn "$($r.Name) está en ejecución: traduce el mando a uno virtual y añade un salto de latencia."
            Add-HLManualStep 'Mando' ("Cierra {0} para Warzone: el juego soporta tu mando de forma nativa y la traducción añade latencia. Si lo usas para HidHide u otros juegos, desactívalo solo mientras juegas." -f $r.Name)
            Add-HLResult -Module 'Mando' -Item $r.Name -Status Manual -Detail 'Capa intermedia en ejecución'
        }
    }
    if (@($pads | Where-Object { $_.PlayStation }).Count -gt 0) {
        Add-HLManualStep 'Mando' 'DualSense/DualShock: Warzone los soporta de forma nativa. Si juegas desde Steam, desactiva Steam Input para Call of Duty (Propiedades > Mando > Desactivar Steam Input) para que no pase por la capa de Steam.'
    }

    # Ajustes del juego
    $dir = $Hardware.Game.ConfigDir
    $cst = if ($dir -and (Test-Path $dir)) { Get-ChildItem -Path $dir -Filter 'options*.cst' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } else { $null }
    if ($cst -and -not (Test-HLProcess -Name 'cod')) {
        $res = Update-HLCstFile -Path $cst.FullName -Rules (Get-HLWarzoneControllerRules)
        foreach ($c in $res.Changes) { Add-HLResult -Module 'Mando' -Item $c.Label -Status Applied -Detail "$($c.Key): $($c.From) -> $($c.To)" }
        Write-HLSub "Ajustes de mando en $($cst.Name): $($res.Changes.Count)" 'OK'
        if ($res.Missing.Count -gt 0) { Add-HLManualStep 'Mando' ('En Warzone > Mando, pon a mano: ' + ($res.Missing -join ', ') + ' (zona muerta de gatillos 0, efecto de gatillo y vibración desactivados).') }
    } else {
        Add-HLManualStep 'Mando' 'En Warzone > Mando: zona muerta de gatillos 0, efecto de gatillo desactivado y vibración desactivada.'
    }
    Add-HLManualStep 'Mando' 'Zona muerta de los sticks: botón "Test de mando" de la interfaz o install.ps1 -ControllerTestOnly. Mide el drift real de tus sticks y te da el mínimo seguro para "Zona muerta mínima" del stick izquierdo y derecho. Curva de respuesta: Dinámica.'
}
