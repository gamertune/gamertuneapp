# File locations

Every file or registry entry GamerTune reads or writes is listed below. Nothing is hidden in System32, the Windows directory, or any user-invisible location.

## On disk

| Path | Purpose | Lifetime |
|---|---|---|
| `%LOCALAPPDATA%\Programs\GamerTune\GamerTune.exe` | Installed app | Until uninstall |
| `%APPDATA%\GamerTune\config.json` | Your monitor / want / auto-apply preferences | Persists; survives upgrades |
| `%APPDATA%\GamerTune\changes.log` | Append-only audit of every applied change | Auto-rotates at ~1 MB → `changes.log.1` |
| `%TEMP%\gamertune_error.log` | Unhandled-exception stack traces (rare) | Auto-rotates at ~1 MB → `.log.1` |
| `%TEMP%\gamertune_selftest.txt` | Output of `GamerTune.exe --test` | Overwritten each run |
| `%TEMP%\GamerTune-Setup-x.y.z.exe` | Installer downloaded by the auto-update flow before it launches | Auto-cleaned on next launch if older than 1 day |

If you see leftover `GamerTune-Setup-*.exe` files in `%TEMP%` from before v0.1.20, you can delete them — they were the previous auto-update flow's downloaded installers. v0.1.20+ cleans them up automatically.

## In the registry

| Key | Purpose | When written |
|---|---|---|
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\GamerTune` | Launch-at-startup entry | Created/removed by the *Launch at Windows startup* checkbox |

GamerTune *modifies* additional Windows registry locations as part of applying settings — but those are the user's own settings (HAGS, Memory Integrity, etc.), not GamerTune's data. The full list of mechanism keys is in [Logging](Logging) and in [`SettingDocs.cs`](https://github.com/gamertune/gamertuneapp/blob/main/src/GamerTune/Services/SettingDocs.cs).

## Single-instance enforcement

GamerTune uses a named mutex `GamerTune.SingleInstance` to ensure only one copy runs at a time. A second launch silently exits.

## What GamerTune does **not** touch

- System files / DLLs in `C:\Windows\`
- The hosts file
- Network adapter settings
- Browser settings or extensions
- Any file under another user's profile
- Any HKLM key not listed in [Logging](Logging)'s mechanism table
