using Microsoft.Win32;

namespace GamerTune.Services;

public static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>A beta build registers under its own value name rather than being
    /// skipped: launch-at-startup is a feature testers need to exercise, and a
    /// shared name would have the two builds overwrite each other's entry.</summary>
    private const string ValueName = AppIdentity.StartupRegistryValueName;

    public static bool IsRegistered()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
        return key?.GetValue(ValueName) is string;
    }

    public static void Register()
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe)) return;
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true)!;
        key.SetValue(ValueName, $"\"{exe}\" --tray");
    }

    public static void Unregister()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        key?.DeleteValue(ValueName, throwOnMissingValue: false);
    }

    public static void Sync(bool desired)
    {
        RemoveLegacyEntry();
        if (desired && !IsRegistered()) Register();
        else if (!desired && IsRegistered()) Unregister();
    }

    /// <summary>Deletes the pre-rename (GamerGuardian) Run value. The upgrade
    /// removes the old executable, so left alone it would point at nothing; the
    /// current entry is re-created under the new name by <see cref="Sync"/>.</summary>
    private static void RemoveLegacyEntry()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            key?.DeleteValue(AppIdentity.LegacyStartupRegistryValueName, throwOnMissingValue: false);
        }
        catch
        {
            // Best-effort cleanup; never block startup registration on it.
        }
    }
}
