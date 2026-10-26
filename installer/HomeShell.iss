; Everything Bar installer (Inno Setup 6). Per-user: no admin rights, nothing in system folders.
; Build:  flutter build windows --release   then compile this file with Inno Setup.
#define AppName "Everything Bar"
#define AppExe "Everything Bar.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; Kept the same as the first version so an update replaces it instead of installing twice.
AppId={{6F3B1D0C-4E5A-4C8B-9A71-HOMESHELL0001}
AppName={#AppName}
AppVersion=0.3.1
DefaultDirName={localappdata}\HomeShell
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=EverythingBar-Setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Put an Everything Bar shortcut on the desktop"

[InstallDelete]
; Old name from the first version.
Type: files; Name: "{app}\home_shell.exe"

[Files]
Source: "{#BuildDir}\home_shell.exe"; DestDir: "{app}"; DestName: "{#AppExe}"; Flags: ignoreversion
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "home_shell.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Same startup entry the app uses itself; removed on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "HomeShell"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue

; Windows' own on/off switch for startup apps: make sure it says "on".
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueType: binary; ValueName: "HomeShell"; ValueData: 02 00 00 00 00 00 00 00 00 00 00 00; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "Start {#AppName} now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Resume anything the bar had paused, then close it.
Filename: "{app}\{#AppExe}"; Parameters: "--thaw"; Flags: runhidden waituntilterminated; RunOnceId: "ThawEverythingBar"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM ""{#AppExe}"""; Flags: runhidden; RunOnceId: "KillEverythingBar"

[UninstallDelete]
; Anything left in the program folder goes too.
Type: filesandordirs; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if UninstallSilent then
      DelTree(ExpandConstant('{userappdata}\HomeShell'), True, True, True)
    else if MsgBox('Also remove your saved bar items, settings and cached icons?' + #13#10 + #13#10 +
                   'Choose Yes for a complete clean removal (nothing of Everything Bar is left on this PC).' + #13#10 +
                   'Choose No to keep them in case you reinstall.', mbConfirmation, MB_YESNO) = IDYES then
      DelTree(ExpandConstant('{userappdata}\HomeShell'), True, True, True);
  end;
end;
