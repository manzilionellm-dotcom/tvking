"""Personnalise le runner généré sans maintenir une copie de Flutter."""
from pathlib import Path

main = Path('windows/runner/main.cpp')
source = main.read_text(encoding='utf-8')
marker = 'int APIENTRY wWinMain'
if marker not in source:
    raise SystemExit('Runner Flutter non reconnu')
# Mutex local à la session Windows : deux Zuno ne doivent jamais écrire
# simultanément dans le cache et ouvrir deux canaux pour la même licence.
body = source.index('{', source.index(marker)) + 1
source = source[:body] + r'''
  HANDLE zuno_instance = CreateMutexW(nullptr, TRUE, L"Local\\Zuno.Desktop.5D2E8C41");
  if (zuno_instance && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(nullptr, L"Zuno");
    if (existing) {
      if (IsIconic(existing)) ShowWindow(existing, SW_RESTORE);
      SetForegroundWindow(existing);
    }
    CloseHandle(zuno_instance);
    return EXIT_SUCCESS;
  }
''' + source[body:]
# window_manager intercepte la croix pour mémoriser la taille puis fermer.
source = source.replace('window.SetQuitOnClose(true);', 'window.SetQuitOnClose(false);')
source = source.replace('L"tv_king"', 'L"Zuno"')
main.write_text(source, encoding='utf-8')
