#!/usr/bin/env python3
# FLAG_SECURE ON. Flutter create peut générer une MainActivity SANS accolades.
from pathlib import Path
import re

ROOT = Path("android/app/src/main/kotlin")
SET = (
    "        window.setFlags(\n"
    "            WindowManager.LayoutParams.FLAG_SECURE,\n"
    "            WindowManager.LayoutParams.FLAG_SECURE,\n"
    "        )"
)
ON_CREATE = (
    "    override fun onCreate(savedInstanceState: Bundle?) {\n"
    "        super.onCreate(savedInstanceState)\n"
    f"{SET}\n"
    "    }\n"
)


def patch(path: Path) -> None:
    text = path.read_text()
    text = text.replace(
        "window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)",
        "window.setFlags(\n            WindowManager.LayoutParams.FLAG_SECURE,\n            WindowManager.LayoutParams.FLAG_SECURE,\n        )",
    )
    if "window.setFlags" in text and "FLAG_SECURE" in text:
        path.write_text(text)
        print(f"FLAG_SECURE déjà ON : {path}")
        return
    if "import android.view.WindowManager" not in text:
        if "import io.flutter" in text:
            text = text.replace(
                "import io.flutter",
                "import android.os.Bundle\nimport android.view.WindowManager\nimport io.flutter",
                1,
            )
        else:
            text = (
                "import android.os.Bundle\n"
                "import android.view.WindowManager\n"
            ) + text
    if "override fun onCreate" in text:
        text = text.replace(
            "super.onCreate(savedInstanceState)",
            "super.onCreate(savedInstanceState)\n" + SET,
            1,
        )
        path.write_text(text)
        print(f"FLAG_SECURE injecté dans onCreate : {path}")
        return
    # FlutterActivity() sans corps
    m = re.search(r"class MainActivity\s*:\s*\w+\(\)\s*$", text, re.M)
    if m:
        text = (
            text[: m.start()]
            + "class MainActivity : FlutterActivity() {\n"
            + ON_CREATE
            + "}\n"
            + text[m.end() :]
        )
        # si le type n'était pas FlutterActivity, garder le type d'origine
        orig = m.group(0)
        parent = re.search(r":\s*(\w+)\(\)", orig)
        if parent:
            text = text.replace(
                "class MainActivity : FlutterActivity()",
                f"class MainActivity : {parent.group(1)}()",
                1,
            )
        path.write_text(text)
        print(f"FLAG_SECURE + onCreate ajoutés : {path}")
        return
    if "{" in text:
        head, rest = text.split("{", 1)
        text = head + "{\n" + ON_CREATE + rest
        path.write_text(text)
        print(f"FLAG_SECURE dans classe : {path}")
        return
    raise SystemExit(f"MainActivity inattendu : {path}\n{text[:400]}")


def main() -> None:
    files = list(ROOT.rglob("MainActivity.kt")) if ROOT.exists() else []
    if not files:
        raise SystemExit("MainActivity.kt introuvable")
    for f in files:
        patch(f)


if __name__ == "__main__":
    main()
