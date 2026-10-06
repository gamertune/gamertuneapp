; GamerTune Inno Setup script
; Build with: ISCC.exe installer\GamerTune.iss
; Override version at the command line: ISCC.exe /DAppVersion=1.2.3 installer\GamerTune.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName       "GamerTune"
#define AppPublisher  "GamerTune Contributors"
#define AppURL        "https://github.com/gamertune/gamertuneapp"
#define AppExeName    "GamerTune.exe"
#define PublishDir    "..\publish"

; Pre-rename identity. This installer keeps the GamerGuardian AppId so it
; upgrades that install in place; these names drive the migration cleanup.
#define LegacyName       "GamerGuardian"
#define LegacyExeName    "GamerGuardian.exe"
#define LegacyDefaultDir "{userpf}\GamerGuardian"

[Setup]
; Unchanged from GamerGuardian on purpose: same AppId = in-place upgrade, one
; Add/Remove Programs entry. Do not change it.
AppId={{B6C2D7E1-9F1B-4F32-9A8C-3D6F0A7E6B11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={userpf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=GamerTune-Setup-{#AppVersion}
SetupIconFile=..\src\GamerTune\Assets\AppIcon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
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
; Leftovers from the pre-rename GamerGuardian install this one upgrades over
; (same AppId). The old executable is removed from a custom install folder that
; is being reused; the default old folder, Start Menu group and desktop
; shortcut go entirely. The old uninstaller is superseded by this install's.
Type: files; Name: "{app}\{#LegacyExeName}"
Type: filesandordirs; Name: "{#LegacyDefaultDir}"
Type: filesandordirs; Name: "{autoprograms}\{#LegacyName}"
Type: files; Name: "{userdesktop}\{#LegacyName}.lnk"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -Command ""Get-Process -Name GamerTune -ErrorAction SilentlyContinue | Stop-Process -Force"""; Flags: runhidden; RunOnceId: "StopGamerTune"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\GamerTune"
; Settings folder left behind by the pre-rename app (migrated, never deleted on upgrade).
Type: filesandordirs; Name: "{userappdata}\{#LegacyName}"

[Code]
var
  PreviousAppDir: String;

// An upgrade from GamerGuardian (same AppId) would otherwise reuse the old
// default folder. Move it to the GamerTune default; a custom folder is kept.
procedure InitializeWizard();
begin
  PreviousAppDir := WizardForm.DirEdit.Text;
  if CompareText(PreviousAppDir, ExpandConstant('{#LegacyDefaultDir}')) = 0 then
    WizardForm.DirEdit.Text := ExpandConstant('{userpf}\{#AppName}');
end;

// Restart Manager only closes processes holding files under the new {app}, so a
// running GamerGuardian must be stopped explicitly before its files are deleted.
// Filtered on the previous install folder: the old beta also ran as
// GamerGuardian.exe and must not be killed by a stable upgrade.
// Its startup entry would point at the removed executable; the app re-registers
// under the new name on first launch.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec('powershell.exe',
    '-NoProfile -Command "Get-Process -Name {#LegacyName} -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''' + PreviousAppDir + '\*'' } | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#LegacyName}');
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RootKey: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    RootKey := HKEY_CURRENT_USER;
    RegDeleteValue(RootKey, 'Software\Microsoft\Windows\CurrentVersion\Run', 'GamerTune');
    RegDeleteValue(RootKey, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#LegacyName}');
  end;
end;
