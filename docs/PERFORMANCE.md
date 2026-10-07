# Performance: how light GamerTune is, and how we know

GamerTune runs all the time, so its cost should be small, measured, and stated
plainly. This page lists what was measured, how, what changed as a result, and
what is still heavier than we'd like. Every number below comes from
[`tools/measure-footprint.ps1`](../tools/measure-footprint.ps1), which is re-run
against every build before it ships.

## Summary

Measured 2026-10-06/07 on 0.1.72 (the changes below), compared with 0.1.71.
Where a build was measured more than once, the range across runs is shown.

| | 0.1.71 | 0.1.72 | Change |
|---|---|---|---|
| **In the tray, idle** — private memory (committed) | 115–116 MB (3 runs) | **37.5–37.7 MB** (2 runs) | −67% |
| **In the tray, idle** — working set (median) | 19.5–20.3 MB | **17.3–19.5 MB** | slightly lower |
| **In the tray, idle** — CPU per 30 s polling cycle | 36.5–39.1 ms | **31.2–33.9 ms** (≈0.1% of one core) | about the same |
| **Settings window open** — peak private memory | 287 MB (1 run) | **206–281 MB** | 2–28% lower |
| **Settings window open** — peak working set | 152 MB | **147–172 MB** | about the same |
| **After closing Settings** — private memory | 233 MB | **153–175 MB** | 25–34% lower |
| **After closing Settings** — working set (median) | 28 MB | **24–25 MB** | slightly lower |
| Installer download | 72 MB | **52 MB** | −28% |
| Installed `GamerTune.exe` on disk | 77 MB | 185 MB | **+108 MB** |

In one line: **under 20 MB of RAM and about 38 MB of committed memory while it sits
in the tray**, roughly 0.1% of one CPU core, and noticeably more (about 150–175 MB
committed, measured 4 minutes after closing) once you have opened the Settings window.

The tray figures repeat closely from run to run. The Settings-window figures do
not: two runs of the identical 0.1.72 build peaked at 206 MB and 281 MB, because
the peak depends on when .NET's garbage collector happens to run relative to the
samples. Treat those as ranges, not exact numbers.

## What the two memory numbers mean

Task Manager's default **Memory** column shows the *working set*: the part of the
app's memory that is in RAM right now. GamerTune deliberately keeps that low: every
five polling cycles (about 2.5 minutes) it runs a full garbage collection and asks
Windows to page its memory out (`EmptyWorkingSet`). Right after a trim the working
set can read as low as 1 MB; it climbs back as the app touches memory again. That
is why the table quotes the **median** over several trim cycles, not a single
reading.

Trimming moves memory out of RAM; it does not give it back. *Private memory*
(Task Manager → Details → "Commit size") is everything the app has reserved,
whether or not it is in RAM right now. It counts against your system's commit
limit and is the closest single number to what the app really costs, so both are
reported, and private memory is the one the changes below target.

## How it was measured

`tools/measure-footprint.ps1` (Windows PowerShell 5.1) does the following:

1. Stops any running GamerTune (only one copy can run at a time) and starts the
   build under test with `--tray`, so no window opens.
2. Waits 60 seconds for start-up work to finish (the first full scan, the
   update check, JIT compilation).
3. **Tray phase:** samples working set and private memory every 5 seconds for
   6 minutes (72 samples, about 2.4 trim cycles) and records the process's total
   CPU time over the same window. *CPU per polling cycle* is that CPU time divided
   by the number of 30-second cycles in the window — all of the app's idle CPU
   charged to the cycles, so it is an upper bound on the cost of one cycle.
4. **Settings phase:** restarts the build with `--show-settings`, clicks through
   all eleven sidebar pages (Status → General) with a 1.5-second pause on each,
   records the peak, closes the window with its close button, waits 15 seconds,
   and samples the tray again for 4 minutes.
5. Restarts whatever GamerTune was running before.

Test machine: AMD Ryzen 7 9850X3D, NVIDIA GeForce RTX 5080, 32 GB DDR5,
Windows 11 Pro 25H2 (build 26200), one 3840×2160 display at 120 Hz. The config
monitors most settings with auto-apply on, so the polling work is at the heavy end
of a typical setup. Every build compared was published exactly the way the
release workflow publishes it (self-contained, single-file, win-x64, Release).

**Repeatability:** 0.1.71 was measured three separate times. Idle working set
came out at 19.5–20.3 MB, private memory at 115.0–115.7 MB and CPU per cycle at
36.5–39.1 ms, so differences of a few milliseconds of CPU between builds are
noise; differences in memory of more than a couple of MB are real.

**What the windows don't cover:** the slow 10-minute check of the ~40
set-and-forget settings falls outside the sampling windows. It was timed
separately: on the test configuration its heaviest part, five scheduled-task
queries, uses about 80 ms of CPU in total, once every 10 minutes, on a
background thread.

## What changed

### 1. The single-file EXE is no longer compressed

GamerTune ships as one self-contained EXE with the .NET runtime, WPF and WinForms
inside it. With `EnableCompressionInSingleFile=true`, every one of those
libraries has to be decompressed into private memory each time the app starts —
about 80 MB of committed memory spent on code it mostly never runs. Without
compression, the runtime maps the libraries straight from the EXE file and Windows
pages in only the parts that are used; that memory is backed by the file, so
Windows can drop it at any time without writing anything to the page file.

- Private memory in the tray: **115 MB → 38 MB**.
- The installer got *smaller* (72 MB → 52 MB): its LZMA compression works far
  better on the raw libraries than on already-compressed ones.
- The cost: the installed `GamerTune.exe` is 185 MB instead of 77 MB, and the
  optional portable EXE on each release is a 185 MB download.

Set in all three publish workflows (`release.yml`, `dev-build.yml`, `beta.yml`).

### 2. Leaner .NET garbage-collector settings

In `GamerTune.csproj`:

- `ConcurrentGarbageCollection=false` — no background GC thread. The app's managed
  heap is a few megabytes, so a blocking collection takes well under a
  millisecond; a dedicated background collector buys nothing here.
- `TieredPGO=false` — turns off dynamic profile-guided optimisation, which
  instruments hot code to re-compile it later. It pays off in long-running hot
  loops this app doesn't have.

Measured together on top of change 1: idle working set 21.0 → 17.2 MB, private
memory unchanged (37.7 → 36.8 MB), CPU unchanged. A small win, but a free one.

### All variants measured

| Variant | Tray WS median | Tray private | CPU / cycle |
|---|---|---|---|
| A — as released in 0.1.71 (compressed) | 20.2 MB | 115.3 MB | 36.5 ms |
| B — uncompressed | 21.0 MB | 37.7 MB | 40.4 ms |
| C — uncompressed + GC settings | 17.2 MB | 36.8 MB | 39.1 ms |
| D — uncompressed, periodic trim switched off | 49.3 MB | 36.8 MB | 27.3 ms |
| Final — C built from the repo, run 1 | 17.3 MB | 37.5 MB | 33.9 ms |
| Final — 0.1.72 release build, run 2 | 19.5 MB | 37.7 MB | 31.2 ms |

## What we tested and kept as it is

**The periodic memory trim (variant D).** Switching it off saves about 12 ms of CPU
per 30-second cycle (≈0.04% of one core) — the cost of the forced collection and
of paging memory back in afterwards — but the app then holds about 32 MB more of
your RAM (49 MB instead of 17 MB). For a tool that exists to stay out of a game's
way, handing that RAM back is worth a few milliseconds of CPU, so the trim stays.

## Process launches — the full list

GamerTune does not run other programs while it watches your **display**
settings, and it reads registry, power-plan and display state through Windows
APIs directly (`powrprof.dll`, the registry API, `QueryDisplayConfig`). It does
launch Windows' own tools in these cases:

| When | What runs | Why |
|---|---|---|
| Slow check (startup, resume, every 10 min), only for scheduled tasks you manage | `schtasks.exe /Query` — one per task | Reads whether the task is enabled |
| Slow check, only for Windows AI apps you've set to *Removed* | `powershell.exe` (`Get-AppxPackage`) — one per app | Checks whether the app is still installed |
| Applying a machine-wide (HKLM) setting | `reg.exe` / `cmd.exe`, elevated | Writes the value; this is the UAC prompt |
| Applying a service change | `sc.exe` / `cmd.exe`, elevated | Changes the service start type |
| Applying a scheduled-task change | `cmd.exe` running `schtasks.exe`, elevated | Enables or disables the task (one UAC prompt for all tasks) |
| Removing a Windows AI app | `powershell.exe` (`Remove-AppxPackage`) | Uninstalls the app |
| You choose *Restart now* | `shutdown.exe` | Restarts Windows |

## Still heavier than it should be

- **The Settings window leaves memory behind.** Opening it and visiting every page
  raises private memory to about 206–281 MB; after closing it about 153–175 MB stays
  committed, still there 4 minutes later (working set does drop back to ~25 MB
  thanks to the trim). That retained ~115–140 MB is the largest remaining cost and
  the next thing to investigate. It has not been profiled yet; the likely cause
  is WPF and the UI library keeping their loaded resources and caches.
- **The scheduled-task and AI-app checks launch processes.** Both could use
  in-process Windows APIs instead (the Task Scheduler COM API and the AppX
  `PackageManager`), which would remove every process launch from monitoring.
- **Each polling cycle re-reads `config.json`.** Reloading only when the file has
  changed would trim the per-cycle CPU further.

## Re-running the measurement

From the repo root, with the build you want to measure:

```powershell
powershell -ExecutionPolicy Bypass -File tools\measure-footprint.ps1 -Exe publish\GamerTune.exe
```

It takes about 12 minutes and clicks through the Settings window during the
second phase, so leave the mouse alone while it runs. `-SkipSettingsPhase`
measures the tray only (about 7 minutes). Without `-Exe` it measures the installed
copy.
