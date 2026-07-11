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
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checkedonce
Name: "startup"; Description: "Start PosEx when Windows starts"; GroupDescription: "Startup:"; Flags: checkedonce

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "launch_posex.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\vc_redist.x64.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\PosEx"; Filename: "{app}\launch_posex.cmd"; IconFilename: "{app}\posex_app.exe"
Name: "{autoprograms}\PosEx"; Filename: "{app}\launch_posex.cmd"; IconFilename: "{app}\posex_app.exe"
Name: "{autodesktop}\PosEx"; Filename: "{app}\launch_posex.cmd"; IconFilename: "{app}\posex_app.exe"; Tasks: desktopicon
Name: "{userstartup}\PosEx"; Filename: "{app}\launch_posex.cmd"; IconFilename: "{app}\posex_app.exe"; Tasks: startup

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "PosEx"; ValueData: """{app}\launch_posex.cmd"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
Filename: "{app}\launch_posex.cmd"; Description: "Launch PosEx"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    if Installed = 1 then
    begin
      Result := False;
      Exit;
    end;
  end;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    if Installed = 1 then
      Result := False;
  end;
end;
