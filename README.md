# Hardline

Optimizaciones reales para Warzone. Nada de placebo.

Hardline es un script de PowerShell que ajusta Windows, la plataforma AMD, la red, la configuración del juego y el audio. Aplica lo que se puede aplicar de forma segura y reversible. Lo que no (BIOS, Adrenalin) te lo deja escrito paso a paso con la ruta de menús de **tu** placa. Todo cambio queda registrado con su valor anterior y se revierte con un comando.

## Qué hace

| Área | Automático | Te lo deja en el reporte |
|---|---|---|
| Plataformas | Eliges desde dónde juegas (Battle.net, Steam, Xbox app); las que no usas se cierran, pierden el arranque automático y sus servicios se deshabilitan | |
| Windows | Servicios de fondo, Game DVR off, Game Mode on, HAGS off, MMCSS, plan Ultimate Performance, timer 0.5 ms, widgets/Cortana fuera | LatencyMon si hay picos DPC |
| CPU Ryzen | Detección de familia, SMT y chipset driver | PBO, Curve Optimizer -20, validación con Prime95/CoreCycler |
| GPU Radeon | Driver, estado real de SAM/ReBAR, crashes TDR recientes | Anti-Lag, Chill off, RIS 80%, undervolt 1100 mV |
| RAM | Velocidad y si EXPO/XMP está activo | tRFC con ZenTimings |
| Red | DNS 1.1.1.1, EEE/Green Ethernet off, autotuning, QoS DSCP 46 para `cod.exe` | Test de bufferbloat, SQM en el router |
| Warzone | Ajustes gráficos en `options.*.cst` / `adv_options.ini` | FOV, brillo, Anti-Lag 2 |
| Audio | Corrección medida de tu headset (AutoEq, ~8800 modelos) + EQ de pasos (Equalizer APO) + compresor/gate (Voicemeeter) | Enrutado de `cod.exe` en Windows |

Lo que Hardline **no** hace, y por qué, está en [docs/TWEAKS_EXPLAINED.md](docs/TWEAKS_EXPLAINED.md#lo-que-hardline-no-hace).

## Instalación

PowerShell como administrador:

```powershell
irm https://raw.githubusercontent.com/jhernandezl2c-hash/CLVX-GMNG/main/install.ps1 | iex
```

Necesitas permisos de admin (si no los tienes, el script pide elevación). Crea un restore point antes de tocar nada. Se instala en `%LOCALAPPDATA%\Hardline`.

Ver qué haría sin aplicar nada:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jhernandezl2c-hash/CLVX-GMNG/main/install.ps1))) -DryRun
```

Desde un clon:

```powershell
git clone https://github.com/jhernandezl2c-hash/CLVX-GMNG.git hardline
cd hardline
.\install.ps1
```

### Opciones

| Parámetro | Efecto |
|---|---|
| `-DryRun` | Detecta y muestra, no cambia nada |
| `-Unattended` | Sin preguntas (respuestas por defecto). Los instaladores de Equalizer APO y VB-CABLE siguen abriendo su ventana: combínalo con `-SkipAudio` para una ejecución sin intervención |
| `-Platform battlenet\|steam\|xbox` | Plataforma desde la que juegas Warzone (por defecto se deduce de dónde está `cod.exe` y se confirma) |
| `-Headset <id o modelo>` | Perfil incluido (`hyperx-cloud-ii`, `logitech-g-pro-x`, `steelseries-arctis-7`, `razer-blackshark-v2`, `corsair-hs80`, `astro-a40-tr`, `generic`), un archivo de `headsets\` o cualquier modelo para buscar en AutoEq (`-Headset "Kraken V3"`) |
| `-AudioMode Full\|EqOnly` | EQ + compresor, o solo EQ (sin latencia añadida) |
| `-SkipWindows` `-SkipNetwork` `-SkipGame` `-SkipAudio` `-SkipBenchmark` | Omitir módulos |
| `-BenchmarkOnly` | Medir otra vez y comparar con el benchmark previo (tras reiniciar) |

## Flujo

1. Permisos de admin
2. Restore point `Hardline_YYYY-MM-DD_HH-mm`
3. Detección de hardware
4. Snapshot de la configuración actual (`backups/<fecha>/snapshot`)
5. Benchmark previo
6. Windows, plataformas de juego, CPU, GPU, RAM, red, Warzone
7. Audio: headset (detectado, elegido o buscado en AutoEq), modo, instalación de Equalizer APO / VB-CABLE / Voicemeeter Potato / Peace
8. Benchmark posterior
9. Reporte en `reports/YYYY-MM-DD_HH-mm.txt` con pasos manuales y cómo revertir

## Qué mejora

En un Ryzen 5 7600X + RX 6650 XT, Warzone 1080p:

- **FPS**: la subida depende casi entera del punto de partida gráfico. Desde medio/alto a la configuración de Hardline (todo bajo salvo texturas) es donde está la mayor parte de la ganancia; los tweaks de Windows por sí solos mueven poco la media.
- **1% lows y frametimes**: servicios de fondo, Game DVR, plan de energía y timer atacan los picos, no la media. Es lo que más se nota al jugar.
- **Input lag**: Anti-Lag 2 en el juego, HAGS off y sin limitador por software.
- **Audio**: pasos a más distancia y explosiones que no tapan todo.

Hardline no publica cifras que no haya medido en tu equipo. Para medirlo tú: instala [CapFrameX](https://www.capframex.com/), graba 60 s en el mismo recorrido antes y después, y Hardline lee las capturas y las compara en el reporte.

## Audio

El preset de pasos realza 2-4 kHz y recorta por debajo de 500 Hz. Tres realces solapados en 2.2/2.8/3.6 kHz suman **+19 dB** en 2.8 kHz, así que Hardline calcula la respuesta real de la cadena y ajusta el preamp para que no haya clipping (en el preset base sale -20.5 dB, no los -4 dB habituales en otras guías). Detalles, perfiles por headset y enrutado: [docs/TWEAKS_EXPLAINED.md#audio](docs/TWEAKS_EXPLAINED.md#audio).

### Tu headset

1. **Detectado o elegido de la lista** (6 modelos incluidos): Hardline descarga su corrección medida de [AutoEq](https://github.com/jaakkopasanen/AutoEq) (oratory1990, crinacle, Rtings) y pone encima el preset de pasos. Sin internet, usa el perfil aproximado incluido.
2. **Otro modelo**: escribe el nombre ("Kraken V3", "Arctis Nova Pro") y elige entre los resultados de los ~8800 perfiles de AutoEq.
3. **Manual**: descarga el perfil de [autoeq.app](https://autoeq.app) en formato Equalizer APO y déjalo en la carpeta `headsets\`. Hardline lo detecta y lo ofrece en el menú.

Todo lo descargado se guarda en `headsets\`, así que la próxima vez funciona sin conexión.

## Revertir

```powershell
.\rollback.ps1              # última sesión
.\rollback.ps1 -List        # ver sesiones
.\rollback.ps1 -Stamp 2025-01-15_14-30
```

O usa el restore point de Windows. Si instalaste por `irm | iex`, `rollback.ps1` está en `%LOCALAPPDATA%\Hardline`.

El rollback restaura el valor exacto anterior de cada cambio (registro, servicios, plan de energía, DNS, NIC, QoS, tareas, archivos). No desinstala software: Voicemeeter, VB-CABLE, Equalizer APO y Peace se quitan desde Configuración > Aplicaciones.

## Requisitos

- Windows 10 22H2 o Windows 11
- PowerShell 5.1 (viene con Windows; si lanzas desde PowerShell 7, el script se relanza en 5.1)
- Permisos de administrador
- .NET Framework 4.7.2+ (incluido en Windows 10/11)
- Conexión a internet para el audio (descarga los instaladores oficiales)

## Documentación

- [TWEAKS_EXPLAINED.md](docs/TWEAKS_EXPLAINED.md): qué hace cada cambio y por qué
- [SUPPORTED_HARDWARE.md](docs/SUPPORTED_HARDWARE.md): qué se detecta y qué se ajusta en cada plataforma
- [FAQ.md](docs/FAQ.md): anticheat, rollback, problemas comunes

## Anticheat

Hardline no toca el proceso del juego, no inyecta nada y no modifica archivos del juego. Solo edita la configuración de usuario que el propio juego guarda en `Documentos\Call of Duty\players`, igual que el menú de ajustes. Ver [FAQ](docs/FAQ.md#ricochet).

## Licencia

MIT. Ver [LICENSE](LICENSE).
