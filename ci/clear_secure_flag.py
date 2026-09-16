#!/usr/bin/env python3
# FORCE FLAG_SECURE à OFF. Sur les box Amlogic, un drapeau « secure »
# = son sans image. Idempotent.
from pathlib import Path

ROOT = Path("android/app/src/main/kotlin")
MARK = "window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)"
IMPORTS = (
    "import android.os.Bundle\n"
    "import android.view.WindowManager\n"
)
ON_CREATE = """
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Captures AUTORISÉES. FLAG_SECURE éteint l'image sur les box.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
"""


def patch(path: Path) -> None:
    text = path.read_text()
    if MARK in text:
        print(f"clearFlags déjà présent : {path}")
        return
    # Si un vieux setFlags FLAG_SECURE traîne, on le retire.
    text = text.replace(
        "window.setFlags(\n"
        "            WindowManager.LayoutParams.FLAG_SECURE,\n"
        "            WindowManager.LayoutParams.FLAG_SECURE,\n"
        "        )",
        MARK,
    )
    if MARK in text:
        path.write_text(text)
        print(f"setFlags remplacé par clearFlags : {path}")
        return
    if "import android.view.WindowManager" not in text:
        if "import io.flutter" in text:
            text = text.replace("import io.flutter", IMPORTS + "import io.flutter", 1)
        else:
            text = IMPORTS + text
    if "override fun onCreate" in text:
        text = text.replace(
            "super.onCreate(savedInstanceState)",
            "super.onCreate(savedInstanceState)\n        " + MARK,
            1,
        )
    else:
        if "class MainActivity" not in text:
            print(f"pas de MainActivity dans {path}")
            return
        if "{" not in text.split("class MainActivity", 1)[1]:
            text = text.rstrip() + " {\n" + ON_CREATE + "}\n"
        else:
            head, rest = text.split("{", 1)
            text = head + "{" + ON_CREATE + rest
    path.write_text(text)
    print(f"FLAG_SECURE forcé OFF : {path}")


def main() -> None:
    files = list(ROOT.rglob("MainActivity.kt")) if ROOT.exists() else []
    if not files:
        raise SystemExit("MainActivity.kt introuvable")
    for f in files:
        patch(f)


if __name__ == "__main__":
    main()
