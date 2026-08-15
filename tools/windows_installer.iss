#define SourceDir GetEnv("POKOLENIE_RELEASE_DIR")
#define OutputDir GetEnv("POKOLENIE_OUTPUT_DIR")
#define AppVersion GetEnv("POKOLENIE_APP_VERSION")
#define IconFile GetEnv("POKOLENIE_ICON_FILE")

[Setup]
AppId={{D096F315-FF29-4B8A-97D7-835E86B76460}
AppName=Pokolenie WARP
AppVersion={#AppVersion}
AppPublisher=Pokolenie
DefaultDirName={autopf}\Pokolenie WARP
DefaultGroupName=Pokolenie WARP
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Pokolenie-WARP-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\pokolenie_vpn.exe
SetupIconFile={#IconFile}

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pokolenie WARP"; Filename: "{app}\pokolenie_vpn.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Pokolenie WARP"; Filename: "{app}\pokolenie_vpn.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Run]
Filename: "{sys}\sc.exe"; Parameters: "stop ""AmneziaWGTunnel$pokolenie-warp"""; Flags: runhidden waituntilterminated
Filename: "{sys}\sc.exe"; Parameters: "delete ""AmneziaWGTunnel$pokolenie-warp"""; Flags: runhidden waituntilterminated
Filename: "{app}\pokolenie_vpn.exe"; Description: "Запустить Pokolenie WARP"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\sc.exe"; Parameters: "stop ""AmneziaWGTunnel$pokolenie-warp"""; Flags: runhidden waituntilterminated; RunOnceId: "StopPokolenieTunnel"
Filename: "{sys}\sc.exe"; Parameters: "delete ""AmneziaWGTunnel$pokolenie-warp"""; Flags: runhidden waituntilterminated; RunOnceId: "DeletePokolenieTunnel"
