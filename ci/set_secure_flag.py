#!/usr/bin/env python3
# FLAG_SECURE ON (pas de capture) — la vidéo doit être en TEXTURE,
# sinon SurfaceView + ce drapeau = image noire sur Amlogic.
from pathlib import Path

ROOT = Path("android/app/src/main/kotlin")
MARK = "WindowManager.LayoutParams.FLAG_SECURE"
SET = (
    "        window.setFlags(\n"
    "            WindowManager.LayoutParams.FLAG_SECURE,\n"
    "            WindowManager.LayoutParams.FLAG_SECURE,\n"
    "        )"
)
IMPORTS = (
    "import android.os.Bundle\n"
    "import android.view.WindowManager\n"
)


def patch(path: Path) -> None:
    text = path.read_text()
    text = text.replace(
        "window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)",
        "window.setFlags(\n            WindowManager.LayoutParams.FLAG_SECURE,\n            WindowManager.LayoutParams.FLAG_SECURE,\n        )",
    )
    if "window.setFlags" in text and MARK in text:
        path.write_text(text)
        print(f"FLAG_SECURE ON : {path}")
        return
    if "import android.view.WindowManager" not in text:
        if "import io.flutter" in text:
            text = text.replace("import io.flutter", IMPORTS + "import io.flutter", 1)
        else:
            text = IMPORTS + text
    if "override fun onCreate" in text:
        if "super.onCreate" in text and SET.strip() not in text:
            text = text.replace(
                "super.onCreate(savedInstanceState)",
                "super.onCreate(savedInstanceState)\n" + SET,
                1,
            )
    else:
        needle = "class MainActivity"
        if needle not in text:
            print(f"pas de MainActivity dans {path}")
            return
        head, rest = text.split("{", 1)
        body = (
            "\n    override fun onCreate(savedInstanceState: Bundle?) {\n"
            "        super.onCreate(savedInstanceState)\n"
            f"{SET}\n"
            "    }\n"
        )
        text = head + "{" + body + rest
    path.write_text(text)
    print(f"FLAG_SECURE posé : {path}")


def main() -> None:
    files = list(ROOT.rglob("MainActivity.kt")) if ROOT.exists() else []
    if not files:
        raise SystemExit("MainActivity.kt introuvable")
    for f in files:
        patch(f)


if __name__ == "__main__":
    main()
