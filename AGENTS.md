<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Organisation du dépôt

- Racine : site web Next.js (règles ci-dessus).
- `android-app/` : application mobile / Android TV **7 MOTION** en Flutter.
  Ses conventions propres sont dans `android-app/AGENTS.md` (lu automatiquement
  via `android-app/CLAUDE.md`). Ne pas mélanger les deux projets : toute
  modification de l'app (nom, logo, package, design, textes, fonctionnalités)
  se fait uniquement sous `android-app/`.
