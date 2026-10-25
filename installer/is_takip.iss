; Is Takip - Windows kurulum programi (Inno Setup)
[Setup]
AppName=Is Takip
AppVersion=2.1.0
AppPublisher=Is Takip
DefaultDirName={autopf}\IsTakip
DefaultGroupName=Is Takip
OutputBaseFilename=IsTakip-Kurulum
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\IsTakip.exe

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs

[Icons]
Name: "{group}\Is Takip"; Filename: "{app}\IsTakip.exe"
Name: "{autodesktop}\Is Takip"; Filename: "{app}\IsTakip.exe"

[Run]
Filename: "{app}\IsTakip.exe"; Description: "Is Takip'i simdi baslat"; Flags: nowait postinstall skipifsilent
