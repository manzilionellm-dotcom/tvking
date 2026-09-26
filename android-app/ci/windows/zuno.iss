; =========================================================
;  zuno.iss — Installeur Windows de Zuno (Inno Setup 6)
; =========================================================
;  Compilé par .github/workflows/build-zuno-windows.yml :
;      iscc /DAppVersion=<n> /DSourceDir=<dossier Release> zuno.iss
;
;  Reprend les choix VÉRIFIÉS de l'ancien installeur 7 MOTION (voir
;  l'historique git de windows/installer/7motion.iss) :
;    • installation silencieuse possible (/VERYSILENT /NORESTART) ;
;    • installation pour toute la machine (entrée « Applications
;      installées » dans HKLM, visible par Windows et le Store) ;
;    • AppId FIXE : une nouvelle version REMPLACE l'ancienne au lieu
;      d'ajouter une seconde entrée (mise à jour propre) ;
;    • pas de signature Authenticode tant qu'aucun certificat n'existe
;      (SmartScreen affichera « éditeur inconnu » — dire « Exécuter quand
;      même ») ; l'emplacement SignTool est prévu, commenté.
;  La VERSION est injectée par le build, jamais codée en dur.
; =========================================================

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName        "Zuno"
#define AppPublisher   "Zuno"
#define AppExeName     "tv_king.exe"
#define AppUrl         "https://app.7themotion.com"

[Setup]
; Identifiant PROPRE à Zuno (≠ ancien 7 MOTION) : ne jamais le changer.
AppId={{5D2E8C41-7A93-4B6F-9E10-3C8B2F7D6A15}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=Zuno-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=yes
DisableReadyPage=yes
Uninstallable=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=app_icon.ico
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}. All rights reserved.
; SignTool=signtool sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 $f
; SignedUninstaller=yes

[Languages]
Name: "french";  MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; TOUT le dossier Release : l'exécutable a besoin de ses .dll voisines
; (dont libmpv, le moteur de lecture vidéo) et du dossier data\.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
