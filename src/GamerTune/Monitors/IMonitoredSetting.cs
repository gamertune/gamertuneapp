using GamerTune.Models;

namespace GamerTune.Monitors;

public interface IMonitoredSetting
{
    string Id { get; }
    IEnumerable<DriftItem> CheckDrift(AppConfig config);
}
