# Tweaks explicados

Cada cambio de Hardline, qué hace y por qué está (o no está). El orden sigue el de ejecución.

Convención: **[auto]** lo aplica el script y lo revierte `rollback.ps1`. **[manual]** requiere BIOS, Adrenalin o una decisión tuya; queda en el reporte con instrucciones.

---

## Windows

### Servicios [auto]

Archivo: `src/modules/windows/services.ps1`. Se cambia el valor `Start` de la clave del servicio (2 automático, 3 manual, 4 deshabilitado), no `Set-Service`, para poder restaurar exactamente el valor anterior, incluido el inicio retrasado.

| Servicio | Pasa a | Motivo |
|---|---|---|
| `SysMain` | Deshabilitado | Superfetch. Precarga apps en RAM con I/O de fondo. Con NVMe y 16 GB+ no compensa. |
| `WSearch` | Deshabilitado | Indexador. Reindexa cuando quiere. Inicio sigue encontrando apps; la búsqueda por contenido de archivos se vuelve lenta. |
| `DiagTrack` | Deshabilitado | Telemetría. Subidas periódicas con picos de CPU. |
| `dmwappushservice` | Deshabilitado | Enrutador WAP de la telemetría. |
| `MapsBroker` | Deshabilitado | Mapas offline. |
| `RetailDemo`, `WpcMonSvc`, `Fax` | Deshabilitado | Modo tienda, control parental, fax. |
| `WerSvc`, `PcaSvc` | Manual | Informe de errores y asistente de compatibilidad: solo arrancan si hacen falta. |

Los servicios de Xbox y Steam no están en esta lista: dependen de la plataforma desde la que juegas y se gestionan en [Plataformas de juego](#plataformas-de-juego-auto).

### Plataformas de juego [auto]

Archivo: `src/modules/windows/platforms.ps1`.

Se pregunta desde qué plataforma juegas Warzone (preseleccionada según dónde está `cod.exe`: `steamapps` = Steam, `XboxGames` = Xbox app, resto = Battle.net). Esa no se toca. Para cada otra plataforma instalada, se pregunta si la usas para otros juegos; si no:

| Plataforma | Procesos que se cierran | Arranque automático | Servicios deshabilitados |
|---|---|---|---|
| Battle.net | `Battle.net`, `Agent` (Blizzard Update Agent) | Valores `Run` que apuntan a Battle.net | — |
| Steam | `steam`, `steamwebhelper` (varios procesos, 300-600 MB en total), `steamservice` | Valor `Run` de Steam | `Steam Client Service` |
| Xbox app / Game Pass | `XboxPcApp`, `XboxPcTray`, `GameBar` | Tarea de inicio AppX de la Xbox app | `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`, `GamingServices`, `GamingServicesNet` |

- Nada se desinstala. Battle.net y Steam se siguen abriendo a mano con normalidad.
- **Xbox**: sin esos servicios no arrancan los juegos de Game Pass ni los de la Microsoft Store que usan Xbox Live (Minecraft, Forza...). Si juegas alguno, responde que sí usas la Xbox app. `GamingServices` tiene permisos restringidos en algunas builds; si no se puede modificar, se indica en el reporte.
- **`XboxGipSvc` no se toca**: gestiona los mandos y accesorios de Xbox (firmware, palas del Elite). Solo arranca al conectar un accesorio, así que no ocupa nada si no lo usas.
- En modo `-Unattended` las plataformas secundarias se conservan: cerrar una plataforma que usas para otros juegos no es algo que decidir sin preguntar.
- El rollback restaura servicios y arranque automático.

### Registro [auto]

Archivo: `src/modules/windows/registry.ps1`.

| Cambio | Clave | Por qué |
|---|---|---|
| Game DVR off | `HKCU\System\GameConfigStore\GameDVR_Enabled=0`, `AppCaptureEnabled=0`, política `AllowGameDVR=0` | La captura en segundo plano mantiene un encoder de vídeo activo. |
| Overlay de Game Bar off | `HKCU\Software\Microsoft\GameBar\UseNexusForGameBarEnabled=0` | Win+G y el botón Xbox del mando dejan de abrirlo. |
| Game Mode on | `AutoGameModeEnabled=1` | Desde Win10 2004, Game Mode frena Windows Update y prioriza el proceso en primer plano. Se nota en 1% lows cuando hay actividad de fondo; en reposo es neutro. |
| HAGS off (solo Radeon) | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode=1` | Con RDNA2 y los drivers Adrenalin actuales, HAGS off da frametimes más regulares en Warzone. Requiere reinicio. En NVIDIA e Intel no se toca: su Frame Generation necesita HAGS on y con sus drivers no hay ventaja medible en apagarlo. |
| MMCSS `SystemResponsiveness=10` | `...\Multimedia\SystemProfile` | Reserva de CPU para tareas de baja prioridad cuando hay tareas multimedia: 20% por defecto. [Microsoft documenta](https://learn.microsoft.com/windows/win32/procthread/multimedia-class-scheduler-service) que 0 se trata como 10, así que 10 es el mínimo real. |
| MMCSS tarea `Games` | `GPU Priority=8`, `Priority=6`, `Scheduling Category=High`, `SFIO Priority=High` | Prioridad de la clase "Games" de MMCSS. Efecto pequeño y dependiente de si el juego se registra en MMCSS; se incluye porque no tiene contrapartida. |
| Power Throttling off | `...\Control\Power\PowerThrottling\PowerThrottlingOff=1` | EcoQoS puede aparcar Discord/overlays en núcleos lentos mientras juegas. |
| Widgets, Noticias, Cortana, Bing en Inicio | Políticas en `HKLM\SOFTWARE\Policies\Microsoft\...` | Procesos WebView2 residentes que no aportan nada durante una partida. |
| GPU por ejecutable | `HKCU\Software\Microsoft\DirectX\UserGpuPreferences\<ruta cod.exe>=GpuPreference=2;` | Solo si hay iGPU activa. El 7600X trae iGPU (Radeon Graphics); con varios monitores Windows puede elegir mal. |

Opcionalmente (se pregunta) desinstala los paquetes AppX de Xbox Game Bar y Cortana para el usuario actual. Esto no se revierte desde el manifiesto: se reinstalan desde la Microsoft Store (enlaces en el reporte).

### Plan de energía [auto]

Archivo: `src/modules/windows/power.ps1`.

Duplica la plantilla oculta Ultimate Performance (`e9a42b02-d5df-448d-aa00-03f14749eb61`), la renombra a `Hardline Ultimate Performance` y la activa. Dentro del plan: suspensión selectiva USB off, ASPM de PCIe off, estado mínimo de CPU 100%.

Efecto: los núcleos no se aparcan y la CPU no baja a estados C/P profundos, así que no hay latencia de salida al llegar trabajo. Coste: 10-25 W más en reposo en un Ryzen 7000. El rollback reactiva tu plan anterior y borra el creado.

Nota: AMD recomienda Balanced con el driver de chipset para Ryzen. En la práctica, con Ultimate Performance los 1% lows son iguales o mejores y el consumo en reposo sube.

**Con modo partida** se puede elegir que el plan esté activo **solo con Warzone abierto**: el plan se crea pero no se activa, y el modo partida lo activa al abrir el juego y devuelve tu plan al cerrarlo. Es la opción por defecto si instalas el modo partida.

### Modo partida [auto]

Archivos: `src/modules/windows/gamesession.ps1` (instalación) y `gamesession_watcher.ps1` (proceso residente).

En vez de dejar todo apagado de forma permanente, una tarea al iniciar sesión (`Hardline-GameSession`, con privilegios elevados porque detiene servicios) comprueba cada 5 s si `cod.exe` está abierto.

| Al abrir Warzone | Al cerrarlo |
|---|---|
| Detiene los servicios de `pause_services` **que estuvieran en marcha**: Windows Search, SysMain, Windows Update (`wuauserv`, `UsoSvc`), BITS, Delivery Optimization, cola de impresión | Los vuelve a arrancar |
| Baja a "por debajo de lo normal" la prioridad de `lower_priority`: navegadores, Spotify, OneDrive, launchers. También los que abras durante la partida | Devuelve la prioridad original (comprueba PID + hora de inicio para no tocar un proceso distinto que reutilizó el PID) |
| Cierra `close_processes` (vacío por defecto) | — |
| Activa `Hardline Ultimate Performance` si `power_plan` es true | Vuelve al plan anterior |

- **El juego no se toca**: ni prioridad ni afinidad. El anticheat vigila su proceso y no hay ganancia que justifique el riesgo.
- **Discord** no está en la lista: el chat de voz debe seguir fluido.
- **Configuración**: `config\gamesession.json` (se crea a partir de `src/modules/windows/configs/gamesession.default.json` y las actualizaciones no la pisan). Se relee al empezar cada partida.
- **Registro**: `logs\gamesession.log`, una línea al empezar y otra al terminar.
- **Robustez**: el estado de la partida se guarda en `config\gamesession.state.json`. Si el PC se apaga a mitad de partida, al siguiente inicio de sesión se restaura lo pendiente. El rollback también lo hace antes de quitar la tarea.

### Timer resolution 0.5 ms [auto]

Archivos: `src/modules/windows/timer.ps1`, `timer_resident.ps1`.

El scheduler despierta hilos en múltiplos del periodo del timer global (15.6 ms por defecto; los juegos piden 1 ms). A 0.5 ms, `Sleep()` y las esperas cortas del render thread y los limitadores de FPS por software tienen menos jitter.

- Desde **Windows 10 2004** la resolución es por proceso: lo que pide un proceso de fondo no afecta al juego.
- **Windows 11** añadió `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel\GlobalTimerResolutionRequests=1` para restaurar el comportamiento global. Hardline lo activa y registra una tarea al iniciar sesión (`Hardline-TimerResolution`) que pide 0.5 ms y se queda dormida (0% CPU, ~30 MB RAM).
- En **Windows 10 2004+** esa clave no existe. Hardline no instala la tarea ahí porque no tendría efecto, y lo dice.

El benchmark mide la resolución y el jitter real de `Sleep(1)` antes y después. Si en tu sistema 0.5 ms no mejora frente a 1 ms, edita la tarea y cambia `-Resolution 5000` por `-Resolution 10000`.

Referencia: [timeBeginPeriod](https://learn.microsoft.com/windows/win32/api/timeapi/nf-timeapi-timebeginperiod).

### Latencia DPC [manual]

Ningún tweak de Windows arregla un driver con rutinas DPC lentas. [LatencyMon](https://www.resplendence.com/latencymon) 5 minutos en reposo: si "highest DPC routine execution time" pasa de ~500 µs, la pestaña Drivers dice cuál (típicos: red, audio USB, `amdkmdag.sys`). Se arregla actualizando o cambiando ese driver.

### Latencia avanzada [auto]

Archivo: `src/modules/windows/latency.ps1`. Es la parte de "advanced latency" que venden los servicios de optimización de pago, limitada a lo que tiene efecto medible.

| Cambio | Dónde | Por qué |
|---|---|---|
| **Modo MSI** (Message Signaled Interrupts) | GPU dedicada, tarjetas de red PCIe y controladores USB (xHCI: ratón, teclado, headset USB). Registro: `Enum\<dispositivo>\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties\MSISupported=1` | Con interrupciones por línea (INTx) los dispositivos pueden compartir línea y el driver tiene que averiguar quién interrumpió. Con MSI cada uno escribe la suya: menos latencia ISR/DPC y menos picos. Muchos drivers ya lo activan; Hardline solo lo hace donde el hardware **declara soporte MSI/MSI-X** (`DEVPKEY_PciDevice_InterruptSupport`) y no está ya activo. Requiere reinicio. [Microsoft](https://learn.microsoft.com/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry) |
| **Interrupt Moderation OFF** | Tarjeta de red Ethernet (`*InterruptModeration=0`) | La moderación agrupa paquetes para generar menos interrupciones: ahorra CPU retrasando cada paquete. En juego interesa entregarlos en cuanto llegan. Coste: algo más de uso de CPU en descargas grandes. |
| **RSS ON** | Tarjeta de red (`*RSS=1`) | Reparte el procesamiento de red entre núcleos en lugar de cargarlo todo en uno. |

No se tocan la afinidad ni la prioridad de interrupciones por dispositivo: el efecto es inconsistente entre equipos y un mal ajuste (todo al núcleo 0, que ya atiende la mayoría del sistema) empeora las cosas. Verificación: LatencyMon antes y después del reinicio.

### Experimental [auto, desactivado por defecto]

Archivo: `src/modules/windows/experimental.ps1`. Aparecen en casi todas las guías y packs de pago, pero la evidencia es **débil o mixta**. Hardline los ofrece porque mucha gente los pide, desmarcados por defecto y revertibles. Mide con `-BenchmarkOnly` y LatencyMon; si no notas nada, revierte.

| Tweak | Valor | Qué hace y por qué es dudoso |
|---|---|---|
| `bcdedit disabledynamictick yes` | yes | El kernel deja de saltarse ticks del timer en reposo (ahorro de batería). En escritorio puede dar un timer algo más regular; en muchos equipos no cambia nada medible. **Se salta si hay BitLocker**: cambiar el BCD puede pedir la clave de recuperación al arrancar. |
| `MouseDataQueueSize` / `KeyboardDataQueueSize` | 50 (por defecto 100) | Tamaño del búfer de eventos. Las guías bajan a 16-20 alegando menos input lag; no hay medición fiable de mejora y con ratones de 4000-8000 Hz un búfer tan pequeño puede **perder** eventos. 50 deja margen. |
| `Win32PrioritySeparation` | 0x26 | Quantum corto y variable con boost al primer plano. Es prácticamente lo que Windows cliente ya hace por defecto; se incluye para quien quiera fijarlo explícitamente. |

Lo que Hardline **no** incluye ni como experimental: `useplatformclock` / forzar HPET (empeora la latencia del timer en CPUs modernas), `useplatformtick` (relacionado con más input lag en Win10/11) y desactivar mitigaciones de CPU.

---

## CPU Ryzen [manual]

Archivo: `src/modules/amd/ryzen.ps1`. PBO, Curve Optimizer, SMT y EXPO viven en la BIOS. Ningún script de Windows puede cambiarlos de forma persistente (Ryzen Master usa su propio driver y se pierde al reiniciar), así que Hardline detecta el fabricante de tu placa y te da la ruta exacta de menús.

### PBO + Curve Optimizer -20

PBO en Advanced con límites de placa, Curve Optimizer All Cores Negative 20. CO baja la curva voltaje/frecuencia: a igual voltaje el núcleo boostea más alto, o a igual frecuencia se calienta menos. Un 7600X típico aguanta entre -15 y -30.

Validación, en este orden:

1. Prime95 Small FFTs, 5 minutos como mínimo. Detecta inestabilidad bajo carga.
2. [CoreCycler](https://github.com/sp00n/corecycler), 1 hora. Prueba núcleo a núcleo en boost de un solo hilo, que es donde falla un CO agresivo y donde Prime95 all-core no llega.

Un CO inestable no siempre da pantallazo azul. Síntomas típicos: `DEV ERROR` en Warzone, reinicios en reposo, WHEA 18 en el visor de eventos. Si pasa, sube a -15.

X3D: solo CO (-15 a -20). No subas límites de PBO.

### SMT: se mantiene activo en 6 núcleos

Postura de Hardline: con 6 núcleos **no** se desactiva SMT. Warzone reparte trabajo en más de 8 hilos (render, streaming de texturas, audio, red, anticheat) y con solo 6 hilos lógicos los 1% lows empeoran aunque la media pueda subir un poco. Desactivar SMT solo compensa en CPUs de 12 núcleos o más, y ahí se sugiere probarlo midiendo con CapFrameX.

### Chipset driver

Se comprueba que esté instalado AMD Chipset Software. Incluye el driver PPM/CPPC que decide a qué núcleo van los hilos del juego.

---

## Memoria [manual]

- **EXPO/XMP**: se detecta comparando la velocidad configurada con JEDEC (DDR5 en AM5: 4800-5200 MT/s). Si está inactivo, es la mayor mejora de 1% lows disponible y va lo primero en el reporte.
- **UCLK 1:1**: en AM5, por encima de 6400 MT/s el controlador suele pasar a UCLK = MEMCLK/2 y la latencia sube. 6000-6400 en 1:1 es el punto dulce.
- **Timings**: Windows no los expone. [ZenTimings](https://zentimings.protonrom.com/) los lee del SMU.
- **tRFC**: los perfiles EXPO lo traen holgado (800-1000 ciclos a 6000 MT/s). Conversión: `ns = ciclos × 2000 / MT/s`. En Hynix M/A-die, ~160 ns (480 ciclos a 6000) es un objetivo razonable; en Samsung/Micron empieza en ~220 ns. Valida con TestMem5 (config anta777 absolut) 1 hora.
- **DRAM Calculator for Ryzen** solo cubre DDR4. No sirve para AM5.

---

## GPU

Comprobaciones comunes (`src/modules/gpu/shared.ps1`): antigüedad del driver, estado real de Resizable BAR leyendo la ventana de memoria PCIe de la GPU, y crashes del driver (TDR, evento 4101) de los últimos 14 días.

### NVIDIA [manual]

Archivo: `src/modules/gpu/nvidia.ps1`. La versión del driver se traduce desde la de Windows (`32.0.15.6094` → 560.94).

| Ajuste | Valor | Por qué |
|---|---|---|
| Reflex (en Warzone) | Activado + Boost | Elimina la cola de render entre CPU y GPU. Con Reflex activo, el "Modo de baja latencia" del panel no se usa. |
| Modo de control de energía (cod.exe) | Preferir rendimiento máximo | Evita bajadas de reloj en escenas ligeras que luego cuestan subir. |
| Filtrado de texturas - Calidad | Alto rendimiento | Coste mínimo en imagen. |
| Tamaño de caché del sombreador | 10 GB / Ilimitado | Warzone recompila sombreadores en cada parche; con caché pequeña hay tirones al empezar. |
| V-Sync (panel) | Solo con G-SYNC | G-SYNC + V-Sync en el panel + Reflex limita los FPS por debajo del refresco sin tearing. Sin G-SYNC: desactivado. |
| DLSS Frame Generation | Desactivado | Los frames generados no responden al ratón: más latencia real. |
| Superposición / Repetición instantánea | Desactivadas | Graban o procesan en segundo plano. |

HAGS no se toca en NVIDIA. Undervolt sugerido con la curva de MSI Afterburner (~0.900-0.950 V a tu boost habitual), validado con el contador de TDR.

### Intel Arc [manual]

Archivo: `src/modules/gpu/intel.ps1`. En Arc, **Resizable BAR es obligatorio**: sin él el rendimiento cae a la mitad o menos, así que es lo primero que se comprueba. XeLL en el juego si está disponible, XeSS solo si no llegas a tus FPS, Frame Generation desactivado.

### Radeon

Archivo: `src/modules/amd/gpu.ps1`.

### Detección [auto, solo lectura]

- **Driver**: versión de Adrenalin y antigüedad. Más de 120 días: aviso.
- **SAM / Resizable BAR**: se lee el tamaño real de la ventana de memoria PCIe asignada a la GPU (`Win32_DeviceMemoryAddress`). Sin ReBAR la CPU ve 256 MB de VRAM; con SAM, la VRAM entera. No depende de lo que diga Adrenalin.
- **TDR**: cuenta los eventos 4101 ("el controlador de pantalla dejó de responder") de los últimos 14 días. Útil para validar un undervolt.

### Adrenalin [manual]

AMD no publica una API para cambiar ajustes de Adrenalin. Escribir las claves internas del driver es frágil entre versiones y puede corromper el perfil, así que Hardline no lo hace.

| Ajuste | Valor | Por qué |
|---|---|---|
| AMD Anti-Lag | On | Reduce la cola de frames entre CPU y GPU. Si Warzone muestra **AMD Anti-Lag 2** en su menú, actívalo allí: tiene prioridad sobre el del driver y reduce más porque se integra en el motor. |
| Radeon Chill | Off | Limita FPS dinámicamente según movimiento: latencia variable. |
| Radeon Boost | Off | Baja la resolución al moverte, justo al apuntar. |
| Image Sharpening | 80% | Compensa el suavizado de texturas bajas. No lo combines con FidelityFX CAS del juego: elige uno. |
| Fluid Motion Frames | Off | Interpola frames: más FPS en el contador, más latencia real. |
| Enhanced Sync / Wait for VSync | Off | Añaden cola de frames. |
| Radeon Super Resolution | Off | Upscaling a nivel de driver, peor que FSR in-game. |

### Undervolt [manual, no se aplica nunca]

RX 6650 XT: Adrenalin > Rendimiento > Sintonización > Manual > Sintonización de GPU Avanzada. Frecuencia máxima stock, voltaje **1100 mV** (stock ~1150-1200 mV), límite de potencia al máximo.

Procedimiento: 30 minutos de Warzone + 20 minutos de Time Spy en bucle. Crash o artefactos: +20 mV. Estable: baja de 10 en 10 mV. Vuelve a ejecutar Hardline después: el contador de TDR confirma si es estable.

Resultado esperado: misma frecuencia con menos consumo y temperatura, así que la GPU mantiene el boost más tiempo.

---

## Red

Archivo: `src/modules/network/optimize.ps1`.

Warzone usa **UDP** para el tráfico de juego.

| Cambio | Tipo | Efecto real |
|---|---|---|
| DNS 1.1.1.1 / 1.0.0.1 (+ IPv6 si hay) | auto | No cambia el ping al servidor. Acelera la resolución de nombres del matchmaking y el launcher. Si tenías DNS por DHCP, el rollback lo devuelve a DHCP. |
| EEE / Green Ethernet off | auto | Energy Efficient Ethernet duerme el enlace entre paquetes y añade microlatencia al despertar. Se usan las palabras clave NDIS (`*EEE`) y las propietarias de Intel I225/I226 y Realtek, no los nombres visibles (que van traducidos). |
| TCP autotuning `normal` | auto | Solo se corrige si un tweak antiguo lo dejó en `disabled`. Afecta a descargas, no al ping. |
| QoS DSCP 46 para `cod.exe` | auto | Marca los paquetes del juego como tráfico prioritario (EF). Solo sirve si el router respeta DSCP. Requiere `Do not use NLA=1` en equipos fuera de dominio. |
| Bufferbloat | manual | [Test](https://www.waveform.com/tools/bufferbloat). Nota B o peor: activa SQM (fq_codel/cake) en el router y limita al ~90% del ancho de banda contratado. Es la causa principal de picos de ping cuando otro usa la red. |

### Diagnóstico de red: "registro de balas" [auto, solo lectura]

Archivo: `src/modules/network/diagnose.ps1`. También desde la interfaz o con `install.ps1 -NetDiagOnly`.

El registro de balas lo decide el servidor de Activision: **ningún tweak de Windows lo cambia**, y quien prometa lo contrario vende placebo. Lo que sí depende de ti es lo que le llega al servidor, y eso se mide:

| Medición | Cómo | Qué significa |
|---|---|---|
| Pérdida y jitter **al router** | 100 pings cada 20 ms a la puerta de enlace | Si ya hay pérdida aquí, el problema está en casa: cable, Wi-Fi, router o adaptador. |
| Pérdida y jitter **a Internet** | 100 pings a 1.1.1.1 | Pérdida solo aquí (y no al router) = problema del proveedor. Jitter > ~5 ms se nota en los duelos. |
| **Bufferbloat** | Ping en reposo y durante 10 s de descarga desde speed.cloudflare.com (~100-250 MB) | Cuánto sube el ping cuando la línea está ocupada. Nota A+ a F con la escala de waveform. B o peor: SQM en el router. |
| **MTU** | Ping con "no fragmentar" y búsqueda binaria | 1500 normal, 1492 típico de PPPoE; mucho menos sugiere VPN o túnel. |

El reporte traduce cada medición en un hallazgo con su recomendación concreta.

---

## Warzone

Archivo: `src/modules/game/warzone.ps1`.

El juego guarda la configuración en `Documentos\Call of Duty\players\options.<n>.cod<año>.cst` (y `adv_options.ini` en Warzone 1). Los nombres de los ajustes cambian entre temporadas, así que Hardline:

1. Busca cada ajuste por una lista de nombres candidatos.
2. Solo toca claves que ya existen en tu archivo.
3. Elige el valor según lo que el propio archivo declara como válido (`// one of [Low, Normal, High]` o `// 0 to 4`). Nunca escribe un valor que el juego no acepte.
4. Lista los ajustes que no encontró para que los pongas a mano.

| Ajuste | Valor |
|---|---|
| Texture Resolution, Texture Filter | Normal |
| Particle, Shader, Terrain, Volumetric, Deferred Physics, Shadows, Static Reflections | Mínimo |
| Bullet Impacts, Tessellation, On-Demand Streaming, Water Caustics, Screen Space Shadows, AO, SSR, Weather Grid, DoF, Motion Blur, Film Grain, V-Sync | Off |
| `RendererWorkerCount` | Núcleos físicos (6 en un 7600X) |
| `ConfigCloudStorageEnabled` | Off, para que la copia en la nube no sobrescriba el archivo |

Texturas en Normal y no en Low: con 8 GB de VRAM caben de sobra, y en Low las superficies se vuelven uniformes y cuesta más distinguir siluetas.

Sugeridos, no impuestos: FOV 105-110, ADS FOV Affected, brillo hasta que el logo de calibración sea apenas visible, pantalla completa exclusiva, límite de FPS 3-5 por debajo del refresco si usas FreeSync.

El juego tiene que estar cerrado: al salir reescribe el archivo.

---

## Pantalla

Archivo: `src/modules/windows/display.ps1`.

| Ajuste | Detalle |
|---|---|
| **Refresco al máximo** [auto, revertible] | Compara el refresco activo con el máximo que el driver ofrece a la resolución actual (sin modos entrelazados ni de 16 bits). Si la diferencia es de 5 Hz o más, lo sube con `ChangeDisplaySettingsEx`, probando el modo antes (`CDS_TEST`). El valor anterior queda en el manifiesto. Un monitor de 144 Hz a 60 Hz es el problema más común y el que más se nota: 2,4 veces más imágenes y unos 10 ms menos entre imagen e imagen. |
| **Solo 60 Hz disponibles** | Si el monitor es de más Hz pero el driver solo ofrece 60, el límite es el cable o el puerto: DisplayPort o HDMI 2.0/2.1 conectado a la tarjeta gráfica. |
| **Optimizaciones para juegos en ventana** [auto, Windows 11] | `SwapEffectUpgradeEnable=1` en `HKCU\Software\Microsoft\DirectX\UserGpuPreferences\DirectXUserGlobalSettings`. En ventana sin bordes, el juego usa el modelo de presentación flip, con la misma latencia que pantalla completa. Se conservan las demás claves de esa cadena (Auto HDR, etc.). |
| **VRR en ventana** [auto] | `VRROptimizeEnable=1` en la misma cadena: FreeSync/G-SYNC también para juegos DX11 en ventana. |
| **Límite de FPS** [manual] | Con FreeSync/G-SYNC: refresco - 3 (162 en 165 Hz). Así los FPS no salen del rango VRR: sin tearing y sin la latencia de V-Sync. Con Reflex activo, NVIDIA ya limita por debajo del refresco. |
| **Overlays** [aviso] | Discord, RivaTuner, MSI Afterburner, Overwolf, Medal, overlay de NVIDIA, OBS, Game Bar, Wallpaper Engine. Se inyectan en el juego o compiten por la GPU. Se dice cómo quitar cada uno; no se cierran solos. |

## Medir partida

Archivo: `src/modules/game/gameplay_bench.ps1`.

Mide tu partida real, no un benchmark sintético. Usa [PresentMon](https://github.com/GameTechDev/PresentMon) (Intel, MIT), que lee los eventos ETW de presentación de Windows: no se inyecta ni toca el proceso del juego. Es la misma base que usan CapFrameX y la app de Intel.

1. Espera a que `cod.exe` esté abierto, deja 20 s para entrar en partida y graba 60 s.
2. Calcula FPS medios ponderados por tiempo (frames / segundos), 1% y 0.1% lows (media de los frames más lentos), percentil 99, tirones (frames que tardan más del doble que el típico) y latencia de imagen si el driver la expone.
3. Compara con la medición anterior. Si entre las dos se aplicó Hardline, la comparación es antes/después.
4. Umbrales de ruido: 3 % en FPS medios, 5 % en 1% lows, 8 % en 0.1% lows, 0,3 puntos en tirones. Por debajo es "igual": dos partidas nunca dan lo mismo.

La primera vez descarga PresentMon de su release oficial: comprueba el SHA256 que publica GitHub y la firma digital de Intel, y si algo no cuadra lo borra sin ejecutarlo. Necesita administrador (sesión ETW).

---

## Mando

Archivos: `src/modules/input/controller.ps1` y `controller_test.ps1`.

El retraso de un mando en PC viene, por orden de impacto, de:

| Causa | Qué hace Hardline |
|---|---|
| **Conexión** | Detecta si va por USB, adaptador inalámbrico o Bluetooth. Bluetooth comparte radio con el Wi-Fi y da latencia variable: aviso y recomendación de cable o adaptador oficial. |
| **Capas de remapeo** | DS4Windows, reWASD, x360ce, InputMapper, JoyToKey, DSX y BetterJoy convierten el mando en otro virtual: un salto más. Warzone soporta Xbox, DualSense y DualShock de forma nativa. Aviso si están abiertos; con mandos PlayStation, instrucción para desactivar Steam Input. No se cierran solos: algunos se usan con HidHide para otros juegos. |
| **Ahorro de energía USB** [auto, revertible] | `EnhancedPowerManagementEnabled`, `AllowIdleIrpInD3` y `SelectiveSuspendEnabled` a 0 en `Enum\<dispositivo>\Device Parameters` del mando y de su hub. Evita que Windows suspenda el puerto y el primer input tras una pausa llegue tarde. Efectivo al reconectar o reiniciar. |
| **Ajustes del juego** [auto] | Zona muerta de gatillos 0 (dispara en cuanto tocas), efecto de gatillo del DualSense off (la resistencia retrasa el disparo), vibración off. Mismo editor de `options.*.cst` que la configuración gráfica: solo claves existentes y valores válidos. |
| **Zona muerta de sticks** [medida] | El test mide el drift real en reposo. La zona muerta mínima recomendada es el peor drift + 2 puntos (temperatura, desgaste). Por encima del 15 % de drift el stick está gastado y conviene recalibrarlo o cambiarlo. |

### Test de mando

Dos fases de 5 s, sin cambiar nada:

1. **Reposo**: muestras cada ~1 ms con el mando quieto. Se calcula el radio máximo del stick respecto al centro (decide la zona muerta) y el descentrado medio.
2. **Movimiento**: girando los dos sticks, se registra cada cambio de estado (`dwPacketNumber` en XInput, marca de tiempo del dispositivo en Windows.Gaming.Input). La mediana del intervalo da los Hz reales; el p95 y el máximo dicen si llegan regulares. Un hueco aislado no falsea la cifra.

Mandos Xbox y compatibles se leen por XInput, también desde la interfaz. DualSense/DualShock sin capa XInput se leen por Windows.Gaming.Input, que solo entrega datos a la ventana en primer plano: para ellos usa `install.ps1 -ControllerTestOnly` desde la consola.

Úsalo para comparar: mismo mando por cable, adaptador y Bluetooth, en tu equipo.

---

## Audio

Archivos: `src/audio/`.

### Por qué el preset funciona

- **Pasos**: el golpe del tacón está en 2-3 kHz y la textura de la superficie (grava, metal, madera) en 3-4 kHz. Es además la zona donde el oído humano es más sensible (curvas de igual sonoridad).
- **Explosiones, vehículos, disparos propios**: la energía está por debajo de 500 Hz. Recortar ahí hace que no enmascaren las frecuencias medias-altas.
- **5 kHz**: claves espectrales de la localización (el filtrado del pabellón auditivo).
- **10 kHz**: siseo y agudos fatigantes en sesiones largas.

### Preset base

```
Filter: ON LSC Fc 100 Hz Gain -8 dB Q 0.7     graves / explosiones
Filter: ON PK Fc 180 Hz Gain -6 dB Q 1.2      cuerpo de disparos propios
Filter: ON PK Fc 320 Hz Gain -4 dB Q 1.0      mid-bass
Filter: ON PK Fc 2200 Hz Gain 8 dB Q 1.8      golpe del paso
Filter: ON PK Fc 2800 Hz Gain 9 dB Q 1.6      pasos
Filter: ON PK Fc 3600 Hz Gain 7 dB Q 1.4      textura de superficie
Filter: ON PK Fc 5000 Hz Gain 3 dB Q 1.0      localización
Filter: ON HSC Fc 10000 Hz Gain -3 dB Q 0.8   siseo
```

Dos detalles que suelen salir mal en los presets que circulan:

1. **El corte de graves es `LSC` (shelf bajo), no `HSC`.** Un `HSC` a 100 Hz con -8 dB atenúa todo lo que hay *por encima* de 100 Hz: bajaría los pasos en vez de las explosiones.
2. **El preamp se calcula.** Los tres realces se solapan: en 2.8 kHz la cadena suma **+19 dB**, no +9. Con un preamp de -4 dB, cualquier explosión cercana clipea (distorsión digital) justo cuando necesitas oír pasos. `src/audio/eq.ps1` reproduce los biquads de Equalizer APO (fórmulas RBJ Audio EQ Cookbook a 48 kHz), calcula la respuesta combinada y fija `preamp = -(pico) - 1 dB`. Preset base: **-20.5 dB**. Sube el volumen de Windows para compensar; el resultado no distorsiona.

Intensidad **moderada** (70%): mismas frecuencias y Q, 30% menos de ganancia. Pico +13.3 dB. Menos sonido "metálico", sigue destacando pasos.

### Perfiles por headset

`src/audio/profiles/headsets.json`. El preset base asume un cerrado de respuesta más o menos neutra; cada modelo corrige su firma conocida:

| Headset | Driver | Impedancia | Ajuste |
|---|---|---|---|
| HyperX Cloud II | 53 mm | 60 Ω | Graves amplios y agudos algo adelantados: más recorte abajo, menos realce en 3.6k/5k. +2 dB de makeup por la impedancia. |
| Logitech G Pro X | 50 mm | 35 Ω | Graves marcados, agudos apagados: más recorte en 100/180 Hz, más energía en 3.6k/5k. |
| SteelSeries Arctis 7 | 40 mm | 32 Ω | Equilibrado con valle en 3-5 kHz: menos recorte abajo, realce de presencia más ancho. |
| Razer BlackShark V2 | 50 mm | 32 Ω | Ya brillante y orientado a FPS: menos realce arriba, más recorte en 10 kHz para evitar sibilancia. |
| Corsair HS80 | 50 mm | 32 Ω | Cálido y oscuro: el mayor recorte de graves y más realce arriba. |
| Astro A40 TR | 40 mm | 48 Ω | Abierto, pocos graves: menos recorte abajo y realce moderado para conservar la escena del diseño abierto. |

Son ajustes orientativos a partir de la firma conocida de cada modelo. Se usan solo como respaldo sin internet: lo normal es la corrección medida de AutoEq (abajo).

### Corrección medida (AutoEq)

Archivo: `src/audio/autoeq.ps1`.

[AutoEq](https://github.com/jaakkopasanen/AutoEq) publica perfiles de Equalizer APO para ~8800 auriculares, calculados a partir de mediciones en laboratorio (oratory1990, crinacle, Rtings...). Cada perfil lleva ese modelo a una respuesta neutra (target Harman). La cadena final es:

```
corrección AutoEq (tu headset -> neutro)  +  preset de pasos base (neutro -> Warzone)
```

Así el preset de pasos hace lo mismo en cualquier headset, en lugar de depender de lo que ya realce o apague de fábrica.

- Búsqueda por palabras sobre el índice de AutoEq (cacheado 7 días en `headsets\.cache`). Orden: coincidencia exacta, over-ear antes que in-ear, y fuente (oratory1990 > crinacle > Rtings > Filk > resto).
- Si Windows expone el modelo en el nombre del dispositivo ("Auriculares (Razer Kraken V3)"), se usa como búsqueda sugerida.
- El perfil descargado se guarda en `headsets\<modelo> (<fuente>).txt`. La siguiente vez se usa sin conexión.
- **Manual**: cualquier archivo de Equalizer APO con líneas `Filter: ON PK|LSC|HSC ...` en `headsets\` aparece en el menú. Sirve el `ParametricEQ.txt` de AutoEq o lo que exporta [autoeq.app](https://autoeq.app) eligiendo Equalizer APO.
- El preamp del archivo se ignora: se recalcula con la cadena completa. Con corrección + pasos el pico suele quedar entre +20 y +25 dB, así que el preamp baja a -21/-26 dB. Compensa con el volumen; no hay clipping.
- Los parámetros de Voicemeeter (makeup por impedancia) se heredan del perfil incluido si tu modelo es uno de los 6.

### Audio anterior: limpieza antes de instalar

Archivo: `src/audio/cleanup.ps1`.

| Qué se busca | Qué se hace |
|---|---|
| `config.txt` de Equalizer APO que no es de Hardline | Todo lo que no es de serie ni de Hardline se aparta a `config\antes_de_hardline\` (también lo que incluía el `config.txt` anterior). Copia en el backup de la sesión: el rollback lo devuelve. |
| Equalizer APO activo en varios dispositivos | Se leen los efectos de cada dispositivo (`MMDevices\Audio\Render\*\FxProperties`, CLSID de Equalizer APO). Antes del Configurator se dice cuál dejar: CABLE Input en modo Completo, el headset en Solo EQ. |
| Presets antiguos de Hardline | Se apartan los `warzone_footsteps_*.txt` que no son el actual. |
| Peace, FxSound, Boom 3D, ViPER4Windows, Razer Surround | Sin arranque automático (revertible). Desinstalación con su propio desinstalador: silenciosa si el programa lo permite (MSI o `QuietUninstallString`), si no se abre el suyo. Se confirma programa a programa; en modo desatendido solo con `-CleanAudio`. No se puede revertir. |
| Nahimic | Servicio `NahimicService` desactivado (revertible). |
| SteelSeries Sonar, Dolby Atmos, DTS | Van dentro de otras apps: instrucciones en la guía de pasos. |
| VB-CABLE o Voicemeeter renombrados por otro programa ("Art Tune +", "Virtual Mix") | Vuelven a "CABLE Input" / "CABLE Output" y "Voicemeeter Input" / "Voicemeeter Output" con IMMDevice/IPropertyStore (lo mismo que Cambiar nombre en Configuración > Sonido). Revertible. Voicemeeter se reabre para leer los nombres nuevos. |
| Art Tune | No tiene desinstalador en Aplicaciones: se busca su rastro y se aparta entero a `backups\<sesión>\apartado\` (revertible): `config\ArtTuneDB`, sus copias `config\_backup_*`, `ProgramData\ArtTune` (iconos), el VST `VSTPlugins\ArtTuneKit`, LEQ Control Panel y los accesos directos. Los iconos de VB-CABLE que apuntaban a `ProgramData\ArtTune` vuelven a los del driver. ReaPlugs (VST de la cadena "Art Tune +") se ofrece desinstalar solo si hay rastro de Art Tune. Las copias que Art Tune guardó en Documentos y Descargas son tuyas: solo se listan. Si algo está en uso (un VST cargado por Equalizer APO), se deja `config.txt` neutro, se reinicia el audio de Windows y se reintenta. |
| HeSuVi | Virtualizador surround dentro de Equalizer APO. Sin la opción `-HeSuVi`, se aparta entero (`config\HeSuVi` y su acceso directo, revertible) porque apilado sobre el HRTF de Warzone destruye la localización. Con `-HeSuVi` se conserva e integra (ver sección). |
| Entradas de Aplicaciones sin programa (p. ej. Peace borrado a mano) | Solo si la entrada apunta a un `.exe` que ya no existe (RunDll32, msiexec o rutas raras cuentan como instaladas). Se exporta la clave con `reg export` y se borra; el rollback la importa. |
| Sound Blaster (Acoustic Engine / Command) | Aviso: apagar SBX, Crystalizer, Smart Volume y su EQ. No se desinstala (es el software de la tarjeta). |
| Voicemeeter Banana o Standard | Se instala Potato encima: mismo programa y desinstalador; solo Potato expone el compresor completo. |

### HeSuVi: 7.1 virtual opcional

Archivo: `src/audio/hesuvi.ps1`. Parámetro `-HeSuVi` (casilla en la interfaz, default No).

**Qué es.** HeSuVi (Headphone Surround Virtualization, [SourceForge](https://sourceforge.net/projects/hesuvi/)) convoluciona los 8 canales de un flujo 7.1 con respuestas al impulso binaurales (HRIR/HRTF) dentro de Equalizer APO, y saca estéreo para audífonos normales. Es lo que hacía por hardware una tarjeta USB 7.1: sirve para oír de dónde vienen los pasos (adelante/atrás/arriba/abajo), no para que suenen más claros (eso lo hace el EQ).

**Cómo funciona el HRTF (resumen).** Tu cerebro localiza un sonido por tres pistas: diferencia de tiempo entre oídos (ITD), diferencia de volumen (ILD) y el filtrado del pabellón auditivo según el ángulo (HRTF). Un impulso grabado con micrófonos en oídos artificiales (HRIR) captura las tres. HeSuVi aplica un HRIR distinto por cada uno de los 7.1 canales y mezcla el resultado a 2 canales: tus audífonos estéreo reciben una señal que el cerebro interpreta como envolvente.

**Requisitos (los pone la guía de pasos al instalar).**
1. Equalizer APO instalado (Hardline lo instala primero si falta).
2. Dispositivo de Windows configurado en **7.1 Surround** (Panel de sonido > tu headset > Configurar). Si tu tarjeta no lo permite, en HeSuVi > Additional > Matrix Upmix: Stereo y 5.1 activados.
3. Warzone con salida **7.1 / home theater** (NO la mezcla "Auriculares"): HeSuVi necesita los 8 canales; con mezcla estéreo no hay nada que virtualizar.
4. En la interfaz de HeSuVi, elegir un perfil HRIR (prueba `ooyh_0`) y Actions > Restart Audio Service.
5. "Audio espacial" de Windows (Sonic/Dolby) y el 7.1 del software del headset, **apagados**: no se apilan virtualizadores.

**Integración con el EQ de Hardline.** El `config.txt` queda así (orden: pre, HeSuVi, EQ):

```
Include: HeSuVi\hesuvi.txt
Include: hardline\switch.txt
```

La convolución va primero y el EQ de pasos después: el atajo Ctrl+Alt+F10 (y el panel del EQ) enciende/apaga solo el EQ sin perder la virtualización. Combinación recomendada: **Solo EQ + HeSuVi** (directo al headset, sin la latencia de Voicemeeter). Con modo Completo también funciona si Equalizer APO apunta al headset final, pero es configuración avanzada.

**Seguridad de la descarga.** `HeSuVi_2.0.0.1.exe` desde el proyecto oficial de SourceForge con SHA256 fijado en el código (fail-closed: si no coincide no se ejecuta nada) y verificación de firma Authenticode cuando el binario la trae. La instalación queda registrada como `Info` en el manifiesto (el rollback no desinstala software, igual que Voicemeeter/VB-CABLE).

### Compresor y gate (modo Completo)

**Ajuste al preamp del EQ.** El EQ baja todo el audio (preamp calculado, hasta -20 dB) para que los realces no saturen. Los umbrales del gate y del compresor se desplazan lo mismo; sin esto, el gate se cerraba con los pasos lejanos. Parte de la pérdida se recupera con la ganancia de salida del compresor y un limitador evita saturar.

| Perfil | Gate | Compresor | Ganancia | Limitador |
|---|---|---|---|---|
| Normal | -45 dB + preamp, atenúa 20 dB | 4:1 desde -25 dB + preamp, ataque 5 ms | makeup + la mitad del preamp | -3 dB |
| Pasos al máximo | Desactivado | 8:1 desde -20 dB + preamp, ataque 1 ms, release 50 ms | 4 dB - preamp (hasta +24) | -6 dB |

"Pasos al máximo" baja lo fuerte y sube lo flojo: con preamp -20, un disparo a -20 dBFS sale a unos -14 y un paso a -55 sale a unos -31, cuando antes los separaban 35 dB. Se cambia al momento desde el panel del EQ.


Voicemeeter Potato, configurado por su [Remote API](https://github.com/vburel2018/Voicemeeter-SDK) (no se edita ningún archivo interno de Voicemeeter).

| Parámetro | Valor | Por qué |
|---|---|---|
| Gate | -45 dB | Solo corta ruido de fondo. Más alto se come los pasos lejanos. |
| Ratio | 4:1 | Picos (explosiones, disparos propios) bajan de forma notable sin aplastar la mezcla. |
| Threshold | -25 dB | Pasos y recargas suelen quedar por debajo: no se comprimen. |
| Attack | 5 ms | Deja pasar el transitorio del paso antes de comprimir. |
| Release | 80 ms | Recupera ganancia antes del siguiente paso (cada 350-500 ms al correr). |
| Makeup | +6 dB | Sube todo lo que no es pico. Neto: pasos más altos, explosiones más bajas. |

### Enrutado

```
cod.exe  ->  CABLE Input  [Equalizer APO]  ->  CABLE Output  ->  Voicemeeter Strip 1 [Gate + Comp]  ->  A1 (headset)
Discord, navegador, sistema  ->  Voicemeeter Input  ->  Strip 6  ->  A1 (headset, sin procesar)
```

- El juego entra por una strip de **hardware** porque en Voicemeeter solo esas tienen Gate y Compresor.
- El EQ se instala en `CABLE Input`, así que solo afecta al juego. Discord y el resto suenan normal.
- Coste: Voicemeeter añade 10-20 ms de latencia de audio. Si no la quieres, modo **Solo EQ**: el EQ va directo al headset, sin Voicemeeter ni VB-CABLE.

Pasos que el script no puede hacer por ti (Windows no tiene API pública para el enrutado por aplicación):

1. Configuración > Sistema > Sonido > Salida: `Voicemeeter Input`.
2. Con Warzone abierto: Mezclador de volumen > `cod.exe` > Salida: `CABLE Input`.
3. En el Configurator de Equalizer APO, marca solo el dispositivo que indica el script.
4. Desactiva "Audio espacial" de Windows (Sonic/Dolby) y "Mejoras de audio" en el headset, y el 7.1 virtual del software del fabricante. No se apilan virtualizadores (con HeSuVi instalado por Hardline, este paso ya lo cubre la guía).
5. En Warzone: mezcla de audio "Auriculares" (o salida 7.1 / home theater si usas HeSuVi), música y diálogos a 0.

### Atajo EQ on/off y test de pasos [auto]

Archivos: `src/audio/eqswitch.ps1`, `eq_toggle.ps1`, `eq_toggle.vbs`, `footstep_test.ps1`.

- **Cadena**: `config.txt` → `hardline\switch.txt` → preset. Encender/apagar solo comenta o descomenta la línea de `switch.txt`; Equalizer APO recarga al instante. La instalación da permiso de escritura al usuario sobre `config\hardline` (queda en el manifiesto y el rollback lo retira), así que el atajo no pide admin.
- **Panel del EQ** (`src/gui/eq_panel.ps1`): ventana sin administrador que lee y escribe el mismo `switch.txt` que el atajo. Encender/apagar comenta o descomenta el `Include`; la intensidad cambia el preset al que apunta (`warzone_footsteps_<headset>.txt` completo o `_70.txt` moderado, los dos se escriben al instalar). Relee el estado cada segundo.
- **Atajo**: `Ctrl+Alt+F10`, desde un acceso directo en Inicio > Hardline (Windows solo atiende atajos de accesos directos del menú Inicio o el escritorio). Se lanza vía `wscript` sin ventana: una consola, aunque sea un instante, puede quitar el foco al juego en pantalla completa exclusiva. Confirmación por sonido: un pitido agudo = encendido, dos graves = apagado. No se usa `Ctrl+Alt+letra` porque en teclados españoles equivale a AltGr (Ctrl+Alt+E = €).
- **Test de pasos**: genera una escena sintética de 5 s (4 pasos lejanos a la izquierda, una explosión cercana, 2 pasos más justo después) y la reproduce dos veces por el mismo dispositivo que usa el juego (`CABLE Input` en modo Completo), primero con el EQ apagado y luego encendido. Al terminar deja el EQ como estaba. No usa grabaciones de terceros.

---

## Lo que Hardline NO hace

| Tweak popular | Por qué no |
|---|---|
| `TcpAckFrequency`, `TCPNoDelay`, desactivar Nagle | Solo afectan a TCP. El tráfico de juego de Warzone es UDP. |
| `NetworkThrottlingIndex=0xFFFFFFFF` | Limita paquetes no multimedia cuando hay reproducción MMCSS activa. Sin efecto medible en el ping de juego. |
| `Win32PrioritySeparation` a valores exóticos | El valor por defecto en cliente ya da quantum corto variable con boost al primer plano. (0x26 está disponible como experimental.) |
| Prometer "mejor registro de balas" | El registro lo decide el servidor. Hardline mide y corrige lo que depende de ti: pérdida, jitter y bufferbloat. |
| `useplatformclock` / forzar HPET, `useplatformtick` | Empeoran la latencia del timer en CPUs modernas. |
| Desactivar Spectre/Meltdown | Hueco de seguridad real a cambio de una ganancia que en Zen 4 es mínima. |
| Desactivar Defender o Windows Update | Seguridad. Game Mode ya frena Update durante la partida. |
| Deshabilitar Xbox services a ciegas | Rompe Game Pass y los juegos de la Store. Hardline solo lo hace si eliges otra plataforma y confirmas que no usas la Xbox app. |
| "Limpiadores" de RAM | Windows gestiona la standby list. Vaciarla obliga a releer de disco. |
| Aplicar ajustes de BIOS o Adrenalin | No hay API pública y fiable. Hacerlo mal deja la placa o el driver en estado inconsistente. Se dan instrucciones exactas. |
| "Overclock" del sondeo USB del mando (hidusbf y similares) | Exige un driver sin firmar o el modo de prueba de Windows. Riesgo con el anticheat y con Secure Boot. El test de mando mide la tasa real para que compares conexiones. |
| Ajustes de prioridad del proceso del juego | El anticheat vigila modificaciones al proceso. No merece el riesgo. |
