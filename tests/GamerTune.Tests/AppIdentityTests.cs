using System;
using System.IO;
using GamerTune.Services;
using Xunit;

namespace GamerTune.Tests;

/// <summary>
/// Pins the per-flavor identity.
///
/// <para>In a default build these assert the exact literals the code used before
/// <see cref="AppIdentity"/> existed — the enforced proof that a stable build's
/// paths, mutex name and startup entry are behaviorally unchanged.</para>
///
/// <para>Built with <c>-p:Beta=true</c> they assert the beta identity instead, so
/// <c>dotnet test -p:Beta=true</c> proves a beta build really is isolated: its own
/// config root, its own mutex, its own startup entry, its own diagnostics. Asserting
/// the stable values against a beta build would fail an app that is behaving
/// correctly.</para>
/// </summary>
public class AppIdentityTests
{
    private static string AppData => Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

#if BETA
    private const string Folder = "GamerTune-Beta";
    private const string DiagPrefix = "gamertune-beta";
    private const string Mutex = "GamerTune.SingleInstance.Beta";
    private const string RunValue = "GamerTune-Beta";
    private const string LegacyFolder = "GamerGuardian-Beta";
    private const string LegacyRunValue = "GamerGuardian-Beta";
#else
    private const string Folder = "GamerTune";
    private const string DiagPrefix = "gamertune";
    private const string Mutex = "GamerTune.SingleInstance";
    private const string RunValue = "GamerTune";
    private const string LegacyFolder = "GamerGuardian";
    private const string LegacyRunValue = "GamerGuardian";
#endif

    [Fact]
    public void ProductFolder_MatchesTheFlavor()
    {
        Assert.Equal(Folder, AppIdentity.ProductFolderName);
        Assert.Equal(Path.Combine(AppData, Folder), AppIdentity.ConfigDirectory);
    }

    [Fact]
    public void ConfigAndChangeLog_ShareTheFlavorRoot()
    {
        Assert.Equal(Path.Combine(AppData, Folder, "config.json"), AppIdentity.ConfigFile);
        Assert.Equal(Path.Combine(AppData, Folder, "changes.log"), AppIdentity.ChangeLogFile);
    }

    [Fact]
    public void DiagnosticPaths_MatchTheFlavor()
    {
        Assert.Equal(DiagPrefix, AppIdentity.DiagnosticPrefix);
        Assert.Equal(Path.Combine(Path.GetTempPath(), DiagPrefix + "_error.log"), AppIdentity.ErrorLogFile);
        Assert.Equal(Path.Combine(Path.GetTempPath(), DiagPrefix + "_selftest.txt"), AppIdentity.SelfTestFile);
    }

    [Fact]
    public void MutexAndStartupNames_MatchTheFlavor()
    {
        Assert.Equal(Mutex, AppIdentity.MutexName);
        Assert.Equal(RunValue, AppIdentity.StartupRegistryValueName);
    }

    [Fact]
    public void LegacyIdentity_PointsAtThisFlavorsPreRenameNames()
    {
        // The GamerGuardian -> GamerTune migration reads settings from here and
        // removes this Run value. Pinned to the exact names the old app used:
        // a typo would silently strand every upgrading user's settings.
        Assert.Equal(Path.Combine(AppData, LegacyFolder), AppIdentity.LegacyConfigDirectory);
        Assert.Equal(LegacyRunValue, AppIdentity.LegacyStartupRegistryValueName);
        Assert.NotEqual(AppIdentity.ConfigDirectory, AppIdentity.LegacyConfigDirectory);
    }

    [Fact]
    public void StableConfigDirectory_AlwaysPointsAtTheStableRoot()
    {
        // The seed source. In a stable build it is the same folder as
        // ConfigDirectory (making the seed inert); in a beta build it is the
        // separate stable install's folder, which the beta only ever reads.
        Assert.Equal(Path.Combine(AppData, "GamerTune"), AppIdentity.StableConfigDirectory);
    }

    [Fact]
    public void ConfigStore_ResolvesToTheSamePathsAsAppIdentity()
    {
        // The whole point of the shared source: ConfigStore and ChangeLogger used to
        // build this path independently and could drift apart.
        var store = new ConfigStore();
        Assert.Equal(AppIdentity.ConfigDirectory, store.ConfigDirectory);
        Assert.Equal(AppIdentity.ConfigFile, store.ConfigPath);
    }

    [Fact]
    public void ChangeLogger_WritesIntoTheSameFolderAsTheConfig()
    {
        Assert.Equal(AppIdentity.ChangeLogFile, ChangeLogger.LogPath);
        Assert.Equal(
            Path.GetDirectoryName(AppIdentity.ConfigFile),
            Path.GetDirectoryName(ChangeLogger.LogPath));
    }

#if BETA
    [Fact]
    public void BetaBuild_IsIsolatedFromStable()
    {
        // The isolation guarantee, asserted directly rather than inferred.
        Assert.NotEqual(AppIdentity.ConfigDirectory, AppIdentity.StableConfigDirectory);
        Assert.Contains("Beta", AppIdentity.ProductFolderName, StringComparison.Ordinal);
        Assert.EndsWith(".Beta", AppIdentity.MutexName, StringComparison.Ordinal);
    }

    [Fact]
    public void BetaBuild_CarriesAVisibleMarker()
    {
        Assert.NotEqual(string.Empty, AppIdentity.DisplaySuffix);
        Assert.Contains("BETA", AppIdentity.DisplaySuffix, StringComparison.Ordinal);
    }
#else
    [Fact]
    public void StableBuild_DisplaySuffix_IsEmpty_SoTitlesAreUnchanged()
    {
        // Callers concatenate this unconditionally; empty is what keeps the stable
        // window title and tray tooltip byte-identical to before.
        Assert.Equal(string.Empty, AppIdentity.DisplaySuffix);
        Assert.Equal("GamerTune", "GamerTune" + AppIdentity.DisplaySuffix);
        Assert.Equal("GamerTune - Settings", "GamerTune - Settings" + AppIdentity.DisplaySuffix);
    }

    [Fact]
    public void StableBuild_SeedIsInert_BecauseSourceAndTargetMatch()
    {
        Assert.Equal(AppIdentity.ConfigDirectory, AppIdentity.StableConfigDirectory);
        Assert.False(ConfigStore.SeedConfigFrom(
            AppIdentity.StableConfigDirectory, AppIdentity.ConfigDirectory));
    }
#endif
}
