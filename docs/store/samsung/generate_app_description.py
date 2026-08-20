# =========================================================
#  generate_app_description.py — PDF « Application UI Description »
# =========================================================
#  POURQUOI : Samsung a rejeté « The Few » le 14/08/2026 en Doc Review :
#  « Description file incomplete: 1.- App preview images 2.- Key policy ».
#  Ce script produit le PDF conforme au template officiel
#  (developer.samsung.com/tv-seller-office/checklists-for-distribution/
#   application-ui-description.html) : page de titre, historique de
#  révisions, structure UI, cas d'usage, écrans annotés (images d'aperçu),
#  politique des touches télécommande (tirée du CODE RÉEL de
#  tv_player_screen.dart), langues.
#
#  USAGE :
#    1. Déposer les captures d'écran dans docs/store/samsung/screenshots/
#       avec ces noms (PNG ou JPG) :
#         01-activation, 02-home, 03-channels, 04-player, 05-movies,
#         06-settings  (ex. 02-home.png)
#    2. python3 docs/store/samsung/generate_app_description.py
#       → docs/store/samsung/TheFew_App_Description.pdf
#    Sans captures, le PDF sort avec des cadres « image à insérer »
#    (repérables — NE PAS soumettre tant qu'il en reste).
# =========================================================
import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (Image, PageBreak, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "screenshots")
OUT = os.path.join(HERE, "TheFew_App_Description.pdf")

APP = "The Few"
VENDOR = "7 Few, LLC"
PKG = "com.sevenmotion.thefew"
VERSION = "1.0.1"
DATE = "2026-08-20"

styles = getSampleStyleSheet()
H1 = styles["Heading1"]
H2 = styles["Heading2"]
BODY = ParagraphStyle("Body", parent=styles["Normal"], fontSize=10.5,
                      leading=15, spaceAfter=6)
CAPTION = ParagraphStyle("Caption", parent=styles["Normal"], fontSize=9,
                         leading=12, textColor=colors.HexColor("#555555"),
                         spaceBefore=4, spaceAfter=12)
TITLE = ParagraphStyle("TitleBig", parent=styles["Title"], fontSize=30,
                       leading=36, spaceAfter=18)

GOLD = colors.HexColor("#CCB089")
DARK = colors.HexColor("#070707")


def elements_table(rows):
    """Tableau « n° | élément | fonction » sous chaque capture (exigence
    Samsung : chaque écran illustré + chaque élément décrit — première
    cause de rejet des Doc Reviews). Les n° correspondent aux badges
    numérotés incrustés sur l'image."""
    t = Table([["#", "UI element", "Function"]] + rows,
              colWidths=[0.4 * inch, 1.9 * inch, 4.2 * inch])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), GOLD),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1),
         [colors.white, colors.HexColor("#F4F0E8")]),
    ]))
    return [t, Spacer(1, 16)]


def screenshot(name, caption):
    """Image réelle si présente dans screenshots/, sinon cadre placeholder
    clairement marqué (à remplacer AVANT soumission)."""
    flow = []
    path = None
    for ext in (".png", ".jpg", ".jpeg"):
        p = os.path.join(SHOTS, name + ext)
        if os.path.exists(p):
            path = p
            break
    if path:
        img = Image(path)
        # 16:9, largeur pleine page utile (6,5 in).
        img.drawWidth = 6.5 * inch
        img.drawHeight = 6.5 * inch * 9 / 16
        flow.append(img)
    else:
        box = Table(
            [[Paragraph(
                f"[ APP PREVIEW IMAGE TO INSERT — {name} ]<br/>"
                "Drop the screenshot in docs/store/samsung/screenshots/ "
                "and re-run the script.", CAPTION)]],
            colWidths=[6.5 * inch], rowHeights=[6.5 * inch * 9 / 16])
        box.setStyle(TableStyle([
            ("BOX", (0, 0), (-1, -1), 1.2, colors.red),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (-1, -1), "CENTER"),
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF5F5")),
        ]))
        flow.append(box)
    flow.append(Paragraph(caption, CAPTION))
    return flow


def key_table(rows):
    t = Table([["Remote control key", "Action"]] + rows,
              colWidths=[2.4 * inch, 4.1 * inch])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), GOLD),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9.5),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1),
         [colors.white, colors.HexColor("#F4F0E8")]),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    return t


story = []

# ---------- 1. Page de titre ----------
story += [
    Spacer(1, 1.6 * inch),
    Paragraph(APP, TITLE),
    Paragraph("Application UI Description", H1),
    Spacer(1, 0.4 * inch),
    Paragraph(f"Content provider: <b>{VENDOR}</b>", BODY),
    Paragraph(f"Application ID: <b>{PKG}</b>", BODY),
    Paragraph(f"Application version: <b>{VERSION}</b>", BODY),
    Paragraph(f"Document date: <b>{DATE}</b>", BODY),
    Paragraph("Category: Videos — Live TV &amp; video-on-demand player "
              "for IPTV subscriptions the user already owns.", BODY),
    PageBreak(),
]

# ---------- 2. Historique des révisions ----------
story += [Paragraph("1. Revision history", H1)]
rev = Table([
    ["Version", "Date", "Changes", "Author"],
    ["1.0", "2026-08-14", "Initial submission.", "Lionel Manzi"],
    ["2.0", DATE,
     "Added annotated app preview images and the remote-control key "
     "policy, per Samsung Doc Review feedback. Application package "
     "updated to 1.0.1.",
     "Lionel Manzi"],
], colWidths=[0.8 * inch, 1.0 * inch, 3.7 * inch, 1.0 * inch])
rev.setStyle(TableStyle([
    ("BACKGROUND", (0, 0), (-1, 0), DARK),
    ("TEXTCOLOR", (0, 0), (-1, 0), GOLD),
    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
    ("FONTSIZE", (0, 0), (-1, -1), 9.5),
    ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
story += [rev, PageBreak()]

# ---------- 3. Structure UI ----------
story += [
    Paragraph("2. UI structure", H1),
    Paragraph(
        "The application is a “10-foot” TV interface, fully navigable with "
        "the standard Samsung remote control. Screen flow:", BODY),
    Paragraph(
        "<b>Launch</b> → <b>Activation</b> (first run only: the TV shows its "
        "device code / MAC address; the service operator activates it "
        "server-side, no on-TV typing required) → <b>Home</b> (content "
        "rails) → from Home the user reaches: <b>Live TV player</b> "
        "(full-screen), <b>Channel list</b> (with live preview panel), "
        "<b>Movies</b> (video-on-demand), and <b>Settings</b> (language, "
        "themes, sources, diagnostics).", BODY),
    Paragraph(
        "The Back key always returns to the previous screen; from Home it "
        "shows an exit confirmation dialog.", BODY),
    Spacer(1, 12),
]

# ---------- 4. Cas d'usage ----------
story += [
    Paragraph("3. Main use cases", H1),
    Paragraph("<b>UC-1 — First launch.</b> The activation screen offers "
              "three paths: (a) operator activation by the displayed "
              "device code — the app detects it automatically and "
              "continues to Home; (b) <b>“Add my own playlist”</b> — the "
              "user loads their own M3U/Xtream subscription, no account "
              "or login required (this is the reviewer path, see "
              "Verification Info); (c) a 6-digit family code. No password "
              "is ever typed on the TV. In-app purchase: none. Ads: none.",
              BODY),
    Paragraph("<b>UC-2 — Watching live TV.</b> From Home or the channel "
              "list, pressing OK on a channel opens the full-screen "
              "player. Channel Up/Down (or Arrow Up/Down) zaps to the "
              "next/previous channel. Typing a channel number with the "
              "digit keys jumps directly to that channel. Pressing OK "
              "shows the channel overlay (name, program, progress).", BODY),
    Paragraph("<b>UC-3 — Watching a movie (VOD).</b> From the Movies "
              "screen, OK starts playback. Left/Right seek, OK "
              "pauses/resumes via the overlay. Playback position is "
              "remembered and offered as “Resume” on the next opening.",
              BODY),
    Paragraph("<b>UC-4 — Changing the app language.</b> Settings → "
              "Language: the interface is available in 9 options (system "
              "default, English, French, Spanish, Arabic, Norwegian, "
              "Swedish, Danish, Swahili) and switches instantly.", BODY),
    PageBreak(),
]

# ---------- 5. Menus & fonctions (images d'aperçu annotées) ----------
story += [Paragraph("4. Menus and functions — app preview images", H1)]
story += screenshot("01-activation",
                    "Screen 1 — Activation (first launch only).")
story += elements_table([
    ["1", "Device code / MAC", "Identifier the operator uses to activate "
     "the device server-side."],
    ["2", "“Check my subscription”", "Re-checks the activation status "
     "(OK key)."],
    ["3", "“Add my own playlist”", "Opens the Add source screen — the "
     "no-account path used for review."],
])
story.append(PageBreak())
story += screenshot("02-home",
                    "Screen 2 — Home: content rails, D-pad navigation.")
story += elements_table([
    ["1", "Navigation tiles", "Live TV, Movies, Favorites, Settings — "
     "arrows move focus, OK opens."],
    ["2", "Content rails", "Recently watched and quick access to "
     "channels; OK starts playback."],
])
story.append(PageBreak())
story += screenshot("03-channels",
                    "Screen 3 — Live channel list with preview panel.")
story += elements_table([
    ["1", "Category column", "Channel groups from the user's playlist."],
    ["2", "Channel list", "Arrows browse; OK opens full-screen playback."],
    ["3", "Preview panel", "Shows the focused channel's logo/preview and "
     "current program (EPG)."],
])
story.append(PageBreak())
story += screenshot("04-player",
                    "Screen 4 — Full-screen player with channel overlay.")
story += elements_table([
    ["1", "Channel overlay (OK)", "Channel name, current program, "
     "progress bar."],
    ["2", "Playback area", "Channel Up/Down or Arrow Up/Down zaps; "
     "digits 0–9 jump to a channel number; Play/Pause toggles; "
     "RETURN leaves the player."],
])
story.append(PageBreak())
story += screenshot("05-movies",
                    "Screen 5 — Movies (VOD) shelf.")
story += elements_table([
    ["1", "Poster grid", "Arrows browse the catalog from the user's "
     "playlist; OK starts playback (resume offered on reopening)."],
])
story += screenshot("06-settings",
                    "Screen 6 — Settings.")
story += elements_table([
    ["1", "Settings tiles", "Sources (add/manage playlists), Language "
     "(9 options, instant switch), Themes, Diagnostics."],
])
story.append(PageBreak())

# ---------- 6. Key policy (tirée du code réel) ----------
story += [
    Paragraph("5. Remote control key policy", H1),
    Paragraph("Keys handled on <b>all screens</b> (navigation):", BODY),
    key_table([
        ["Arrow Up / Down / Left / Right", "Move focus between items."],
        ["OK (Enter)", "Activate the focused item."],
        ["Back (Return)",
         "Go back to the previous screen. On Home: show the exit "
         "confirmation dialog. On Exit: quit the application."],
    ]),
    Spacer(1, 14),
    Paragraph("Keys handled in the <b>full-screen player</b>:", BODY),
    key_table([
        ["Channel Up / Arrow Up", "Zap to the previous channel in the "
         "list (live TV)."],
        ["Channel Down / Arrow Down", "Zap to the next channel (live TV)."],
        ["Digits 0–9", "Type a channel number to jump directly to that "
         "channel (live TV)."],
        ["OK (Enter)", "Show/hide the channel overlay (name, current "
         "program, progress bar, actions)."],
        ["Arrow Left / Right", "Seek backward / forward (movies and "
         "catch-up); with the overlay open: move between actions."],
        ["Play / Pause", "Pause and resume playback (movies; live pause "
         "releases the stream and resumes at the live edge)."],
        ["Back (Return)", "Leave the player and return to the previous "
         "screen (the stream connection is closed immediately)."],
    ]),
    Spacer(1, 14),
    Paragraph(
        "No other special keys (color keys, voice, pointer) are required: "
        "every function is reachable with the D-pad, OK, Back, the digit "
        "keys and Channel Up/Down.", BODY),
    PageBreak(),
]

# ---------- 7. Langues ----------
story += [
    Paragraph("6. Language options", H1),
    Paragraph(
        "The service country is the United States and the default "
        "interface language is <b>English</b>. The interface is fully "
        "localized in 8 languages (English, French, Spanish, Arabic, "
        "Norwegian, Swedish, Danish, Swahili). By default the app follows "
        "the TV system language when supported; the user can override it "
        "at any time in Settings → Language, and the change applies "
        "instantly without restarting.", BODY),
    Spacer(1, 12),
    Paragraph("7. Test account / review notes", H1),
    Paragraph(
        "The application requires a service activation (per device). The "
        "test account and pre-activated review details are provided in "
        "the Verification Info section of the Seller Office submission. "
        "No payment happens inside the application.", BODY),
]

doc = SimpleDocTemplate(OUT, pagesize=letter, title=f"{APP} — Application UI Description",
                        author=VENDOR, leftMargin=inch, rightMargin=inch)
doc.build(story)

missing = [n for n in ("01-activation", "02-home", "03-channels",
                       "04-player", "05-movies", "06-settings")
           if not any(os.path.exists(os.path.join(SHOTS, n + e))
                      for e in (".png", ".jpg", ".jpeg"))]
print(f"✓ {OUT}")
if missing:
    print(f"⚠️  {len(missing)} capture(s) manquante(s) : {', '.join(missing)}")
    print("   → PDF NON soumissible tant que les cadres rouges restent.")
