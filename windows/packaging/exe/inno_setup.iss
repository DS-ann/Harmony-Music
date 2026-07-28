[Setup]
AppId=B9F6E402-0CAE-4045-BDE6-14BD6C39C4EA
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
AppVersion={#AppVersion}
AppName=Harmony Music
AppPublisher=anandnet
AppPublisherURL=https://github.com/anandnet/Harmony-Music
AppSupportURL=https://github.com/anandnet/Harmony-Music
AppUpdatesURL=https://github.com/anandnet/Harmony-Music
DefaultDirName={autopf}\harmonymusic
DisableProgramGroupPage=yes
OutputDir=.
#ifndef OutputBaseFilename
  #define OutputBaseFilename "harmonymusic-setup"
#endif
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
WizardStyle=modern
PrivilegesRequired=lowest
LicenseFile=..\..\LICENSE
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\harmonymusic.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\Harmony Music"; Filename: "{app}\harmonymusic.exe"
Name: "{autodesktop}\Harmony Music"; Filename: "{app}\harmonymusic.exe"; Tasks: desktopicon

; Auth0 Windows login returns to this per-user URL protocol. The setup runs
; without elevation, so the registration intentionally lives in HKCU.
[Registry]
Root: "HKCU"; Subkey: "Software\Classes\harmonymusic"; ValueType: string; ValueName: ""; ValueData: "URL:Harmony Music Protocol"; Flags: uninsdeletekey
Root: "HKCU"; Subkey: "Software\Classes\harmonymusic"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: "HKCU"; Subkey: "Software\Classes\harmonymusic\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\harmonymusic.exe"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\harmonymusic.exe"; Description: "{cm:LaunchProgram,{#StringChange('Harmony Music', '&', '&&')}}"; Flags: nowait postinstall skipifsilent
