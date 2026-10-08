# FAQ

## Ricochet

**¿Me pueden banear por usar Hardline?**

Hardline no interactúa con el proceso del juego: no inyecta, no lee memoria, no cambia la prioridad de `cod.exe` ni toca archivos del juego. Edita la configuración de usuario en `Documentos\Call of Duty\players`, que es lo mismo que hace el menú de ajustes. El resto son ajustes de Windows, drivers y audio del sistema.

Voicemeeter y Equalizer APO procesan el audio a nivel de Windows, fuera del juego. Son de uso habitual entre jugadores y streamers.

## Instalación

**El script dice que no puede crear el restore point.**

Causas habituales: Protección del sistema desactivada en C: (el script intenta activarla), poco espacio reservado para puntos de restauración, o el servicio de instantáneas de volumen (VSS) deshabilitado. Hardline sigue sin él si aceptas: el manifiesto de cambios permite revertir igual con `rollback.ps1`.

**"La ejecución de scripts está deshabilitada en este sistema".**

Con `irm | iex` no pasa: el instalador pone la política en Bypass solo para su proceso. Si ejecutas desde un clon:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

**¿Por qué se relanza en otra ventana?**

Porque faltaban permisos de administrador (se abre con UAC) o porque lo lanzaste desde PowerShell 7: `Checkpoint-Computer` (restore point) solo existe en Windows PowerShell 5.1.

**¿Puedo ejecutarlo varias veces?**

Sí. Lo que ya tiene el valor objetivo se omite y no se registra. Cada ejecución crea su propia sesión en `backups/`. Para revertir todo: `rollback.ps1 -All` (o el botón **Revertir todo** de la interfaz), que va de la más nueva a la más antigua. `rollback.ps1` sin parámetros solo revierte la más nueva pendiente.

## Actualizar

**¿Cómo actualizo Hardline?**

Con el botón **Actualizar** de la interfaz: aparece arriba, junto a la versión, cuando hay una nueva. También `install.ps1 -Update` desde la carpeta de Hardline, o el comando de instalación de siempre. Todo lo tuyo (backups, reportes, mediciones, perfiles de headset, progreso de la guía) se conserva.

## Rollback

**¿Qué revierte exactamente?**

Todo lo que aparece en `backups/<sesión>/manifest.json`: valores de registro (incluidos los tipos de inicio de servicios), plan de energía, DNS, propiedades de la NIC, política QoS, tarea del timer y archivos (config de Warzone, `config.txt` de Equalizer APO). Restaura el valor exacto anterior; si una clave no existía, la borra.

**¿Qué no revierte?**

- Software instalado (Voicemeeter, VB-CABLE, Equalizer APO) y lo que la limpieza de audio desinstaló a petición tuya. Se gestiona desde Configuración > Aplicaciones.
- AppX desinstalados (Xbox Game Bar, Cortana), si aceptaste quitarlos. Reinstalar desde la Microsoft Store; los enlaces están en el reporte.
- Lo que cambiaste tú en BIOS o Adrenalin.

**Algo se rompió y no sé qué.**

1. `.\rollback.ps1 -All`
2. Si persiste: Panel de control > Recuperación > Abrir Restaurar sistema > punto `Hardline_<fecha>`.
3. El log de la sesión (`logs/`) tiene cada cambio con su valor anterior.

## Audio

**No se oye nada en Warzone después de configurar el audio.**

En modo Completo el juego sale por `CABLE Input` y Voicemeeter lo lleva al headset. Comprueba:

1. Voicemeeter está abierto (icono en la bandeja). Hardline lo añade al inicio de sesión.
2. En Voicemeeter, A1 (arriba a la derecha) es tu headset.
3. En la strip 1 ("HL GAME"), el botón A1 está encendido.
4. Mezclador de volumen de Windows: `cod.exe` sale por `CABLE Input`.

Si Voicemeeter muestra A1 en rojo, el dispositivo no está disponible: vuelve a elegirlo en el desplegable de A1.

**Suena muy bajo.**

Es el preamp calculado (-20.5 dB en el preset base): evita el clipping de los realces. Sube el volumen de Windows o del headset. En modo Completo, el makeup del compresor ya compensa +6 dB.

**Suena metálico o chillón.**

Intensidad moderada: `.\src\audio\setup.ps1` y elige "Moderada". O baja 1-2 dB los filtros de 3600 y 5000 Hz de tu headset en `headsets.json`.

**Discord suena raro / con eco.**

Discord no debe salir por `CABLE Input`. Ponlo en la salida por defecto (`Voicemeeter Input`) o directo al headset.

**Ya tenía un EQ o un audio personalizado. ¿Se mezcla con el de Hardline?**

No. Antes de instalar, Hardline lo detecta y lo limpia. Tu configuración de Equalizer APO se aparta a `config\antes_de_hardline\` (el rollback la devuelve). Art Tune y HeSuVi se apartan enteros y los dispositivos que Art Tune renombró ("Art Tune +", "Virtual Mix") recuperan su nombre e icono. Peace, FxSound, Boom 3D, ViPER4Windows o Razer Surround se desinstalan con su propio desinstalador, preguntando uno a uno. Nahimic se desactiva. Si Equalizer APO está activo en varios dispositivos, te dice cuáles desmarcar.

**Los pasos se oyen bajos y mis disparos muy altos.**

Panel del EQ (Inicio > Hardline > Hardline EQ) > Compresor > **Fuerte**, con Voicemeeter abierto. Si se pierden sobre todo en tiroteos seguidos (un rush con tu escuadra disparando), prueba **Rush**: recupera el volumen entre disparo y disparo. Baja todo lo fuerte casi al instante (8:1, ataque de 1 ms) y sube lo flojo hasta +24 dB, con un limitador para no saturar. Ningún procesador sabe qué disparo es tuyo, pero los tuyos son lo más fuerte que suena, así que son lo que más baja. Necesita Voicemeeter Potato para el ajuste completo.

**¿Y Peace?**

Hardline ya no lo instala. Al guardar un preset en Peace se reescribe `config.txt` y desaparece el de Hardline, que es justo la confusión que se quiere evitar. Para encender y apagar el EQ y cambiar la intensidad está el **panel del EQ** (Inicio > Hardline > Hardline EQ), y en partida `Ctrl+Alt+F10`.

**Quiero cero latencia añadida.**

Modo Solo EQ (`-AudioMode EqOnly`). Sin Voicemeeter ni VB-CABLE: Equalizer APO va directo en el headset. Pierdes la compresión de explosiones.

**¿Qué es la opción HeSuVi y me conviene?**

HeSuVi virtualiza 7.1 en audífonos estéreo (es lo que hacía tu tarjeta USB 7.1, pero por software, sobre Equalizer APO). Conviene si quieres distinguir de dónde vienen los pasos (adelante/atrás/arriba/abajo). No hace que los pasos suenen más claros —eso lo hace el EQ— y no es magia: necesita que Windows tenga el headset en 7.1 y que Warzone saque 7.1 (no la mezcla "Auriculares"). Se instala con `-HeSuVi` o la casilla en la interfaz (default No). El EQ de Hardline sigue aplicando encima y Ctrl+Alt+F10 lo apaga sin perder la virtualización.

**Ya tenía HeSuVi instalado. ¿Hardline lo borra?**

Solo si no usas la opción `-HeSuVi`: antes se apartaba entero como "audio anterior" (revertible). Con `-HeSuVi`, Hardline lo detecta, lo conserva y lo integra en el `config.txt` junto al EQ de pasos.

**Mi headset no está en la lista.**

Elige "Otro modelo: buscar su medición en AutoEq" y escribe el modelo (solo el nombre: "Kraken V3", no "Razer Kraken V3 X USB negro"). Si no aparece, descarga el perfil más parecido en [autoeq.app](https://autoeq.app) (destino: Equalizer APO) y déjalo en la carpeta `headsets\`; o usa el Genérico.

**¿Dónde está la carpeta `headsets`?**

En la carpeta de Hardline: `%LOCALAPPDATA%\Hardline\headsets` si instalaste con `irm | iex`, o `headsets\` en tu clon. Las actualizaciones de Hardline no la borran.

## Plataformas

**Juego en Battle.net. ¿Por qué me pregunta por Steam y Xbox?**

Porque están instaladas y dejan procesos y servicios residentes. Si no las usas para otros juegos, Hardline las cierra, quita su arranque automático y deshabilita sus servicios. No las desinstala.

**Deshabilité Xbox y ahora un juego de Game Pass / Microsoft Store no arranca.**

Esos juegos necesitan los servicios de Xbox. `.\rollback.ps1` los restaura, o vuelve a ejecutar Hardline y responde que sí usas la Xbox app.

**¿Deja de funcionar mi mando de Xbox?**

No. `XboxGipSvc` (accesorios de Xbox) no se toca.

## Rendimiento

**No he ganado FPS.**

Los tweaks de Windows mejoran la consistencia (1% lows, picos), no la media. La ganancia de FPS medios viene casi entera de la configuración gráfica del juego y de EXPO/PBO en BIOS, que son manuales. Revisa la sección "Requiere acción manual" del reporte.

Para medir de verdad: CapFrameX, 60 s en el mismo sitio (campo de tiro o un recorrido fijo en Resurgence), antes y después. Hardline lee las capturas y las compara.

**Tengo stutter después de Curve Optimizer.**

CO inestable. Sube de -20 a -15 (o a 0 en el núcleo que falle según CoreCycler). Un CO inestable puede dar `DEV ERROR` sin llegar a pantallazo azul.

**¿Por qué no desactiva SMT si lo pedí?**

En 6 núcleos empeora los 1% lows en Warzone. Hardline lo sugiere solo a partir de 12 núcleos. Si quieres probarlo igualmente, está en la BIOS (`SMT Mode`); mide con CapFrameX antes de quedártelo.

**¿Por qué HAGS off si Microsoft lo recomienda on?**

Solo en Radeon: con RDNA2 y Warzone, HAGS off da frametimes más regulares en la mayoría de versiones de Adrenalin. En NVIDIA e Intel Hardline no lo toca. Si usas Frame Generation en otros juegos necesitas HAGS on; cámbialo en Configuración > Pantalla > Gráficos > Configuración de gráficos predeterminada.

## Registro de balas

**¿Hardline mejora el registro de balas?**

No directamente, y nadie puede: el registro lo decide el servidor. Lo que sí afecta es que tus paquetes lleguen completos, a tiempo y con ping estable. El **diagnóstico de red** mide pérdida, jitter y bufferbloat, y te dice si el problema está en casa (cable, Wi-Fi, router) o en tu proveedor. Las mejoras reales suelen ser: cable en vez de Wi-Fi, SQM en el router y no descargar mientras juegas.

**El diagnóstico descarga datos.**

Unos 100-250 MB durante 10 s para medir el bufferbloat. Si tienes tarifa limitada, desmarca "Diagnóstico de red".

## Pasos manuales

**¿Dónde están los pasos que tengo que hacer yo?**

En la **guía de pasos**: se abre sola al terminar de aplicar. Después, en **Inicio > Hardline > Guía de pasos** (página con casillas) o con el botón "Guía de pasos" de la interfaz (un paso cada vez). Están ordenados: primero Windows y el juego, que se notan más y cuestan menos; la BIOS y lo avanzado al final.

**¿Se pierde lo que marqué si vuelvo a aplicar?**

No. Cada paso tiene un identificador fijo; si vuelve a salir igual, sigue marcado. Lo que marcas en la interfaz o en la consola se refleja en la página. Lo que marcas en la página se recuerda en ese navegador.

## Notar la diferencia

**¿Cómo sé si Hardline me ha mejorado algo?**

Con **Medir partida**: mide antes de aplicar, aplica, reinicia y vuelve a medir en el mismo modo y mapa. Te da la tabla de FPS, 1% lows y tirones, y te dice si la diferencia es real o ruido entre partidas. Si ya aplicaste, la primera medición queda como referencia para el siguiente cambio que hagas.

**¿Qué es lo que más se nota?**

Por orden: el monitor al refresco correcto (si estaba mal), cable en vez de Wi-Fi o Bluetooth, la opción de baja latencia de la GPU en el juego (Reflex/Anti-Lag 2), quitar overlays y los 1% lows (tirones). Los tweaks de Windows por sí solos mueven poco los FPS medios: su efecto está en los tirones.

**El refresco subió y la pantalla se ve en negro.**

Pasa muy rara vez: el modo se prueba antes de aplicarlo. Espera 15 s; si sigue en negro, reinicia y ejecuta `rollback.ps1`, o cambia el refresco en Configuración > Pantalla > Pantalla avanzada.

**¿PresentMon es seguro con el anticheat?**

Sí: no se inyecta en el juego, lee los eventos que Windows ya publica. Es lo que usan CapFrameX, la app de Intel y la mayoría de reviews.

## Mando

**¿Hardline quita el delay del mando?**

Quita lo que se puede quitar desde Windows sin riesgo: el ahorro de energía USB del mando y su hub, y te avisa de lo que añade latencia (Bluetooth, DS4Windows, reWASD, Steam Input). En el juego pone la zona muerta de gatillos a 0 y desactiva el efecto de gatillo y la vibración. Lo que más se nota: cable en vez de Bluetooth y no pasar por una capa de remapeo.

**¿Qué zona muerta pongo en los sticks?**

La que te dé el test de mando (botón "Test de mando" o `install.ps1 -ControllerTestOnly`). Mide el drift real de tus sticks; con menos zona muerta la mira se mueve sola, con más pierdes movimientos finos.

**¿Sube la tasa de sondeo (polling rate) del mando?**

No. Hacerlo exige un driver sin firmar o el modo de prueba de Windows, con riesgo de conflicto con el anticheat. El test mide la tasa real para que compares cable, adaptador y Bluetooth.

**Uso DS4Windows con un DualSense.**

Warzone soporta DualSense y DualShock de forma nativa. Cierra DS4Windows para jugar; si lo necesitas para otros juegos, ábrelo solo entonces.

**El test no detecta mi DualSense desde la interfaz.**

Windows solo entrega la entrada de los mandos PlayStation a la ventana en primer plano, y la interfaz ejecuta el test en segundo plano. Usa `install.ps1 -ControllerTestOnly` desde la consola. Los mandos Xbox funcionan en los dos casos.

## Interfaz gráfica

**No encuentro la ventana.**

Inicio > Hardline > Hardline, o `%LOCALAPPDATA%\Hardline\install.ps1 -Gui`. Pide permisos de administrador (UAC).

**Los instaladores de audio abren ventanas.**

Equalizer APO y VB-CABLE tienen instalador propio con su ventana; termina cada uno y la interfaz sigue sola. El paso del Configurator de Equalizer APO queda en el reporte.

## Modo partida

**¿Cómo sé si está funcionando?**

Abre `C:\Program Files\Hardline\gamesession\gamesession.log`: cada partida deja una línea `INICIO` con lo que pausó y otra `FIN` al cerrar el juego. La tarea se llama `Hardline-GameSession` en el Programador de tareas.

**Quiero que no toque X / que cierre Y.**

Edita `config\gamesession.json`: quita X de `pause_services` o `lower_priority`, o añade Y a `close_processes` (nombre del proceso sin `.exe`). Después pulsa **Aplicar** (con el modo partida marcado): Hardline copia la configuración a la carpeta protegida del modo partida, que es la que usa la tarea.

**Se fue la luz a mitad de partida y Windows Search no arranca.**

Al iniciar sesión, el modo partida restaura lo que quedó pendiente. Si lo desinstalaste antes, ejecuta como administrador `src\modules\windows\gamesession_watcher.ps1 -Root "C:\Program Files\Hardline\gamesession" -RestoreOnly` (o `-Root <carpeta de Hardline>` si lo instalaste con la 1.11 o anterior).

## Panel y atajo del EQ

**¿Dónde enciendo y apago el EQ?**

En el **panel del EQ**: Inicio > Hardline > Hardline EQ, o el botón "Panel del EQ" de la interfaz. Muestra si está encendido, lo cambia con un clic y deja elegir intensidad Completa o Moderada (70%) al momento. No pide administrador. En partida, sin salir del juego: `Ctrl+Alt+F10`; el panel se actualiza solo.

**El panel dice "Sin configurar".**

Falta la configuración de audio de Hardline: aplica con la casilla Audio marcada.

**Ctrl+Alt+F10 no hace nada.**

- Comprueba que existe Inicio > Hardline > "Hardline EQ on-off" (el atajo vive en ese acceso directo).
- En pantalla completa exclusiva algunos juegos capturan el teclado: usa "Pantalla completa sin bordes".
- Un pitido largo y grave significa error: mira `logs\eq_toggle.log`.

**¿El test de pasos se oye por el headset?**

Sí, por el mismo camino que el juego: en modo Completo sale por `CABLE Input`, pasa por el EQ y Voicemeeter lo manda al headset. Si no oyes nada, Voicemeeter no está abierto o A1 no es tu headset.

## Desarrollo

**¿Cómo pruebo cambios?**

```powershell
.\tests\validate.ps1          # sintaxis, codificación, JSON, EQ, parser de Warzone, rollback
.\install.ps1 -DryRun         # recorre todo sin aplicar nada
```

**¿Por qué `install.ps1` no tiene tildes?**

Windows PowerShell 5.1 interpreta el texto sin BOM como ANSI. Cuando el script llega por `irm | iex` no hay archivo ni BOM, así que cualquier carácter no ASCII se corrompe. El resto de archivos se ejecutan desde disco con BOM UTF-8 y sí las llevan. `tests/validate.ps1` comprueba ambas cosas.
