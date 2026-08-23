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
;    2. CODES DE RETOUR — liste EXACTE d'Inno Setup :
;         0  succes
;         1  echec d'initialisation de Setup
;         2  annule par l'utilisateur avant le debut de l'installation
;         3  erreur fatale pendant la preparation de la phase suivante
;         4  erreur fatale pendant l'installation
;         5  annule par l'utilisateur pendant l'installation
;         6  Setup termine de force par le debogueur
;         7  la phase « Preparing to Install » ne peut pas continuer
;         8  la phase « Preparing to Install » exige un redemarrage
;
;       ⚠ CORRECTION (23/08) : j'avais d'abord ecrit que cet installeur
;       renvoyait 1641 et 3010. C'EST FAUX. Ce sont des conventions de
;       Windows Installer ; Inno ne les emet QUE si on lui passe
;       /RESTARTEXITCODE=3010, ce que nous ne faisons pas. Les declarer
;       a Microsoft reviendrait a declarer du faux sur un point qu'un
;       relecteur peut tester. Ne pas les mettre.
;
;       Ce qu'on peut remplir honnetement dans la Partner Center :
;         Installation successful          -> 0
;         Installation cancelled by user   -> 2 et 5
;         Reboot required                  -> 8
;         Miscellaneous install failures   -> 1, 3, 4, 6, 7
;       Les autres scenarios (disque plein, reseau, deja installe...)
;       n'ont AUCUN code dedie dans Inno : on les laisse VIDES. Un champ
;       vide ne bloque pas la certification ; un champ faux, si.
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
; Le rapport de certification n'a pas pu CONSTATER l'installation
; silencieuse. /VERYSILENT suffit en principe, mais on retire en plus
; toute page susceptible de s'afficher : moins il reste de surfaces,
; moins il reste de doute pour le robot comme pour le relecteur.
DisableWelcomePage=yes
DisableFinishedPage=yes
DisableReadyPage=yes
; Desinstallation silencieuse declaree : sans QuietUninstallString, le
; Store ne peut pas desinstaller proprement l'application.
Uninstallable=yes
;  INSTALLATION POUR TOUTE LA MACHINE — choix REVU le 23/08.
;
;  J'avais d'abord mis `lowest` pour eviter l'elevation UAC : un
;  avertissement de moins pour le client. C'etait un mauvais calcul
;  pour une app soumise au Store, et voici pourquoi.
;
;  Avec `lowest`, Inno installe PAR UTILISATEUR et ecrit l'entree
;  « Applications installees » dans HKCU. Le bac a sable de Microsoft
;  inspecte HKLM, et sous un autre compte : il ne voit alors RIEN, et
;  rend « We could not identify the app name and the publisher name »
;  — exactement les trois indeterminations du rapport de
;  certification. Le correctif des metadonnees ne suffirait pas :
;  le scanner ne trouverait toujours pas l'entree.
;
;  Et l'argument UAC ne tient pas : la documentation Microsoft
;  l'autorise explicitement pendant une installation silencieuse —
;  « Initiating the install must not display an installation user
;  interface (i.e., silent install is required), however a User
;  Account Control (UAC) dialog is allowed. »
;
;  `PrivilegesRequiredOverridesAllowed=commandline` garde la porte
;  ouverte : /CURRENTUSER permet toujours une installation sans
;  droits administrateur a qui en a besoin.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
; Le Store lit ces metadonnees pour l'entree « Applications installees ».
;  Ces champs sont ceux que Windows affiche dans la boite UAC et dans
;  l'ecran SmartScreen — donc ce que le client voit VRAIMENT au moment
;  d'installer. Ils sont INDEPENDANTS de ceux de l'application : les
;  corriger dans Runner.rc ne les corrige pas ici.
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}. All rights reserved.

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
