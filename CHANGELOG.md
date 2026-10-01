# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado [SemVer](https://semver.org/lang/es/).

## [1.10.1] - 2026-10-01

### Cambiado

- **Actualizar sin cerrar la interfaz**: el botón descarga y verifica la versión nueva en segundo plano, con el progreso en el panel de salida. Las acciones (Aplicar, Benchmark, Medir partida...) usan la versión nueva al momento; la ventana se renueva la próxima vez que se abra. `install.ps1 -UpdateOnly` hace lo mismo en consola.
- La interfaz vuelve a comprobar si hay versión nueva cada 30 minutos mientras está abierta.

## [1.10.0] - 2026-10-01

### Añadido

- **Perfil de compresor "Pasos al máximo"**: compresor 8:1 con ataque de 1 ms, ganancia de compensación alta, limitador y sin puerta de ruido. Lo fuerte (tus disparos, explosiones, granadas) baja casi al instante; lo flojo (pasos, recargas, equipo) sube mucho. Se elige en la interfaz (`-AudioDynamics pasos` en consola) y se cambia al momento desde el **panel del EQ**, con Voicemeeter abierto y sin reinstalar.
- `config\audio.json` guarda el perfil, el preamp real del EQ y los ajustes del headset. Al volver a aplicar se mantiene lo elegido.

### Corregido

- **Pasos con poco volumen**: el EQ baja todo el audio (preamp de hasta -20 dB) para no saturar, pero el gate y el compresor de Voicemeeter estaban calibrados para audio sin EQ. El gate cortaba los pasos lejanos y el compresor casi no actuaba. Ahora los umbrales se desplazan con el preamp real, la ganancia se recupera, un limitador evita saturar y el gate atenúa en lugar de silenciar.

## [1.9.1] - 2026-10-01

### Corregido

- **Voicemeeter configurado con la salida equivocada** al aplicar desde la interfaz: sin nadie que contestara, se usaba la primera salida de la lista (a menudo el HDMI del monitor). Ahora la interfaz tiene el selector **"Salida del headset (Voicemeeter A1)"** (`-AudioDevice` en consola). En "Automática" manda el headset detectado y después la salida predeterminada de Windows; las salidas de monitor (HDMI / DisplayPort) quedan las últimas. La salida elegida se muestra en la salida del proceso.

## [1.9.0] - 2026-10-01

### Añadido

- **Botón Actualizar** en la interfaz: al abrirla se comprueba en segundo plano si hay versión nueva; si la hay, aparece "Actualizar a vX". Descarga la release con SHA256 verificado encima de la instalación (backups, reportes, mediciones, perfiles y guía se conservan) y vuelve a abrir la interfaz.
- `install.ps1 -Update`: lo mismo desde la consola, también ejecutado desde la copia local.

## [1.8.3] - 2026-10-01

### Añadido

- **Nombres de VB-CABLE restaurados**: si otro programa los renombró ("Art Tune +", "Art Tune Unified Output"), vuelven a llamarse "CABLE Input" y "CABLE Output" con la API de audio de Windows. El rollback devuelve el nombre anterior. Así coinciden las instrucciones y Voicemeeter encuentra el cable.
- **Art Tune** detectado como audio anterior (arranque automático fuera y desinstalación ofrecida).
- **Sound Blaster** (Acoustic Engine / Command / Connect): aviso para apagar sus efectos.

### Corregido

- Voicemeeter básico y Banana: la entrada virtual (sistema) estaba fijada a la de Potato y no se configuraba. Ahora se usa la de cada edición.

## [1.8.2] - 2026-10-01

### Corregido

- **Ventana "Hardline: configurando Voicemeeter..." colgada al iniciar Windows**: intentaba abrir siempre Voicemeeter Potato aunque la edición instalada fuera otra, y las llamadas a Voicemeeter no tenían tiempo límite. Ahora abre la edición que tengas, la configuración va en un proceso aparte con 90 s como máximo, la ventana dice qué está haciendo y se cierra sola.

## [1.8.1] - 2026-10-01

### Corregido

- **Guía de pasos vacía** ("Los tipos de argumentos no coinciden"): recorrer la lista de pasos manuales con `foreach (... in @($lista))` falla en PowerShell cuando la lista es `List[object]`. La guía vuelve a mostrar todos los pasos; los pasos vacíos se descartan.
- **Voicemeeter no se instalaba** si ya estaba abierto: se cierra antes de instalar, se prueba winget como alternativa y el éxito se comprueba porque Potato quede instalado (no por el código de salida). Si falla y ya hay otra edición, se sigue con ella y se explica cómo instalar Potato.
- **Aviso falso de Equalizer APO en dos dispositivos** cuando CABLE Input tiene otro nombre en Windows (p. ej. "Art Tune +"): se reconoce por el nombre del driver.
- **Interfaz que no abre**: ahora muestra el motivo en un aviso y lo guarda en `logs\gui_error.log` en lugar de cerrarse sin decir nada.

## [1.8.0] - 2026-10-01

### Añadido

- **Panel del EQ** (Inicio > Hardline > Hardline EQ, o botón "Panel del EQ" en la interfaz): estado encendido/apagado, botón para cambiarlo, intensidad Completa o Moderada al momento y acceso al test de pasos. Sin administrador. Refleja el atajo `Ctrl+Alt+F10` si lo usas en partida. Opción "Siempre visible".
- La instalación deja escritas las dos intensidades del preset (`warzone_footsteps_<headset>.txt` y `_70.txt`), así que cambiar de una a otra no requiere volver a instalar.

## [1.7.0] - 2026-10-01

### Añadido

- **Limpieza del audio anterior** antes de instalar, para que no queden dos cadenas de EQ compitiendo:
  - Equalizer APO con configuración propia (tuya, de Peace, de AutoEq): sus archivos se apartan a `config\antes_de_hardline\`. El rollback los devuelve.
  - Equalizer APO activo en varios dispositivos: se avisa de cuáles desmarcar en el Configurator (en modo Completo el EQ se aplicaría dos veces).
  - Presets antiguos de Hardline de otro headset o intensidad.
  - Peace, FxSound, Boom 3D, ViPER4Windows y Razer Surround: se quita su arranque automático y se desinstalan con su propio desinstalador (confirmando programa a programa, o `-CleanAudio` / casilla en la interfaz).
  - Nahimic: su servicio se desactiva (revertible). SteelSeries Sonar, Dolby y DTS: paso a paso en la guía.
  - Voicemeeter Banana o Standard: se instala Potato encima, que es la que tiene el compresor completo.

### Cambiado

- Peace ya no se ofrece durante la instalación: al guardar reescribe `config.txt` y pisa el preset de Hardline.

## [1.6.0] - 2026-10-01

### Añadido

- **Guía de pasos manuales**: lo que Hardline no puede hacer por ti, ordenado por fases (Windows, Warzone, panel de la GPU, red, BIOS, avanzado, comprobar), de lo que más se nota y menos cuesta a lo avanzado.
  - Página `reports\guia.html` con casillas, barra de progreso y el siguiente paso resaltado. Se abre sola al terminar y tiene acceso directo en Inicio > Hardline > Guía de pasos.
  - Interfaz: al aplicar se abre un asistente que muestra un paso cada vez (Hecho, Saltar, Anterior, abrir enlace). También con el botón "Guía de pasos".
  - Consola: al terminar pregunta si quieres que te guíe ahí mismo, paso a paso.
  - El progreso se guarda (`config\guide_state.json`) y se conserva al volver a aplicar.

### Cambiado

- El reporte enlaza a la guía desde su sección de pasos manuales.

## [1.5.0] - 2026-10-01

Enfocada en lo que se nota al jugar y en poder demostrarlo.

### Añadido

- **Medir partida**: mide 60 s de tu partida real de Warzone con PresentMon (Intel): FPS medios, 1% y 0.1% lows, tirones y latencia de imagen si el driver la da. Cada medición se compara con la anterior; si entre medio aplicaste Hardline, es antes/después, con veredicto que separa una mejora real del ruido entre partidas. Reporte HTML. PresentMon se descarga de su release oficial y se comprueban el SHA256 de GitHub y la firma de Intel antes de ejecutarlo. Botón en la interfaz y `-GameplayBenchOnly`.
- **Pantalla**: detecta monitores funcionando por debajo de su refresco máximo (el típico 144 Hz a 60 Hz) y los sube, probando el modo antes de aplicarlo; revertible. Optimizaciones para juegos en ventana (Windows 11) y VRR en ventana. Límite de FPS recomendado para FreeSync/G-SYNC calculado con tu refresco. `-SkipDisplay`.
- **Overlays**: avisa de Discord, RivaTuner, MSI Afterburner, Overwolf, Medal, overlay de NVIDIA, OBS, Game Bar y Wallpaper Engine en ejecución, con cómo quitar cada uno.
- **Warzone**: la opción de baja latencia de tu GPU en el propio juego (NVIDIA Reflex + Boost, AMD Anti-Lag 2 o Intel XeLL) y pantalla completa exclusiva, si tu archivo de configuración las tiene.

## [1.4.0] - 2026-10-01

### Añadido

- **Mando**: detecta los mandos conectados (Xbox, DualSense, DualShock, 8BitDo, PowerA, SCUF, Razer y otros) y su conexión. Por USB desactiva el ahorro de energía del mando y de su hub (revertible); por Bluetooth avisa de la latencia añadida. Avisa si DS4Windows, reWASD, x360ce, InputMapper, DSX u otras capas de remapeo están en ejecución, y de Steam Input con mandos PlayStation. En Warzone: zona muerta de gatillos 0, efecto de gatillo y vibración desactivados. `-SkipController`.
- **Test de mando**: mide el drift real de cada stick en reposo y recomienda la zona muerta mínima para Warzone; mide la tasa de actualización real (Hz) y la regularidad de los intervalos para comparar cable, adaptador y Bluetooth. No cambia nada. Botón en la interfaz y `-ControllerTestOnly`.

## [1.3.0] - 2026-10-01

### Añadido

- **Interfaz gráfica** (WPF, sin instalar nada): módulos en casillas, opciones de plataforma/headset/audio, botones Simular, Aplicar, Revertir, Diagnóstico de red, Benchmark y Test de pasos, salida en directo. Ejecuta el mismo `install.ps1` que la consola. Acceso directo en Inicio > Hardline y parámetro `-Gui`.
- **Latencia avanzada**: modo MSI de interrupciones para GPU, tarjeta de red y controladores USB, solo donde el hardware declara soporte MSI/MSI-X; Interrupt Moderation off y RSS on en la NIC. `-SkipLatency`.
- **Diagnóstico de red** ("registro de balas"): pérdida y jitter al router y a Internet por separado, bufferbloat bajo carga con nota A+ a F, MTU real; hallazgos con recomendación en el reporte. `-NetDiagOnly`, `-SkipNetDiag`.
- **Tweaks experimentales** (desmarcados por defecto): `disabledynamictick` (se salta con BitLocker), colas de ratón/teclado, `Win32PrioritySeparation`. `-Experimental`.
- `-EqIntensity` y `-DisableOtherPlatforms` para uso sin preguntas (los usa la interfaz).
- CI: la ventana de la interfaz se construye en Windows real en cada push.

## [1.2.0] - 2026-10-01

### Añadido

- **Releases verificadas**: el instalador descarga la última release publicada y comprueba su SHA256 antes de ejecutar nada; si no coincide, cancela. `-Channel main` para lo último de la rama. Aviso al arrancar si hay una versión nueva.
- **Modo partida**: tarea al iniciar sesión que, solo con Warzone abierto, pausa servicios de fondo, baja la prioridad de navegadores/launchers y activa el plan de energía máximo; al cerrar el juego lo restaura todo. Configurable en `config\gamesession.json`, recuperación tras apagón, registro en `logs\gamesession.log`. Parámetro `-GameSession`.
- **Plan de energía solo durante la partida** (opción por defecto con modo partida).
- **Menú de módulos** al inicio para elegir qué aplicar. `-SkipPlatforms`.
- **Atajo `Ctrl+Alt+F10`** para encender/apagar el EQ en partida, sin admin ni ventanas, con confirmación por sonido.
- **Test de pasos**: escena sintética (pasos + explosión) reproducida con el EQ apagado y encendido por el dispositivo del juego.
- **Módulos NVIDIA e Intel Arc**: driver (versión GeForce real), Resizable BAR, TDR e instrucciones de Reflex / panel de NVIDIA / XeLL.
- **Reporte HTML** con resumen, antes/después, pasos manuales enlazados y detalle (el `.txt` se mantiene).
- README en inglés, plantillas de issues y PR, CONTRIBUTING y Dependabot para las acciones del CI.

### Cambiado

- HAGS solo se desactiva en Radeon; en NVIDIA e Intel no se toca (Frame Generation lo necesita).
- Las actualizaciones conservan `config\` además de `backups\`, `reports\`, `logs\` y `headsets\`.

## [1.1.0] - 2026-09-29

### Añadido

- Selección de plataforma (Battle.net, Steam, Xbox app). Las plataformas instaladas que no usas: procesos cerrados, arranque automático quitado (claves `Run` y tarea AppX) y servicios deshabilitados (Xbox Live, Gaming Services, Steam Client Service). `XboxGipSvc` se conserva para los mandos. Parámetro `-Platform`.
- Corrección medida por headset desde AutoEq (~8800 modelos): búsqueda por nombre, mejor fuente primero, descarga a `headsets\` para uso sin conexión. Cadena final: corrección + preset de pasos base, con preamp recalculado sobre todo.
- Carpeta `headsets\` para perfiles propios (ParametricEQ de AutoEq o exportación de autoeq.app).
- `-Headset` acepta un modelo libre (`-Headset "Kraken V3"`) o un archivo de `headsets\`.

### Cambiado

- Los perfiles de `headsets.json` quedan como respaldo sin internet.

## [1.0.0] - 2026-09-29

Primera versión.

### Añadido

- Instalador en una línea (`irm | iex`) con elevación UAC automática, relanzado en Windows PowerShell 5.1 y descarga del repo a `%LOCALAPPDATA%\Hardline`.
- Restore point antes de cualquier cambio (se levanta temporalmente el límite de uno cada 24 h).
- Manifiesto de cambios por sesión con el valor anterior exacto y `rollback.ps1` que lo revierte en orden inverso.
- Detección de hardware por CIM: CPU y reloj efectivo, VRAM real (> 4 GB), SAM/ReBAR por la ventana PCIe, EXPO/XMP, NVMe, placa, headset, red y ruta de `cod.exe` (Battle.net, Steam, Game Pass).
- Windows: servicios, Game DVR off, Game Mode on, HAGS off, MMCSS, Power Throttling off, widgets/Cortana, GPU preferida para `cod.exe` con iGPU presente.
- Plan Ultimate Performance con USB selective suspend y ASPM off.
- Timer resolution 0.5 ms en Windows 11 (tarea residente + `GlobalTimerResolutionRequests`).
- Ryzen: rutas de BIOS por fabricante para PBO, Curve Optimizer, SMT y EXPO; comprobación de chipset driver; guía de tRFC.
- Radeon: antigüedad del driver, SAM, conteo de TDR, instrucciones de Adrenalin y undervolt.
- Red: DNS Cloudflare con restauración a DHCP, EEE/Green Ethernet off por palabra clave NDIS, autotuning, QoS DSCP 46.
- Warzone: editor de `options.*.cst` que valida contra los rangos del propio archivo; `adv_options.ini` desde plantilla.
- Audio: 7 perfiles de headset, preamp calculado a partir de la respuesta real de los biquads, intensidad completa/moderada, instalación de Equalizer APO, VB-CABLE, Voicemeeter Potato (hash SHA256 fijado) y Peace; configuración de Voicemeeter por Remote API.
- Benchmark pre/post: resolución del timer, jitter de `Sleep(1)`, ping y jitter, DNS, lectura de capturas de CapFrameX.
- Reporte en `reports/` con cambios, pasos manuales, benchmark y cómo revertir.
- `tests/validate.ps1` y workflow de CI/release.

### Corregido respecto al preset de audio original

- El corte de graves a 100 Hz pasa de `HSC` a `LSC`. Un shelf alto a 100 Hz recortaba todo lo que hay por encima, pasos incluidos.
- Preamp de -4 dB a calculado (-20.5 dB en el preset base): los realces solapados suman +19 dB en 2.8 kHz.
