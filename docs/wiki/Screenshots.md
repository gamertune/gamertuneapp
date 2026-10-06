# Screenshots

Every page of the GamerTune settings window, top to bottom. Long pages are shown one screenful at a time. Captured from GamerTune 0.1.70 on Windows 11 with `tools/capture-screenshots.ps1`; values such as the detected CPU, GPU and display are from the capture machine and will differ on yours.

## Status

The dashboard: how many monitored settings have drifted, a summary of this PC (processor, graphics, memory, Windows edition, displays, active power plan) and the drift count for each section.

![Status](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-status.png)

![Status (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-status-2.png)

## Gaming

Game Mode, Game DVR, hardware-accelerated GPU scheduling, Memory Integrity / VBS and the other global gaming settings. Each card shows the current value, the Windows default and the recommendation, with Monitor / Want / Auto-apply controls.

![Gaming](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming.png)

![Gaming (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming-2.png)

![Gaming (continued, 3)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming-3.png)

![Gaming (continued, 4)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming-4.png)

![Gaming (continued, 5)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming-5.png)

Every setting has a **Learn more** panel with the recommendation, what it does, pros and cons of each choice, per-scenario advice, risks and copy-pasteable PowerShell to verify or reverse it:

![Gaming — Learn more expanded](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-gaming-learn-more.png)

## Display

Per-display HDR, Dynamic Refresh Rate, refresh rate and resolution, one panel per connected display.

![Display](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-display.png)

![Display (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-display-2.png)

## CPU and power

The detected CPU and its tuning recipe, Power Throttling, the power-plan monitor, and the CPU-aware gaming power plan (suggest a prebuilt Windows plan or build a GamerTune-tuned one).

![CPU and power](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-cpu-and-power.png)

![CPU and power (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-cpu-and-power-2.png)

## Telemetry

Privacy and telemetry toggles Windows often re-enables after feature updates: advertising ID, tailored experiences, Cross-Device Platform, activity history, online speech, inking and typing data.

![Telemetry](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-telemetry.png)

![Telemetry (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-telemetry-2.png)

![Telemetry (continued, 3)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-telemetry-3.png)

## Windows AI

Policy switches for Copilot, Recall, Click to Do, Edge and Office AI features, Notepad and Paint AI, settings-search AI and AI Actions, plus optional removal of Windows AI apps.

![Windows AI](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-windows-ai.png)

![Windows AI (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-windows-ai-2.png)

![Windows AI (continued, 3)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-windows-ai-3.png)

![Windows AI (continued, 4)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-windows-ai-4.png)

![Windows AI (continued, 5)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-windows-ai-5.png)

## Network

Network Throttling, Nagle's algorithm and NIC power management. The last two are contested per-hardware tweaks and default to the Windows value.

![Network](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-network.png)

![Network (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-network-2.png)

## Debloat

Windows 11 ads, nags, suggested content and idle background features (Start suggestions, lock-screen tips, the "Finish setting up your device" nag and more). Every toggle is reversible.

![Debloat](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-debloat.png)

![Debloat (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-debloat-2.png)

![Debloat (continued, 3)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-debloat-3.png)

## Services

The curated Windows services catalog with per-service Default / Manual / Disabled targets, and the Application Experience scheduled tasks.

![Services](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services.png)

![Services (continued, 2)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-2.png)

![Services (continued, 3)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-3.png)

![Services (continued, 4)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-4.png)

![Services (continued, 5)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-5.png)

![Services (continued, 6)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-6.png)

![Services (continued, 7)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-7.png)

![Services (continued, 8)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-8.png)

![Services (continued, 9)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-9.png)

![Services (continued, 10)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-10.png)

![Services (continued, 11)](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-services-11.png)

## BIOS

Recommended firmware settings for the detected CPU. Advisory only: GamerTune cannot read or change BIOS settings.

![BIOS](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-bios.png)

## General

One-click presets (Apply recommended, Apply extreme, Reset all to defaults), theme, launch at startup, update checks, the change log and the polling interval.

![General](https://raw.githubusercontent.com/gamertune/gamertuneapp/main/docs/screenshots/settings-general.png)

