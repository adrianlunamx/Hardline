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

Sí. Lo que ya tiene el valor objetivo se omite y no se registra. Cada ejecución crea su propia sesión en `backups/`. Para revertir todo, revierte de la más nueva a la más antigua (`rollback.ps1` sin parámetros coge siempre la más nueva pendiente).

## Rollback

**¿Qué revierte exactamente?**

Todo lo que aparece en `backups/<sesión>/manifest.json`: valores de registro (incluidos los tipos de inicio de servicios), plan de energía, DNS, propiedades de la NIC, política QoS, tarea del timer y archivos (config de Warzone, `config.txt` de Equalizer APO). Restaura el valor exacto anterior; si una clave no existía, la borra.

**¿Qué no revierte?**

- Software instalado (Voicemeeter, VB-CABLE, Equalizer APO, Peace). Se quita desde Configuración > Aplicaciones.
- AppX desinstalados (Xbox Game Bar, Cortana), si aceptaste quitarlos. Reinstalar desde la Microsoft Store; los enlaces están en el reporte.
- Lo que cambiaste tú en BIOS o Adrenalin.

**Algo se rompió y no sé qué.**

1. `.\rollback.ps1`
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

**¿Para qué sirve Peace si Hardline ya escribe el EQ?**

Para ver la curva y activar/desactivar el EQ rápido. Si guardas un preset desde Peace, sustituye el de Hardline en `config.txt`; para volver al de Hardline, ejecuta otra vez el audio.

**Quiero cero latencia añadida.**

Modo Solo EQ (`-AudioMode EqOnly`). Sin Voicemeeter ni VB-CABLE: Equalizer APO va directo en el headset. Pierdes la compresión de explosiones.

## Rendimiento

**No he ganado FPS.**

Los tweaks de Windows mejoran la consistencia (1% lows, picos), no la media. La ganancia de FPS medios viene casi entera de la configuración gráfica del juego y de EXPO/PBO en BIOS, que son manuales. Revisa la sección "Requiere acción manual" del reporte.

Para medir de verdad: CapFrameX, 60 s en el mismo sitio (campo de tiro o un recorrido fijo en Resurgence), antes y después. Hardline lee las capturas y las compara.

**Tengo stutter después de Curve Optimizer.**

CO inestable. Sube de -20 a -15 (o a 0 en el núcleo que falle según CoreCycler). Un CO inestable puede dar `DEV ERROR` sin llegar a pantallazo azul.

**¿Por qué no desactiva SMT si lo pedí?**

En 6 núcleos empeora los 1% lows en Warzone. Hardline lo sugiere solo a partir de 12 núcleos. Si quieres probarlo igualmente, está en la BIOS (`SMT Mode`); mide con CapFrameX antes de quedártelo.

**¿Por qué HAGS off si Microsoft lo recomienda on?**

Con RDNA2 y Warzone, HAGS off da frametimes más regulares en la mayoría de versiones de Adrenalin. Si usas Frame Generation en otros juegos necesitas HAGS on; cámbialo en Configuración > Pantalla > Gráficos > Configuración de gráficos predeterminada.

## Desarrollo

**¿Cómo pruebo cambios?**

```powershell
.\tests\validate.ps1          # sintaxis, codificación, JSON, EQ, parser de Warzone, rollback
.\install.ps1 -DryRun         # recorre todo sin aplicar nada
```

**¿Por qué `install.ps1` no tiene tildes?**

Windows PowerShell 5.1 interpreta el texto sin BOM como ANSI. Cuando el script llega por `irm | iex` no hay archivo ni BOM, así que cualquier carácter no ASCII se corrompe. El resto de archivos se ejecutan desde disco con BOM UTF-8 y sí las llevan. `tests/validate.ps1` comprueba ambas cosas.
