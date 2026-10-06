using System.Reflection;
using System.Windows;
using GamerTune.Monitors;
using GamerTune.Services;
using GamerTune.Tray;
using GamerTune.UI;
using WpfApplication = System.Windows.Application;

namespace GamerTune;

public partial class App : WpfApplication
{
    private static Mutex? _singleInstanceMutex;

    private TrayIconHost? _tray;
    private MonitorService? _monitor;
    private Notifier? _notifier;
    private ConfigStore? _store;
    private SettingsWindow? _settingsWindow;
    private IReadOnlyList<IMonitoredSetting>? _allMonitors;

    protected override void OnStartup(StartupEventArgs e)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
            LogException("unhandled", ex.ExceptionObject as Exception);
        DispatcherUnhandledException += (_, ex) =>
        {
            LogException("dispatcher", ex.Exception);
            ex.Handled = true;
        };

        base.OnStartup(e);

        if (e.Args.Any(a => a == "--test"))
        {
            RunSelfTest();
            Shutdown();
            return;
        }

        // --gen-docs DEST -- render the settings catalog as markdown and exit.
        // Used to regenerate docs/SETTINGS-REFERENCE.md from CI / pre-commit so
        // the doc and the catalog can't drift apart.
        for (int i = 0; i < e.Args.Length; i++)
        {
            if (e.Args[i] == "--gen-docs")
            {
                var dest = (i + 1 < e.Args.Length) ? e.Args[i + 1] : "docs\\SETTINGS-REFERENCE.md";
                try
                {
                    var md = Services.SettingsReferenceGen.Render();
                    var dir = System.IO.Path.GetDirectoryName(dest);
                    if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
                    System.IO.File.WriteAllText(dest, md);
                    Environment.ExitCode = 0;
                }
                catch (Exception ex)
                {
                    LogException("gen-docs", ex);
                    Environment.ExitCode = 1;
                }
                Shutdown();
                return;
            }
        }

        _singleInstanceMutex = new Mutex(initiallyOwned: true, AppIdentity.MutexName, out bool created);
        if (!created)
        {
            Shutdown();
            return;
        }

#if BETA
        // First launch of a beta build with no state of its own: start from the
        // stable install's settings rather than from defaults. One-way copy -- the
        // stable config is read and never written. No-ops on every later launch.
        ConfigStore.SeedConfigFrom(AppIdentity.StableConfigDirectory, AppIdentity.ConfigDirectory);
#endif
        // First launch after the GamerGuardian -> GamerTune rename: carry the old
        // settings forward. A no-op once this build has state of its own (and, in
        // a beta, when the seed above already created it).
        ConfigStore.SeedConfigFrom(AppIdentity.LegacyConfigDirectory, AppIdentity.ConfigDirectory);

        _store = new ConfigStore();
        ChangeLogger.LogSessionStart();
        var cfg = _store.Load();
        // Dev builds (local Debug + the dev-build.yml CI artifacts with "-dev" in
        // InformationalVersion) keep their hands off the installed app's Windows-
        // startup entry and never offer to "upgrade" themselves to production.
        if (!IsDevBuild())
        {
            StartupRegistration.Sync(cfg.LaunchAtStartup);
        }
        ThemeService.Apply(cfg.Theme);
        TempCleanup.Run();

        _notifier = new Notifier();
        var fixedMonitors = new IMonitoredSetting[]
        {
            new HdrMonitor(),
            new RefreshRateMonitor(),
            new ResolutionMonitor(),
            new DrrMonitor(),
            new VrrMonitor(),
            new HagsMonitor(),
            new MemoryIntegrityMonitor(),
            new VbsMonitor(),
            new SystemResponsivenessMonitor(),
            new NetworkThrottlingMonitor(),
            new UsbSelectiveSuspendMonitor(),
            new GamesTaskProfileMonitor(),
            new GameModeMonitor(),
            new GameDvrMonitor(),
            new MousePrecisionMonitor(),
            new FullscreenOptimizationsMonitor(),
            new PowerPlanMonitor(),
            // Windows AI lockdown -- registry-policy monitors. UWP-removal
            // (Microsoft.Copilot etc.) is registered separately below as
            // per-package monitors via WindowsAiAppCatalog.
            new CopilotMonitor(),
            new RecallMonitor(),
            new ClickToDoMonitor(),
            new EdgeAiMonitor(),
            new NotepadPaintAiMonitor(),
            // v0.1.39 additions for closer parity with zoicware/RemoveWindowsAI:
            new SettingsSearchAiMonitor(),
            new AiActionsMonitor(),
            new InputInsightsMonitor(),
            new OfficeCopilotMonitor(),
            // Privacy / telemetry toggles (Privacy tab):
            new AdvertisingIdMonitor(),
            new TailoredExperiencesMonitor(),
            new CdpMonitor(),
            new ActivityHistoryMonitor(),
            new OnlineSpeechMonitor(),
            new InkingTypingMonitor(),
            // Debloat tab -- ads, nags, suggested content & background bloat:
            new SuggestedContentMonitor(),
            new LockScreenSpotlightMonitor(),
            new FinishSetupNagMonitor(),
            new StartRecommendationsMonitor(),
            new ExplorerAdsMonitor(),
            new FeedbackNagMonitor(),
            new WidgetsMonitor(),
            new EdgeBackgroundMonitor(),
            // System toggles:
            new PowerThrottlingMonitor(),  // CPU/Power tab
            new FastStartupMonitor(),       // Global gaming tab
            new VisualEffectsMonitor(),     // Global gaming tab
            // Network toggles (Network tab):
            new NagleMonitor(),
            new NicPowerMonitor(),
        };
        var serviceMonitors = GamerTune.Services.ServiceCatalog.All
            .Select(d => (IMonitoredSetting)new WindowsServiceMonitor(d));
        var aiAppMonitors = GamerTune.Services.WindowsAiAppCatalog.All
            .Select(d => (IMonitoredSetting)new WindowsAiAppMonitor(d));
        var scheduledTaskMonitors = GamerTune.Services.ScheduledTaskCatalog.All
            .Select(d => (IMonitoredSetting)new ScheduledTaskMonitor(d));
        _allMonitors = fixedMonitors
            .Concat(serviceMonitors)
            .Concat(aiAppMonitors)
            .Concat(scheduledTaskMonitors)
            .ToArray();
        _monitor = new MonitorService(_store, _allMonitors, report => _notifier.ShowAsync(report));
        _monitor.AutoAppliedRebootRequired += items =>
            GamerTune.Services.RebootPrompt.Show(items.Select(i => i.Description).ToList());

        _tray = new TrayIconHost();
        _tray.OpenSettingsRequested += ShowSettings;
        _tray.CheckNowRequested += () => _monitor.TriggerNow();
        _tray.PauseToggleRequested += () => _monitor.TogglePaused();
        _tray.ExitRequested += ExitApp;
        _monitor.PauseChanged += paused => _tray?.SetPaused(paused);

        _monitor.Start();

        // Verbose baseline: log the current state of every monitored setting
        // at session start. Gives users a known baseline to grep against later
        // when they see drift; also surfaces "Oh, that one's drifting" without
        // requiring the user to open Settings.
        try
        {
            var rows = _allMonitors
                .SelectMany(m =>
                {
                    try
                    {
                        return m.CheckDrift(cfg).Select(d =>
                            (d.SettingId, d.DisplayLabel, current: d.CurrentValue, desired: d.DesiredValue, inSync: false));
                    }
                    catch { return Enumerable.Empty<(string, string, string, string, bool)>(); }
                })
                .ToList();
            if (rows.Count > 0) ChangeLogger.LogStateSnapshot(rows);
        }
        catch { }

        bool isFirstRun = !System.IO.File.Exists(_store.ConfigPath);
        if (isFirstRun || e.Args.Any(a => a == "--show-settings")) ShowSettings();

#if !BETA
        if (cfg.CheckForUpdatesOnStartup && !IsDevBuild())
            _ = Task.Run(async () => await CheckForUpdatesAsync());
#endif
        // BETA: the update path is compiled out, not disabled at runtime -- a beta
        // build contains no code that can reach the update feed or replace itself.

        _ = Dispatcher.BeginInvoke(() =>
        {
            GC.Collect();
            GamerTune.Native.Psapi.TrimSelf();
        }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
    }

#if !BETA
    private async Task CheckForUpdatesAsync()
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(5));
            var info = await GamerTune.Services.UpdateService.CheckLatestAsync();
            if (info is null) return;
            var cfg = _store?.Load();
            if (cfg is null) return;
            if (cfg.SkippedUpdateVersion == info.Version) return;

            await Dispatcher.InvokeAsync(() =>
            {
                try
                {
                    var win = new GamerTune.UI.UpdateAvailableWindow(
                        info,
                        _store!,
                        onAppShouldExit: () =>
                        {
                            _tray?.Dispose();
                            _monitor?.Dispose();
                            Shutdown();
                        });
                    win.Show();
                }
                catch (Exception ex) { LogException("UpdateAvailable", ex); }
            });
        }
        catch (Exception ex) { LogException("UpdateCheck", ex); }
    }
#endif

    private void ShowSettings()
    {
        try
        {
            if (_settingsWindow is { IsLoaded: true })
            {
                _settingsWindow.Activate();
                return;
            }
            _settingsWindow = new SettingsWindow(_store!, _allMonitors!, exitApp: ExitApp, monitorService: _monitor);
            _settingsWindow.Saved += () => _monitor?.TriggerNow();
            _settingsWindow.Closed += (_, _) =>
            {
                ReleaseWindow(_settingsWindow);
                _settingsWindow = null;
                _ = Dispatcher.BeginInvoke(() =>
                {
                    System.Runtime.GCSettings.LargeObjectHeapCompactionMode = System.Runtime.GCLargeObjectHeapCompactionMode.CompactOnce;
                    GC.Collect(2, GCCollectionMode.Aggressive, blocking: true, compacting: true);
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                    GamerTune.Native.Psapi.TrimSelf();
                }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            };
            _settingsWindow.Show();
        }
        catch (Exception ex)
        {
            LogException("ShowSettings", ex);
        }
    }

    private void ExitApp()
    {
        _tray?.Dispose();
        _monitor?.Dispose();
        Shutdown();
    }

    /// <summary>
    /// True for any "this isn't a production build" flavor:
    ///  - Compile-time Debug builds (#if DEBUG)
    ///  - CI dev-builds whose InformationalVersion is stamped "{base}-dev.{sha}"
    ///    by .github/workflows/dev-build.yml
    /// Dev builds skip auto-update and skip Windows-startup registration so they
    /// don't interfere with the installed production app.
    /// </summary>
    public static bool IsDevBuild()
    {
#if DEBUG
        return true;
#else
        var info = typeof(App).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "";
        return info.Contains("-dev", StringComparison.OrdinalIgnoreCase)
            || info.Contains("-beta", StringComparison.OrdinalIgnoreCase);
#endif
    }

    /// <summary>
    /// Frees the visual tree associated with a Window so the heap can reclaim it.
    /// WPF won't release Content/DataContext refs on its own after Close.
    /// </summary>
    private static void ReleaseWindow(System.Windows.Window? window)
    {
        if (window is null) return;
        try
        {
            window.Content = null;
            window.DataContext = null;
        }
        catch { }
    }

    private static void LogException(string source, Exception? ex)
    {
        try
        {
            var path = AppIdentity.ErrorLogFile;
            // Cap at ~1 MB by rotating to .1
            try
            {
                var fi = new System.IO.FileInfo(path);
                if (fi.Exists && fi.Length > 1_000_000)
                {
                    var prev = path + ".1";
                    if (System.IO.File.Exists(prev)) System.IO.File.Delete(prev);
                    System.IO.File.Move(path, prev);
                }
            }
            catch { }
            System.IO.File.AppendAllText(path,
                $"[{DateTime.Now:s}] {source}: {ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}\n\n");
        }
        catch { }
    }

    private static void RunSelfTest()
    {
        var log = new List<string>();
        void Run(string name, Func<string> f)
        {
            try { log.Add($"OK   {name,-44} = {f()}"); }
            catch (Exception ex) { log.Add($"FAIL {name,-44} = {ex.GetType().Name}: {ex.Message}"); }
        }

        var asm = typeof(App).Assembly;
        Run("Assembly.GetName().Version", () => asm.GetName().Version?.ToString() ?? "(null)");
        Run("AssemblyInformationalVersion",
            () => asm.GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "(null)");
        Run("AssemblyFileVersion",
            () => asm.GetCustomAttribute<System.Reflection.AssemblyFileVersionAttribute>()?.Version ?? "(null)");
        Run("AssemblyVersion",
            () => asm.GetCustomAttribute<System.Reflection.AssemblyVersionAttribute>()?.Version ?? "(null)");
        Run("FileVersionInfo.ProductVersion", () =>
        {
            var p = Environment.ProcessPath;
            return string.IsNullOrEmpty(p) ? "(no path)"
                : System.Diagnostics.FileVersionInfo.GetVersionInfo(p).ProductVersion ?? "(null)";
        });
        Run("FileVersionInfo.FileVersion", () =>
        {
            var p = Environment.ProcessPath;
            return string.IsNullOrEmpty(p) ? "(no path)"
                : System.Diagnostics.FileVersionInfo.GetVersionInfo(p).FileVersion ?? "(null)";
        });

        Run("displays", () => string.Join(", ",
            GamerTune.Native.DisplayHelper.EnumerateActiveDisplays().Select(d => d.DisplayLabel)));
        Run("Shell32.IsFullscreenAppActive",
            () => GamerTune.Native.Shell32.IsFullscreenAppActive().ToString());
        Run("BenchmarkDetector.GetRunningBenchmark",
            () => GamerTune.Services.BenchmarkDetector.GetRunningBenchmark() ?? "(none)");

        Run("HagsMonitor.ReadCurrent",
            () => GamerTune.Monitors.HagsMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("MemoryIntegrityMonitor.ReadCurrent",
            () => GamerTune.Monitors.MemoryIntegrityMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("SystemResponsivenessMonitor.ReadCurrent",
            () => GamerTune.Monitors.SystemResponsivenessMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("NetworkThrottlingMonitor.ReadCurrent",
            () => GamerTune.Monitors.NetworkThrottlingMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("UsbSelectiveSuspendMonitor.ReadCurrent",
            () => GamerTune.Monitors.UsbSelectiveSuspendMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("GamesTaskProfileMonitor.ReadCurrent",
            () => GamerTune.Monitors.GamesTaskProfileMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("GameModeMonitor.ReadCurrent",
            () => GamerTune.Monitors.GameModeMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("GameDvrMonitor.ReadCurrent",
            () => GamerTune.Monitors.GameDvrMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("MousePrecisionMonitor.ReadCurrent",
            () => GamerTune.Monitors.MousePrecisionMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("FullscreenOptimizationsMonitor.ReadCurrent",
            () => GamerTune.Monitors.FullscreenOptimizationsMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("VrrMonitor.ReadCurrent",
            () => GamerTune.Monitors.VrrMonitor.ReadCurrent()?.ToString() ?? "(null)");
        Run("PowerPlanMonitor.GetActivePlan", () => GamerTune.Monitors.PowerPlanMonitor.GetActivePlan().ToString());
        Run("PowerPlanMonitor.ListAvailablePlans",
            () => string.Join(", ", GamerTune.Monitors.PowerPlanMonitor.ListAvailablePlans().Values));

        foreach (var d in GamerTune.Native.DisplayHelper.EnumerateActiveDisplays())
        {
            Run($"HDR[{d.DisplayLabel}]",
                () => GamerTune.Monitors.HdrMonitor.ReadHdrState(d) is { } s ? $"supported={s.Supported} enabled={s.Enabled}" : "(null)");
            Run($"Refresh[{d.DisplayLabel}]",
                () => GamerTune.Monitors.RefreshRateMonitor.GetCurrentRefresh(d.GdiDeviceName)?.ToString() ?? "(null)");
            Run($"Resolution[{d.DisplayLabel}]",
                () => GamerTune.Monitors.ResolutionMonitor.GetCurrent(d.GdiDeviceName)?.ToString() ?? "(null)");
        }

        var path = AppIdentity.SelfTestFile;
        System.IO.File.WriteAllLines(path, log);
        Environment.ExitCode = log.Any(l => l.StartsWith("FAIL")) ? 1 : 0;
    }
}
