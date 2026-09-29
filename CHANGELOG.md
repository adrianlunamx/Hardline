# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado [SemVer](https://semver.org/lang/es/).

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
