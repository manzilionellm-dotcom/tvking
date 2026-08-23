; =========================================================
;  7motion.iss — Installeur Windows de 7 MOTION (Inno Setup)
; =========================================================
;  POURQUOI CE FICHIER EXISTE (23/08/2026).
;
;  Jusqu'ici la chaine de build ne produisait qu'un .zip. Le
;  « 7MOTION-Setup.exe » publie le 7 aout avait ete fabrique A LA MAIN,
;  une fois, et RIEN ne le regenerait. Consequences en chaine :
;
;    • le lien /win servait un installeur fige au 7 aout, alors que
;      l'application, elle, avancait ;
;    • impossible de publier une mise a jour Windows sans casser soit
;      la distribution directe, soit la soumission au Microsoft Store ;
;    • verifie le 23/08 en lisant l'en-tete PE : ce fichier n'a AUCUNE
;      signature Authenticode (repertoire de securite de taille nulle).
;
;  CE QUE CET INSTALLEUR GARANTIT, et que le Store exige :
;
;    1. INSTALLATION SILENCIEUSE. Inno Setup gere nativement /SILENT et
;       /VERYSILENT. Avec /VERYSILENT /NORESTART, aucune fenetre ne
;       s'affiche et le code de retour vaut 0. C'est l'exigence
;       « silent install » du Microsoft Store.
;
;    2. CODES DE RETOUR CONNUS, a declarer dans la Partner Center :
;         0    succes
;         1    echec d'initialisation de l'installeur
;         2    annule par l'utilisateur avant le debut de la copie
;         3    erreur fatale pendant la preparation
;         5    annule par l'utilisateur pendant l'installation
;         1641 succes, un redemarrage a ete declenche
;         3010 succes, un redemarrage est requis
;
;    3. DESINSTALLATION propre, avec une entree « Applications
;       installees » au nom exact de l'editeur.
;
;  CE QU'IL NE FAIT PAS ENCORE : signer le binaire. L'emplacement est
;  prevu (voir SignTool plus bas, commente) et s'activera le jour ou un
;  certificat existera — sans toucher au reste.
;
;  La VERSION est injectee par la chaine de build (/DAppVersion=...) :
;  elle ne doit JAMAIS etre codee en dur ici, sinon deux builds
;  differents porteraient le meme numero.
; =========================================================

#ifndef AppVersion
  ; Repli pour une compilation manuelle. La chaine de build passe
  ; toujours la vraie version : ce 0.0.0 ne doit jamais etre publie.
  #define AppVersion "0.0.0"
#endif

#define AppName        "7 MOTION"
#define AppPublisher   "7 MOTION"
#define AppExeName     "tv_king.exe"
#define AppUrl         "https://app.7themotion.com"

[Setup]
; AppId identifie l'application pour les MISES A JOUR et la
; desinstallation. Le changer ferait apparaitre une seconde entree dans
; « Applications installees » au lieu de remplacer la premiere : il ne
; doit jamais bouger.
AppId={{7A1C4E92-2B6D-4F51-9C3A-0D5E7B21C4F8}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=7MOTION-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; INSTALLATION PAR UTILISATEUR, pas pour toute la machine : evite la
; demande d'elevation UAC. Un avertissement de moins pour le client,
; et l'installation silencieuse fonctionne sans droits administrateur.
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
; Le Store lit ces metadonnees pour l'entree « Applications installees ».
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}

; SIGNATURE — a activer le jour ou un certificat existe. Rien d'autre
; ne changera dans ce fichier ni dans la chaine de build.
; SignTool=signtool sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 $f
; SignedUninstaller=yes

[Languages]
Name: "french";  MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; TOUT le dossier Release : l'executable ne fonctionne pas seul, il lui
; faut ses .dll voisines (dont libmpv, le moteur de lecture video).
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";          Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}";    Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; `nowait postinstall skipifsilent` : on propose de lancer l'app a la
; fin d'une installation INTERACTIVE, et jamais en mode silencieux —
; sinon une installation automatisee ouvrirait une fenetre, ce que le
; Store interdit precisement.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent
