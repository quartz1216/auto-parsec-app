#define MyAppName "Auto Parsec"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Auto Parsec"

[Setup]
AppId={{37E6FB4D-1863-46A7-9BC7-E072C2C39D85}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\AutoParsec
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\output
OutputBaseFilename=AutoParsecSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={sys}\WindowsPowerShell\v1.0\powershell.exe

[Tasks]
Name: "startup"; Description: "Start Auto Parsec when Windows starts"; Flags: unchecked

[Files]
Source: "..\AutoParsecTray.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\AutoParsecTray.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\auto-parsec.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\settings.template.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\modules\*"; DestDir: "{app}\modules"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\examples\*"; DestDir: "{app}\examples"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Auto Parsec"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\AutoParsecTray.vbs"""; WorkingDir: "{app}"
Name: "{group}\Settings"; Filename: "notepad.exe"; Parameters: """{userappdata}\AutoParsec\settings.json"""
Name: "{group}\Uninstall Auto Parsec"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "AutoParsec"; ValueData: """{sys}\wscript.exe"" ""{app}\AutoParsecTray.vbs"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\AutoParsecTray.vbs"""; WorkingDir: "{app}"; Description: "Launch Auto Parsec"; Flags: nowait postinstall skipifsilent unchecked

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'AutoParsec');
  end;
end;
