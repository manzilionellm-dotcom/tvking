; ============================================================================
;  installer.iss — Installateur Windows de 7 MOTION
; ============================================================================
;  POURQUOI un installateur, alors qu'un .zip existe deja.
;
;  Une application Windows n'est jamais un fichier unique : c'est un
;  executable ENTOURE de ses bibliotheques, dont libmpv qui assure la
;  lecture video. Le .zip oblige donc le client a decompresser, a ne
;  surtout pas sortir l'.exe de son dossier, puis a passer l'avertissement
;  SmartScreen. Trois occasions d'abandonner avant d'avoir vu l'app.
;
;  Ici : un fichier, un double-clic, un raccourci. Le .zip reste publie a
;  cote pour ceux qui preferent ne rien installer.
;
;  RELDIR est passe par le workflow (/DRELDIR=...) : le dossier natif
;  windows/ n'est pas versionne, il est regenere a chaque build, donc son
;  chemin ne peut pas etre ecrit en dur ici.
; ============================================================================

#ifndef RELDIR
  #define RELDIR "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppName=7 MOTION
AppVersion=1.0.0
AppPublisher=7 MOTION
DefaultDirName={autopf}\7 MOTION
DefaultGroupName=7 MOTION
OutputDir=.
OutputBaseFilename=7MOTION-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Installation POUR L'UTILISATEUR COURANT : aucune demande de mot de passe
; administrateur. Une friction de moins, et rien dans cette app ne justifie
; des droits systeme.
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
; TOUT le dossier Release, sous-dossiers compris (data\ contient les
; ressources Flutter). Omettre un seul fichier ici donne une application
; qui se lance et reste noire.
Source: "{#RELDIR}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\7 MOTION"; Filename: "{app}\tv_king.exe"
Name: "{group}\Desinstaller 7 MOTION"; Filename: "{uninstallexe}"
Name: "{autodesktop}\7 MOTION"; Filename: "{app}\tv_king.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Creer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Run]
Filename: "{app}\tv_king.exe"; Description: "Lancer 7 MOTION"; Flags: nowait postinstall skipifsilent
