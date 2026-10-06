using System.Text.Json.Serialization;

namespace GamerTune.Models;

/// <summary>
/// Static metadata for a Windows scheduled task that GamerTune can disable.
/// Lives in <see cref="GamerTune.Services.ScheduledTaskCatalog"/>; per-user
/// prefs live in <see cref="AppConfig.ScheduledTasks"/> keyed by <see cref="TaskPath"/>.
/// </summary>
public sealed record ScheduledTaskDefinition(
    string TaskPath,
    string DisplayName,
    string Description,
    ScheduledTaskTarget? RecommendedTarget = null);

/// <summary>
/// What state the user wants a scheduled task kept in. <see cref="Default"/> means
/// "don't manage this" — leave the task as Windows ships it (enabled). <see cref="Disabled"/>
/// is an explicit target: keep the task disabled and re-disable it if Windows re-enables it.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ScheduledTaskTarget
{
    Default,
    Disabled,
}
