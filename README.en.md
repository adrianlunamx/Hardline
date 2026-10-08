<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg">
    <img alt="Hardline" src="assets/logo-light.svg" width="460">
  </picture>
</p>

<h3 align="center">Warzone PC optimizer: more FPS, lower input lag, and footsteps you hear first.</h3>

<p align="center">
  Windows 10/11 · AMD, NVIDIA &amp; Intel · Battle.net, Steam &amp; Xbox · <b>free, open source and 100% reversible</b>
</p>

<p align="center">
  <a href="https://github.com/adrianlunamx/Hardline/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/adrianlunamx/Hardline?style=for-the-badge&color=FF5A1F"></a>
  <a href="https://github.com/adrianlunamx/Hardline/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/adrianlunamx/Hardline/total?style=for-the-badge&color=0E1116"></a>
  <a href="https://github.com/adrianlunamx/Hardline/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/adrianlunamx/Hardline?style=for-the-badge&color=0E1116&logo=github"></a>
</p>
<p align="center">
  <a href="https://github.com/adrianlunamx/Hardline/actions/workflows/release.yml"><img alt="CI" src="https://github.com/adrianlunamx/Hardline/actions/workflows/release.yml/badge.svg"></a>
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E1116?style=flat-square&logo=windows">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-0E1116?style=flat-square&logo=powershell">
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-FF5A1F?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">Español</a> · <b>English</b>
</p>

<p align="center">
  <img alt="Hardline GUI: modules, step guide, Hardline EQ and tools" src="assets/screenshots/interfaz.png" width="900">
</p>

---

**Hardline** tunes Windows, your GPU/CPU platform, the network, **Call of Duty: Warzone**'s config and your audio, so you hear footsteps first. One GUI, one click, and every change recorded so you can undo it.

- ⚡ **Applies** what can be changed safely: services, power, timer, MSI mode, network, in-game graphics.
- 🎧 **Competitive audio**: a footstep EQ on top of **your** headset's measured correction, a compressor, and a slider panel.
- 🧭 **Guides you** through what can't be touched from Windows (BIOS, Adrenalin, NVIDIA App): a button opens the exact panel.
- ↩️ **Records** every change with its previous value: revert everything in one click.
- 📊 **Measures** before and after with PresentMon (FPS, 1% lows, stutter) and writes a report.

### Why Hardline

| | Hardline | Typical "FPS booster" |
|---|:---:|:---:|
| Every change stored with its previous value, **exact rollback** | ✅ | ❌ |
| **Measures** your real match before and after | ✅ | ❌ |
| Only tweaks with demonstrated effect; dubious ones off and labeled | ✅ | ❌ |
| Never touches the game process or injects anything (Ricochet anti-cheat) | ✅ | ⚠️ |
| Footstep audio built on **your headset's measured correction** (AutoEq) | ✅ | ❌ |
| Open source, SHA256-verified releases, tests on every change | ✅ | ❌ |

> The tool itself (console output, report, docs) is in Spanish. This page is an English overview.

## Install

PowerShell **as administrator**:

```powershell
irm https://raw.githubusercontent.com/adrianlunamx/Hardline/main/install.ps1 | iex
```

Dry run first, to see what it would do without changing anything:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/adrianlunamx/Hardline/main/install.ps1))) -DryRun
```

The one-liner opens the **GUI** (add `-Console` for the console). Later: Start > Hardline > Hardline, or `install.ps1 -Gui`. Hardline EQ announces every new version and every time you apply settings.

**Manual steps** (BIOS, GPU control panel, in-game menus) end up in a step-by-step **guide**, ordered from highest impact to advanced. When a step happens in a Windows panel or an app (Sound, Recording, Volume mixer, 7.1 speaker setup, HeSuVi, Equalizer APO, Voicemeeter), the guide has a button that opens it. Each step is shown once: after applying, only new steps pop up; pending ones stay under Start > Hardline > Guía de pasos. Progress is remembered.

**See the difference on your own PC**: use **Measure match** (GUI button or `install.ps1 -GameplayBenchOnly`) before applying, apply and reboot, then measure again in the same mode and map. It records 60 s of real gameplay with Intel PresentMon and compares average FPS, 1% lows and stutter, telling a real improvement apart from match-to-match noise.

It downloads the **latest release** and verifies its SHA256 before running (`-Channel main` gets the latest `main` branch instead). It creates a Windows restore point first and installs to `%LOCALAPPDATA%\Hardline`. You pick which modules to apply in the GUI (or in a checklist with `-Console`).

## What it does

| Area | Automatic | Left in the report for you |
|---|---|---|
| **Display** | Monitor running below its maximum refresh rate (144 Hz stuck at 60): raised. Windowed game optimizations and VRR. Warns about overlays (Discord, RivaTuner, Overwolf, Medal...) | FreeSync/G-SYNC FPS cap computed from your refresh rate |
| **Platforms** | Pick where you play (Battle.net, Steam, Xbox app). The others: processes closed, autostart removed, services disabled | |
| **Game session mode** | While Warzone is running: pauses background services, lowers browser/launcher priority, switches to the max power plan. Restores everything when you quit | |
| **Windows** | Background services, Game DVR off, Game Mode on, MMCSS, Ultimate Performance, 0.5 ms timer (Win11), widgets/Cortana off | LatencyMon if DPC spikes |
| **GPU** | Radeon, GeForce and Arc: driver age, real Resizable BAR state, recent driver crashes (TDR). HAGS off on Radeon only | Anti-Lag / Reflex / XeLL, control panel settings, undervolt |
| **CPU / RAM** | Ryzen family, SMT, chipset driver, EXPO/XMP state | PBO, Curve Optimizer -20, tRFC |
| **Advanced latency** | MSI interrupt mode for GPU, NIC and USB controllers (only where the hardware supports it); NIC interrupt moderation off, RSS on | Verify with LatencyMon |
| **Experimental** *(off by default)* | `disabledynamictick`, mouse/keyboard queue size, `Win32PrioritySeparation`. Weak evidence: measure and revert if nothing changes | |
| **Network** | DNS 1.1.1.1, NIC power saving off, autotuning, DSCP 46 QoS for `cod.exe` | Router SQM if there is bufferbloat |
| **Network diagnosis** | Packet loss and jitter to the router and to the Internet separately, bufferbloat under load (A+ to F), MTU | Hit registration is server-side; this measures what reaches the server and whether problems are at home or at your ISP |
| **Controller** | Detects controller and connection; USB power saving off for the controller and its hub; warns about Bluetooth and remapping layers (DS4Windows, reWASD, Steam Input...); trigger deadzone 0, vibration off. Built-in test measures stick drift and real update rate (Hz) | Stick deadzone from the test result, wired or official adapter |
| **Warzone** | Graphics settings in `options.*.cst`, validated against the file's own allowed values. Reflex + Boost, Anti-Lag 2 or XeLL for your GPU; exclusive fullscreen | FOV, brightness |
| **Audio** | Measured headset correction (AutoEq, ~8800 models) + footsteps EQ + compressor/gate (Voicemeeter). EQ panel (on/off, full or moderate intensity, no admin), `Ctrl+Alt+F10` in-game, built-in A/B footstep test | Per-app routing of `cod.exe` in Windows |

## Audio

```mermaid
flowchart LR
    G[cod.exe] --> C[CABLE Input]
    C --> EQ["Equalizer APO<br/>headset correction<br/>+ footsteps preset"]
    EQ --> VM["Voicemeeter<br/>gate -45 dB · comp 4:1"]
    VM --> H((Headset))
    D[Discord and system] --> VI[Voicemeeter Input] --> H
```

- **Footsteps EQ**: boosts 2-4 kHz (heel strike and surface texture), cuts below 500 Hz (explosions, your own gunfire).
- **No clipping**: the overlapping boosts add up to **+19 dB** at 2.8 kHz. Hardline computes the real filter response and sets the preamp (-20.5 dB for the base preset).
- **Your headset**: measured correction from [AutoEq](https://github.com/jaakkopasanen/AutoEq) for 6 bundled models or any of ~8800 by name, or drop your own Equalizer APO file in `headsets\`.
- **Zero added latency**: `-AudioMode EqOnly` skips Voicemeeter.

## Revert

```powershell
.\rollback.ps1              # last session
.\rollback.ps1 -All         # every session: back to before Hardline
.\rollback.ps1 -List        # list sessions
```

Restores the exact previous value of every change (registry, services, power plan, DNS, NIC, QoS, scheduled tasks, files). Installed software (Voicemeeter, VB-CABLE, Equalizer APO) is removed from Settings > Apps.

**Existing custom audio**: before installing, Hardline looks for a previous setup (own Equalizer APO config, Art Tune, HeSuVi, Peace, FxSound, Boom 3D, ViPER4Windows, Razer Surround, Nahimic, Sonar, Voicemeeter Banana) and cleans it first: old Equalizer APO files are moved to `config\antes_de_hardline\` (restored by rollback), Art Tune and HeSuVi are moved aside whole (library, VST, icons, LEQ Control Panel, shortcuts) and VB-CABLE / Voicemeeter get their factory names and icons back, stacking audio apps are removed with their own uninstaller (asked one by one), and you are told which devices to untick if Equalizer APO is active on more than one.

## Anti-cheat

Hardline never touches the game process: no injection, no memory access, no priority/affinity changes, no game files. It only edits the user config the game itself stores in `Documents\Call of Duty\players`, same as the settings menu.

## Requirements

Windows 10 22H2 or 11 · PowerShell 5.1 (built in) · Administrator rights · Internet for audio components and AutoEq profiles.

## License

MIT. Headset profiles come from [AutoEq](https://github.com/jaakkopasanen/AutoEq) (MIT).

## Support the project

If Hardline gave you FPS, removed stutter or let you hear someone before they saw you, **star the repo ⭐**: that's how other players find it. Bugs and ideas: [open an issue](https://github.com/adrianlunamx/Hardline/issues/new/choose).

<sub>Hardline is not affiliated with Activision, Call of Duty, Microsoft, AMD, NVIDIA or Intel. Trademarks belong to their owners.</sub>

<sub>Keywords: Warzone optimizer, Warzone FPS boost, fix Warzone stuttering, reduce input lag, best Warzone PC settings, Warzone footsteps EQ, hear footsteps better, Equalizer APO, Voicemeeter, Call of Duty, Black Ops, Windows 11 gaming tweaks, Ryzen, Radeon, NVIDIA, bufferbloat.</sub>
