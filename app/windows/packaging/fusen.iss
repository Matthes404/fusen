; Installer für Windows (Inno Setup 6).
;
; Die Release-Pipeline baut ihn so:
;   iscc /DAppVersion=0.2.0 /DBundleDir=<Release-Ordner> /DOutputDir=<Ziel> fusen.iss
;
; Installiert ohne Administratorrechte nach %LOCALAPPDATA%\Programs\Fusen –
; wer für alle Benutzer installieren will, wählt das im ersten Dialog.
; Die Zettel liegen nicht im Programmordner, sondern unter %APPDATA%, und
; überstehen deshalb Update und Deinstallation.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "fusen-" + AppVersion + "-windows-setup"
#endif
; Die Dateiversion kennt nur Zahlen: aus 0.2.0-dev.14 wird 0.2.0.
#if Pos("-", AppVersion) > 0
  #define NumericVersion Copy(AppVersion, 1, Pos("-", AppVersion) - 1)
#else
  #define NumericVersion AppVersion
#endif

[Setup]
; Die AppId verbindet ein Update mit der installierten Version – nie ändern.
AppId={{B541A5C4-033D-4A57-AFEC-341C3015E56C}
AppName=Fusen
AppVersion={#AppVersion}
AppVerName=Fusen {#AppVersion}
AppPublisher=the Fusen contributors
AppPublisherURL=https://github.com/Matthes404/fusen
AppSupportURL=https://github.com/Matthes404/fusen/issues
AppUpdatesURL=https://github.com/Matthes404/fusen/releases
DefaultDirName={autopf}\Fusen
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\fusen.exe
UninstallDisplayName=Fusen
VersionInfoVersion={#NumericVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Läuft Fusen noch, schließt der Installer es vor dem Überschreiben.
CloseApplications=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Fusen"; Filename: "{app}\fusen.exe"
Name: "{autodesktop}\Fusen"; Filename: "{app}\fusen.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fusen.exe"; Description: "{cm:LaunchProgram,Fusen}"; Flags: nowait postinstall skipifsilent
