; GamerTune BETA Inno Setup script
;
; Build with: ISCC.exe /DAppVersion=1.2.3 installer\GamerTune-Beta.iss
; Expects the BETA payload in ..\publish-beta (publish with -p:Beta=true).
;
; Every identity this script declares is deliberately distinct from
; GamerTune.iss so a beta install sits alongside a stable one instead of
; upgrading over it: AppId, AppName, install directory, Start Menu group,
; uninstall entry, and output filename. The uninstall cleanup targets the beta
; config root and the beta Run value, which AppIdentity.cs defines under the
; BETA compile constant -- these strings must stay in step with that file.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName       "GamerTune Beta"
#define AppPublisher  "GamerTune Contributors"
#define AppURL        "https://github.com/gamertune/gamertuneapp"
#define AppExeName    "GamerTune.exe"
#define PublishDir    "..\publish-beta"

; Must match AppIdentity.ProductFolderName and AppIdentity.StartupRegistryValueName
; under BETA.
#define BetaConfigDir "GamerTune-Beta"
#define BetaRunValue  "GamerTune-Beta"

; Pre-rename (GamerGuardian Beta) identity. The AppId below is unchanged from
; that installer so it upgrades the old beta in place; these names drive the
; migration cleanup. Must match AppIdentity.Legacy* under BETA.
#define LegacyName          "GamerGuardian Beta"
#define LegacyExeName       "GamerGuardian.exe"
#define LegacyDefaultDir    "{userpf}\GamerGuardian Beta"
#define LegacyBetaConfigDir "GamerGuardian-Beta"
#define LegacyBetaRunValue  "GamerGuardian-Beta"

[Setup]
; Distinct from the stable AppId (B6C2D7E1-...). Sharing it would make this
; installer upgrade over -- and then uninstall -- the stable install.
AppId={{9EC25C38-17D8-4AEC-B25B-A914B8C90C98}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={userpf}\GamerTune Beta
DefaultGroupName=GamerTune Beta
DisableProgramGroupPage=yes
DisableDirPage=auto
; Per-user, same as stable -- no elevation to install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=GamerTune-Beta-Setup-{#AppVersion}
SetupIconFile=..\src\GamerTune\Assets\AppIcon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
; Restart Manager works off the files being written under {app}, so this only
; targets a running beta -- it will not close a stable install.
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#PublishDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[InstallDelete]
; Leftovers from the pre-rename GamerGuardian Beta install this one upgrades
; over (same AppId): the old executable in a reused custom folder, and the old
; default folder, Start Menu group and desktop shortcut.
Type: files; Name: "{app}\{#LegacyExeName}"
Type: filesandordirs; Name: "{#LegacyDefaultDir}"
Type: filesandordirs; Name: "{autoprograms}\{#LegacyName}"
Type: files; Name: "{userdesktop}\{#LegacyName}.lnk"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Both flavors ship an executable named GamerTune.exe, so stopping by name
; alone would kill a running STABLE install while uninstalling the beta. Filter
; on the image path so only the beta process is stopped.
Filename: "powershell.exe"; Parameters: "-NoProfile -Command ""Get-Process -Name GamerTune -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -like '{app}\*' } | Stop-Process -Force"""; Flags: runhidden; RunOnceId: "StopGamerTuneBeta"

[UninstallDelete]
; The beta's own config roots only (current and pre-rename). The stable roots
; are never touched -- a beta uninstall must not take the user's real settings.
Type: filesandordirs; Name: "{userappdata}\{#BetaConfigDir}"
Type: filesandordirs; Name: "{userappdata}\{#LegacyBetaConfigDir}"

[Code]
var
  PreviousAppDir: String;

// An upgrade from GamerGuardian Beta (same AppId) would otherwise reuse the old
// default folder. Move it to the GamerTune Beta default; a custom folder is kept.
procedure InitializeWizard();
begin
  PreviousAppDir := WizardForm.DirEdit.Text;
  if CompareText(PreviousAppDir, ExpandConstant('{#LegacyDefaultDir}')) = 0 then
    WizardForm.DirEdit.Text := ExpandConstant('{userpf}\{#AppName}');
end;

// Stop a running pre-rename beta before its files are deleted. The old stable
// app also ran as GamerGuardian.exe, so filter on the previous beta folder.
// The old beta Run value is removed; the app re-registers under the new name.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec('powershell.exe',
    '-NoProfile -Command "Get-Process -Name GamerGuardian -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''' + PreviousAppDir + '\*'' } | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#LegacyBetaRunValue}');
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RootKey: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    RootKey := HKEY_CURRENT_USER;
    // Beta's own Run values only; the stable entries are left alone.
    RegDeleteValue(RootKey, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#BetaRunValue}');
    RegDeleteValue(RootKey, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#LegacyBetaRunValue}');
  end;
end;
