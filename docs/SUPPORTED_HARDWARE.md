# Hardware soportado

Hardline funciona en cualquier PC con Windows 10 22H2 / 11. Lo que cambia según el hardware es cuánto puede hacer por ti.

## Nivel de soporte

| Componente | Soporte completo | Parcial | Qué pasa en el resto |
|---|---|---|---|
| CPU | Ryzen 7000 / 9000 (Zen 4 / Zen 5) | Ryzen 5000 y anteriores | Intel: se omite el módulo Ryzen; RAM, Windows, red, juego y audio igual |
| GPU | Radeon RX 6000 / 7000 / 9000, GeForce RTX, Intel Arc | Radeon RX 5000, GeForce GTX | Gráficos integrados: solo los ajustes comunes |
| RAM | DDR5 en AM5 | DDR4 (AM4, Intel) | Detección de EXPO/XMP en todas |
| Red | Intel I225/I226, Realtek 8125/8111, cualquier NIC con `*EEE` estándar | Wi-Fi (solo DNS y QoS) | |
| Mando | Xbox One / Series, DualSense, DualShock 4 | 8BitDo, PowerA, SCUF, Razer, Hori, PDP | Test de mando: XInput o Windows.Gaming.Input; si no aparece en `joy.cpl`, no se detecta |
| Placa (rutas de BIOS) | ASUS, MSI, Gigabyte, ASRock | Otras | Instrucciones genéricas |
| OS | Windows 11 | Windows 10 22H2 | Win10 2004+: sin timer resolution global (limitación de Windows) |

## Plataforma de referencia

Probado como objetivo principal:

| | |
|---|---|
| CPU | AMD Ryzen 5 7600X (6C/12T, Zen 4, iGPU Radeon Graphics) |
| GPU | AMD Radeon RX 6650 XT 8 GB (RDNA2) |
| RAM | 32 GB DDR5 6000 MT/s EXPO |
| Juego | Warzone 1080p |

Lo específico de esta combinación que Hardline tiene en cuenta:

- **iGPU presente**: el 7600X trae gráficos integrados. Si están activos, Hardline fuerza `cod.exe` a la GPU dedicada (`UserGpuPreferences`). Si no usas la salida de vídeo de la placa, desactivar la iGPU en BIOS libera un poco de RAM y evita confusiones de Windows.
- **6 núcleos**: SMT se mantiene activo (ver [TWEAKS_EXPLAINED](TWEAKS_EXPLAINED.md#smt-se-mantiene-activo-en-6-núcleos)). `RendererWorkerCount = 6`.
- **DDR5 6000**: punto dulce de AM5 con UCLK 1:1. No hay que subir más.
- **RX 6650 XT**: SAM funciona con Ryzen 7000 + placa 600-series. Undervolt sugerido: 1100 mV a frecuencia stock.
- **8 GB de VRAM**: texturas en Normal caben con margen; `VideoMemoryScale 0.85` en `adv_options.ini` si existe.

## Detección

Todo por CIM/WMI, que usa nombres de clase no traducidos (funciona igual en Windows en español o inglés).

| Dato | Fuente | Nota |
|---|---|---|
| CPU, núcleos, hilos | `Win32_Processor` | SMT = hilos > núcleos |
| Reloj efectivo | `Win32_PerfFormattedData_Counters_ProcessorInformation` | `MaxClockSpeed` es el base; se multiplica por `% Processor Performance`. No se usa `Get-Counter` porque sus nombres van traducidos. |
| VRAM | `HardwareInformation.qwMemorySize` en la clave de clase del adaptador | `Win32_VideoController.AdapterRAM` es uint32 y se satura en 4 GB |
| SAM / ReBAR | `Win32_DeviceMemoryAddress` asociado a la GPU | Ventana > 512 MB = activo |
| RAM | `Win32_PhysicalMemory` | `SMBIOSMemoryType` 34 = DDR5, 26 = DDR4 |
| EXPO/XMP | Velocidad configurada vs JEDEC | DDR5 > 5200 o DDR4 > 3200 = perfil activo |
| Disco | `Get-Partition` / `Get-PhysicalDisk` | Bus (NVMe, SATA) y tipo |
| Placa | `Win32_BaseBoard` | Para las rutas de BIOS |
| Headset | `Get-PnpDevice -Class AudioEndpoint` y `MEDIA` | Patrones de `headsets.json` |
| Warzone | Registro de desinstalación (Battle.net), `libraryfolders.vdf` (Steam), `XboxGames` (Game Pass) | `cod.exe` |

## Headsets con perfil propio

| Id | Modelo | Detección por nombre |
|---|---|---|
| `hyperx-cloud-ii` | HyperX Cloud II (y Cloud II Wireless) | `Cloud II`, `HyperX Cloud`, `HyperX 7.1` |
| `logitech-g-pro-x` | Logitech G Pro X (y Pro X 2) | `PRO X`, `G PRO` |
| `steelseries-arctis-7` | SteelSeries Arctis 7 / Nova 7 | `Arctis 7`, `Arctis Nova 7` |
| `razer-blackshark-v2` | Razer BlackShark V2 (Pro, X) | `BlackShark` |
| `corsair-hs80` | Corsair HS80 | `HS80` |
| `astro-a40-tr` | Astro A40 TR | `A40`, `ASTRO A40` |
| `generic` | Cualquier otro | Preset base |

Para estos 6 se descarga además su corrección medida de AutoEq; el perfil de `headsets.json` es el respaldo sin internet.

**Cualquier otro modelo**: opción "Otro modelo" en el menú, escribe el nombre y elige entre los ~8800 perfiles de [AutoEq](https://github.com/jaakkopasanen/AutoEq). O deja un archivo de Equalizer APO (de [autoeq.app](https://autoeq.app)) en la carpeta `headsets\`.

Si tu headset conecta por jack a la placa o a una tarjeta de sonido, Windows lo ve como "Altavoces (Realtek...)" y no se detecta por nombre: elígelo en la lista o búscalo.

Añadir un perfil incluido: copia un bloque en `headsets.json`, ajusta filtros y `match`, y ejecuta `tests\validate.ps1` (comprueba rangos y que el preamp calculado no deje clipping).

## Plataformas

| Plataforma | Detección |
|---|---|
| Battle.net | `Program Files (x86)\Battle.net\Battle.net.exe` o entrada de desinstalación |
| Steam | `HKCU\Software\Valve\Steam\SteamExe` |
| Xbox app / Game Pass | Paquete AppX `Microsoft.GamingApp` o servicio `XblAuthManager` |
