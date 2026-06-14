; PosEx Windows installer — single Setup.exe (like Android APK for first install).
; CI passes /DAppVersion=1.0.N and /DReleaseDir=... before compiling.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#ifndef ReleaseDir
  #define ReleaseDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName=PosEx
AppVersion={#AppVersion}
AppPublisher=PosEx
DefaultDirName={autopf}\PosEx
DefaultGroupName=PosEx
OutputBaseFilename=PosEx-Setup
OutputDir=..\build\installer
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\posex_app.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PosEx"; Filename: "{app}\posex_app.exe"
Name: "{autodesktop}\PosEx"; Filename: "{app}\posex_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\posex_app.exe"; Description: "Launch PosEx"; Flags: nowait postinstall skipifsilent
