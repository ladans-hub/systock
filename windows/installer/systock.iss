#define AppName "Systock"
#define AppVersion "1.0.0"
#define AppPublisher "Ladans"
#define AppExeName "Systock.exe"

[Setup]
AppId={{A7A78C05-9F36-42CB-9673-18041127E552}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Systock
DefaultGroupName=Systock
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows-installer
OutputBaseFilename=Systock-Setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\Systock"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Systock"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando componentes Microsoft Visual C++..."; Flags: waituntilterminated; Check: VCRuntimeMissing
Filename: "{app}\{#AppExeName}"; Description: "Abrir Systock"; Flags: nowait postinstall skipifsilent

[Code]
function VCRuntimeMissing: Boolean;
var
  Installed: Cardinal;
begin
  Result := not RegQueryDWordValue(
    HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed',
    Installed
  ) or (Installed <> 1);
end;
