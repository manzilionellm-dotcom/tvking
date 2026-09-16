#!/usr/bin/env python3
# Pose FLAG_SECURE sur MainActivity : pas de capture, pas de Recents.
# Idempotent. La TV régénère MainActivity à chaque CI (flutter create).
from pathlib import Path

ROOT = Path("android/app/src/main/kotlin")
FLAG = "WindowManager.LayoutParams.FLAG_SECURE"
IMPORTS = (
    "import android.os.Bundle\n"
    "import android.view.WindowManager\n"
)
ON_CREATE = """
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
"""


def patch(path: Path) -> None:
    text = path.read_text()
    if FLAG in text:
        print(f"FLAG_SECURE déjà présent : {path}")
        return
    if "import android.view.WindowManager" not in text:
        if "import io.flutter" in text:
            text = text.replace("import io.flutter", IMPORTS + "import io.flutter", 1)
        else:
            text = IMPORTS + text
    if "override fun onCreate" in text:
        text = text.replace(
            "super.onCreate(savedInstanceState)",
            "super.onCreate(savedInstanceState)\n"
            "        window.setFlags(\n"
            "            WindowManager.LayoutParams.FLAG_SECURE,\n"
            "            WindowManager.LayoutParams.FLAG_SECURE,\n"
            "        )",
            1,
        )
    else:
        # class MainActivity : FlutterActivity() { ... } ou forme courte
        if "class MainActivity" not in text:
            print(f"pas de MainActivity dans {path}")
            return
        if "{" not in text.split("class MainActivity", 1)[1]:
            text = text.rstrip() + " {\n" + ON_CREATE + "}\n"
        else:
            head, rest = text.split("{", 1)
            text = head + "{" + ON_CREATE + rest
    path.write_text(text)
    print(f"FLAG_SECURE posé : {path}")


def main() -> None:
    files = list(ROOT.rglob("MainActivity.kt")) if ROOT.exists() else []
    if not files:
        raise SystemExit("MainActivity.kt introuvable — FLAG_SECURE non posé")
    for f in files:
        patch(f)


if __name__ == "__main__":
    main()
