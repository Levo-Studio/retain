# Retain — design export

This folder is the design. It is the first thing you read before writing UI and
the last thing you check before calling UI work done. It is never edited to
match the code: if the code and the design disagree, the code is wrong.

## What is in here

| File | What it is |
|---|---|
| `Retain - Alle Screens.dc.html` | **The file with the pixels in it.** All seven boards. |
| `screens/*.png` | The same boards rendered, one PNG per board, for quick reference. |
| `App-Icon.dc.html` | Five icon directions (A–E). Exploration, already decided — see "Icon". |
| `Aufnahme-Screen Richtungen.dc.html` | Earlier layout directions for the recording screen. Historical. |
| `support.js` | The generic dc-runtime. Contains no design information. Do not read it. |

Source: design project `4cfd8fc9-0456-4e73-9d31-bc23880316cf`
("macOS Vorlesungs-Transkriptor"). The export is a snapshot; refreshing it is
the owner's job and lands as its own commit.

The export is written in German. **The interface is English.** Only the words
change — geometry, weight, letter-spacing, casing, opacity and colour do not.
The copy table is at the bottom of this file.

**The export is dark-only.** There is no light board. A light appearance is
therefore not designed and is not built until it is.

## The seven boards

| # | File | What it is |
|---|---|---|
| 01 | `screens/01-recording.png` | Recording window during the lesson. Notes grow on the left, the transcript runs along on the right. 1120×720. |
| 02 | `screens/02-menubar-popover.png` | Menu-bar popover, five states side by side: running, stop confirmation, paused, summarizing, ready. Each 470 wide. |
| 03 | `screens/03-lesson-detail.png` | Lesson detail, Notes tab. Right rail switches between Chapters and Chat. 1120×700. |
| 04 | `screens/04-transcript.png` | Lesson detail, Transcript tab. Full text with timestamps, find bar, Chat rail. 1120×700. |
| 05 | `screens/05-library.png` | Library: terms in the title bar, courses in the sidebar, lessons in the table. 1120×700. |
| 06 | `screens/06-settings.png` | Settings: five sections in a sidebar, the Language-model pane shown. 1120×700. |
| 07 | `screens/07-dialogs.png` | Four modal sheets: microphone permission, new course, name term, LM Studio unreachable. Each 430 wide. |

Anything not on this list has no design and is therefore not built. In
particular there is **no flashcard board and no Anki-export board**, and no
onboarding.

---

# Values

Every number below is read out of the export. Take them exactly. Do not round a
14.5 to 14, do not snap an 11 to a 12, do not "improve" a ladder that is not a
ladder. CSS pixels transfer 1:1 to AppKit/SwiftUI points.

## Colour

Colours are given as written in the export. The export mixes hex and `oklch()`;
both are literal values, not approximations of each other.

### Surfaces

| Token | Value | Where |
|---|---|---|
| Canvas (behind the window) | `#08090b` | Design board background. Not an app surface. |
| Window | `#0e1013` | Window body, popover body, dialog body |
| Title bar | `#16181c` | `.tb` |
| Meta strip | `#14161a` | Header strip under the title bar; popover header; current row in the library table |
| Rail / sidebar | `#131519` | Transcript rail, chapters/chat rail, library sidebar, settings sidebar |
| Inset control | `#171a1e` | Text fields, search fields, secondary buttons, cards, composer |
| Selected row | `#1b1f24` | Sidebar selection, active segment |
| Chat bubble (yours) | `#1f242a` | User messages in the chat rail |
| Hotkey chip | `#131519` | `⌘⇧M · 2 Marker` chip inside the annotation bar |

### Lines

| Token | Value | Where |
|---|---|---|
| Window border | `#23272d` | Window, popover, dialog outline; progress track |
| Divider | `#24282e` | Title-bar bottom, strip bottom, rail edges, tab-bar bottom, dialog header |
| Control border | `#272b31` | Fields, secondary buttons, cards, composer |
| Control border, emphasised | `#2f353c` | Field with content/focus, "Pausieren" outline in the recording panel |
| Table row separator | `#1c2025` | Library lesson rows |
| Traffic light | `#30353c` | 10px circles in the title bar |

### Ink

| Token | Value | Where |
|---|---|---|
| Primary | `#edeff2` | Headings, values, active text |
| Body strong | `#e2e5e9` | Annotation body, latest transcript line, table lesson titles |
| Body | `#b8bec6` | Paragraphs, transcript body, secondary buttons, field labels |
| Muted | `#9aa1a9` | Bullet lists, the timestamp of the newest transcript line |
| Dim | `#8e959e` | Title-bar subtitle, settings descriptions, paused values, the block being written |
| Label | `#7c838c` | `.lbl` uppercase labels, captions, chevrons, placeholders |
| Faint | `#767d86` | The word "live" in the transcript rail header |
| Faintest | `#5d646d` | Note block numbers; typing dots |
| Disabled | `#3f454c` | Block number of the block still being written |

### Accents

| Token | Value | Where |
|---|---|---|
| Accent | `oklch(.78 .13 165)` | Primary buttons, active tab underline, connected state, progress fill, meter peak, current course rail |
| Accent hover | `oklch(.84 .13 165)` | Primary button hover (from the icon board) |
| Accent 2 | `oklch(.64 .11 165)` | Meter, second ring |
| Accent 3 | `oklch(.5 .08 165)` | Meter, third ring |
| Accent 4 | `oklch(.42 .06 165)` | Meter, outermost |
| On accent | `#0b0f0d` | Text and glyphs on an accent fill |
| Blue — you | `oklch(.7 .11 250)` | Annotation rule and label, chat source chips, links, course colour 2 |
| Blue hover | `oklch(.78 .11 250)` | Link hover |
| Amber — audience / marker | `oklch(.75 .12 70)` | Left rule, marker dots, status dot while summarizing, course colour 3 |
| Amber ink | `oklch(.78 .11 70)` | Timestamp and label of an audience line or a marker |
| Red — recording | `oklch(.68 .17 25)` | Recording dot, text caret |
| Red ink | `oklch(.75 .14 25)` | "Läuft" label, destructive button text, "läuft" status in the table |
| Red ink, brighter | `oklch(.78 .14 25)` | Destructive button text in the popover |
| Red border | `oklch(.42 .09 25)` | Destructive button outline |
| Red dot, error | `oklch(.72 .16 25)` | "No connection" dialog |
| Purple | `oklch(.68 .1 320)` | Course colour 4 |
| Term highlight | `oklch(.38 .06 95)` | Background behind an emphasised term in the notes |
| Search hit | `oklch(.42 .09 95)` with `#fff` ink | Match highlight in the transcript |

Course colours, in the order the new-course dialog offers them:
`oklch(.78 .13 165)`, `oklch(.7 .11 250)`, `oklch(.75 .12 70)`, `oklch(.68 .1 320)`.

### Shadows

| Where | Value |
|---|---|
| Window | `0 18px 44px rgba(0,0,0,.5)` |
| Popover | `0 18px 44px rgba(0,0,0,.55)` |
| Dialog | `0 22px 50px rgba(0,0,0,.6)` |

## Type

One family: **DM Sans**, variable, optical size 9–40, weights **400, 500, 600,
700**. Nothing else. The monospaced badges in the export are the design board's
own chrome and never reach the app.

`font-variant-numeric: tabular-nums` on every timer, timestamp, duration and
counter.

| Role | Size / weight / line-height | Tracking |
|---|---|---|
| Note heading (`h3`) | 700 · 22px · 1.25 | −0.015em |
| Library course heading | 700 · 21px | −0.015em |
| Settings section heading | 700 · 17px | −0.01em |
| Dialog title | 600 · 17px | — |
| Popover title, ready | 600 · 19px | −0.01em |
| Popover title, summarizing | 600 · 18px | — |
| Popover title, running / paused | 600 · 16px | — |
| Timer, large | 600 · 26px · 1.0 | — |
| Meta value (`.val`) | 500 · 14.5px | — |
| Note paragraph, recording | 400 · 15px · 1.66 | max-width 64ch |
| Note paragraph, detail | 400 · 15px · 1.7 | max-width 70ch |
| Note bullet, recording | 400 · 14.5px · 1.6 | padding-left 18px |
| Note bullet, detail | 400 · 14.5px · 1.68 | padding-left 19px |
| Transcript line, main pane | 400 · 14.5px · 1.65 | — |
| Transcript line, rail | 400 · 12.5px · 1.55 | 1.5 in the popover |
| Annotation body | 400 · 14.5px · 1.55 | — |
| Chat message | 400 · 12.5px · 1.55 (yours) / 1.6 (model) | — |
| Uppercase label (`.lbl`) | 500 · 10.5px, uppercase | 0.07em |
| Tab | 500 · 13px | — |
| Segment | 500 · 12px | — |
| Sidebar row | 500 · 13px | — |
| Table cell, title | 500 · 14px | — |
| Table cell, other | 400 · 12.5px | — |
| Field text | 400 · 13px | — |
| Field label (settings) | 500 · 12.5px | — |
| Field label (dialogs) | 400 · 12.5px | — |
| Button, dialog primary | 600 · 13px | — |
| Button, dialog secondary | 500 · 13px | — |
| Button, popover large | 600 · 13.5px | — |
| Button, panel footer | 500 · 12.5px | — |
| Timestamp, rail | 500 · 10.5px | — |
| Timestamp, main pane | 500 · 11.5px | — |
| Caption | 400 · 11.5px / 12px / 12.5px depending on place | — |
| Note block number | 500 · 11px | — |

## Radii

| Value | Where |
|---|---|
| 2px | Waveform bar, course colour rail |
| 3px | Term highlight, search hit, progress bar |
| 6px | Colour swatch, chat source chip |
| 7px | Hotkey chip |
| 8px | Text field, search field in a rail, sidebar row, segment, export button, status pill in the library title bar |
| 9px | Button, search field, popover secondary button, ready-state field |
| 10px | Dialog button, popover primary button, chat composer, annotation bar in the popover |
| 11px | Window, ASR download card, "open summary" card |
| 12px | Chat bubble (`12px 12px 4px 12px`), toggle |
| 13px | Popover, dialog |
| 14px | Annotation bar in the recording window |
| 999px | Timer pill in the title bar |
| 50% | Dots, traffic lights, toggle knob |

## Metrics

### Window and panes

| Thing | Value |
|---|---|
| Recording window | 1120 × 720 |
| Detail / transcript / library / settings window | 1120 × 700 |
| Popover | 470 wide |
| Dialog | 430 wide |
| Title bar | 38px tall, `0 14px` padding, 9px gap |
| Transcript rail (recording) | 320px |
| Chapters / chat rail (detail) | 330px |
| Library sidebar | 238px |
| Settings sidebar | 210px |
| Meta strip columns | `1.6fr 1fr 1fr` |
| Detail body columns | `1fr 330px` |
| Recording body columns | `1fr 320px` |

### Padding

| Thing | Value |
|---|---|
| Meta strip cell, first | `13px 34px` |
| Meta strip cell, others | `13px 20px` |
| Notes pane, recording | `22px 34px 0` |
| Notes pane, detail | `24px 34px 0` |
| Transcript pane, detail | `18px 34px 0` |
| Library main | `18px 30px 14px` header, `6px 30px 0` body |
| Settings pane | `26px 34px 0`, 24px gap between sections, 22px padding above a section rule |
| Settings sidebar / library sidebar | `16px 12px` |
| Rail header | `16px 20px 10px` (recording), `14px 18px 10px` (detail) |
| Rail body | `0 20px` (recording), `0 18px` (detail) |
| Popover header | `18px 18px 16px` running, `20px 20px 18px` paused, `22px 18px 20px` summarizing, `16px 16px 14px` ready, `22px 22px 20px` stop-confirmation |
| Dialog header | `20px 20px 16px`, or `20px 20px 14px` when a rule follows |
| Dialog body | `16px 20px` |
| Dialog footer | `0 20px 18px`, 10px gap, right aligned |
| Tab bar | `0 34px`, 22px gap between tabs, tab itself `11px 0` |
| Sidebar row | `8px 9px` (library) / `8px 10px` (settings), 3px gap between rows |
| Table header row | `8px 10px` |
| Table row | `13px 10px` |
| Field | `8px 11px` |
| Search field | `8px 12px`, `7px 11px` in a rail |
| Button, dialog | `9px 16px` |
| Button, popover large | `12px 0` |
| Button, panel footer | `8px 0`, 9px gap |
| Segment | `7px 0`, 3px gap |
| Annotation bar, recording | `11px 15px`, margin `14px 34px 20px`, 12px gap |
| Chat composer | `9px 12px`, 10px gap |
| Chat bubble | `9px 12px` |

### Grids

| Thing | Value |
|---|---|
| Settings form | `160px 1fr`, gap `12px 18px`, max-width 640px |
| Dialog form | `104px 1fr`, gap `11px 16px` |
| Library table | `54px 1fr 120px 96px 84px`, gap 14px |
| Transcript line | `74px 1fr`, gap 16px |

### Small parts

| Thing | Value |
|---|---|
| Traffic light | 10px circle |
| Status dot | 8px (popover, dialog), 7px (settings), 5px (marker, term, typing) |
| Waveform bar | 3px wide, 2px gap, 2px radius |
| Waveform height | 13px (title bar), 16px (ready state), 20px (popover) |
| Pause glyph | two bars 3 × 12px (small) or 3 × 13px (large), 1px radius, 3px gap |
| Progress bar | 4px tall (summarizing), 5px (download, mic level), 3px radius |
| Left rule (annotation, audience, chapter) | 2px wide |
| Annotation bar rule | 2px × 16px (recording), 2px × 15px (popover) |
| Text caret | 2px wide, 15px tall in the notes, 12px in a rail |
| Course colour rail | 3 × 14px, 2px radius |
| Toggle | 34 × 20px, 12px radius, 16px knob, 2px inset |
| Colour swatch | 20 × 20px, 6px radius; selected gets `outline: 2px #edeff2`, offset 2px |
| Active tab underline | 2px, accent |
| Chapter indent | 26px for a sub-entry |

### Note block indent

Note headings sit in a row with the block number: 11px gap, number 500 · 11px.
Body and bullets under a heading are indented **30px** in the recording screen
(they align past the number) and **0** in the detail screen, which has no
numbers.

## Motion

Four keyframes, all in the export:

| Name | Timing | What it does |
|---|---|---|
| `recpulse` | 2s ease-in-out infinite | Recording dot, opacity 1 → .25 → 1 |
| `caret` | 1.1s step-end infinite | Text caret blink, 0–49% visible, 50–100% hidden |
| `sweep` | 1.6s ease-in-out infinite | Indeterminate progress, `translateX(-100%)` → `translateX(320%)`, bar 30% wide |
| `breathe` | 1.6s ease-in-out infinite | Status dot while summarizing, opacity .5 → 1 → .5 |

The chat typing indicator is `breathe` at **1.4s**, three dots, delays `0`,
`.2s`, `.4s`.

Every one of these is decorative and must be suppressed under
`accessibilityReduceMotion` — the caret goes solid, the pulse and breathe go to
full opacity, the sweep becomes a static determinate bar.

## Opacity ladder — live transcript

Older lines are faded, the newest is full strength. This is opacity on the whole
line, not a colour change.

- Recording rail, five lines: `.5`, `.75`, `1`, `1`, `1`
- Popover, three lines: `.55`, `.8`, `1`

The newest line also gets brighter ink: timestamp `#9aa1a9` instead of `#7c838c`,
body `#edeff2` instead of `#b8bec6`, and it carries the blinking caret.

---

# Copy — German export to English interface

The export is German. The interface is English. Translate the words, keep
everything else.

| Export | Interface |
|---|---|
| Aufnahme | Recording |
| Thema · automatisch erkannt | Topic · detected |
| Fach | Course |
| Datum | Date |
| Dauer | Duration |
| Transkript | Transcript |
| live | live |
| Lehrerin spricht | Speaker detected |
| Lehrerin | Speaker |
| Publikum | Audience |
| Mikrofon läuft · 8,6 W | Microphone on · 8.6 W |
| Von dir | You |
| schreibt … | writing … |
| Anmerkung — geht an die KI | Note — goes to the model |
| 2 Marker | 2 markers |
| Pausieren | Pause |
| Fortsetzen | Resume |
| Beenden | Finish |
| Stoppen | Stop |
| Läuft | Recording |
| Pausiert | Paused |
| Wird zusammengefasst | Summarizing |
| Bereit | Ready |
| Aufnehmen | Record |
| Stille · MacBook Pro Mikrofon | Silence · MacBook Pro Microphone |
| Zusammenfassung öffnen | Open summary |
| im Hintergrund weiterlaufen lassen | keep running in the background |
| Aufnahme läuft seit 47 Minuten | Recording for 47 minutes |
| Letzte Zeile vor der Pause | Last line before the pause |
| ⌘⇧P setzt fort | ⌘⇧P resumes |
| 3 Notizblöcke | 3 note blocks |
| Block 3 von 4 · noch etwa 20 s | Block 3 of 4 · about 20 s left |
| 3 Marker · 4 Abschnitte | 3 markers · 4 sections |
| Notizen | Notes |
| Kapitel | Chapters |
| Chat | Chat |
| Exportieren | Export |
| Notizen und Transkript durchsuchen … | Search notes and transcript … |
| klausurrelevant | exam relevant |
| Frage stellen … | Ask a question … |
| Fragen zu dieser Stunde. Das Modell sieht Notizen und Transkript. | Questions about this lesson. The model sees the notes and the transcript. |
| Notiz 1 | Note 1 |
| 3 von 11 | 3 of 11 |
| Bibliothek | Library |
| Halbjahr | Term |
| Halbjahre | Terms |
| Drittes Jahr, Winter | Third year, winter |
| Okt 2025 – März 2026 · 4 Kurse | Oct 2025 – Mar 2026 · 4 courses |
| Umbenennen | Rename |
| + Kurs anlegen | + New course |
| Volltextsuche über alle Stunden dieses Halbjahres … | Search every lesson in this term … |
| chronologisch ▾ | by date ▾ |
| 9 Stunden · 13 h 24 min | 9 lessons · 13 h 24 min |
| Nr. | No. |
| Status | Status |
| Heute | Today |
| läuft | recording |
| fertig | done |
| Einstellungen | Settings |
| Allgemein | General |
| Sprachmodell | Language model |
| Spracherkennung | Speech recognition |
| Mikrofon | Microphone |
| Kurzbefehle | Shortcuts |
| Lokales Sprachmodell | Local language model |
| Die Zusammenfassungen laufen über ein Modell auf diesem Mac. Es verlässt nichts das Gerät. | Summaries run on a model on this Mac. Nothing leaves the device. |
| API-Key optional | API key optional |
| leer lassen für LM Studio | leave empty for LM Studio |
| Modell | Model |
| Verbindung testen | Test connection |
| Verbunden · 3 Modelle geladen · Antwort in 240 ms | Connected · 3 models loaded · answered in 240 ms |
| Läuft auf der Neural Engine. Das Modell wird einmalig geladen und danach offline verwendet. | Runs on the Neural Engine. The model is downloaded once and used offline after that. |
| 412 MB von 598 MB | 412 MB of 598 MB |
| wird geladen · noch etwa 40 Sekunden | downloading · about 40 seconds left |
| Eingang | Input |
| Pegel | Level |
| Berechtigung | Permission |
| erteilt | granted |
| Dialoge | Dialogs |
| Retain braucht Zugriff auf dein Mikrofon | Retain needs access to your microphone |
| Die Aufnahme wird ausschließlich auf diesem Mac verarbeitet. Es wird nichts hochgeladen, gespeichert wird nur, was du behältst. | The recording is processed only on this Mac. Nothing is uploaded, and only what you keep is stored. |
| Später | Later |
| Zugriff erlauben | Allow access |
| Neu | New |
| Kurs anlegen | New course |
| Name | Name |
| Farbe | Colour |
| Abbrechen | Cancel |
| Anlegen | Create |
| Halbjahr benennen | Name term |
| Titel | Title |
| Zeitraum | Period |
| Aktuell | Current |
| wird oben ausgewählt gezeigt | shown as selected at the top |
| Sichern | Save |
| Keine Verbindung | No connection |
| LM Studio antwortet nicht | LM Studio is not responding |
| Unter … war kein Server erreichbar. Die Aufnahme läuft weiter, Zusammenfassungen werden nachgeholt, sobald die Verbindung steht. | No server was reachable at … . Recording continues; summaries are caught up once the connection is back. |
| Erneut versuchen | Try again |

---

# Icon

`App-Icon.dc.html` holds five directions, A–E, each drawn at 512, 128 and 32
and once inside a macOS-shaped tile:

| | Name | Motif |
|---|---|---|
| A | Pegel | Four bars, one peak in the middle |
| B | Anschlag | A flat line with a single spike |
| C | Zwei Spuren | Two stacked tracks, speaker and question |
| D | Aufnahme | Ring and dot |
| E | Verdichtung | Audio segments condensing into a block |

The board draws all five in `#3f9b76` on `#f4f2ee`, on `#16181c`, and on a macOS
tile: 128px, 29px corner radius, `#14181c` fill, `#23272d` border.

**This board is exploration and is already settled.** The shipping icon is
`retain-icon.icon` in the repository root, an Icon Composer document built from
`retain-logo.png`. Do not re-derive an icon from this board.

---

# Where the design and the written brief disagree

These are open questions for the owner, not gaps to fill with taste. Until they
are answered, **the design wins for anything that is drawn** and the brief wins
for anything that is not.

1. **School, not university.** The export says *Stunde* (lesson), *Fach*,
   *Halbjahr*, *Lehrerin*, *Frau Reinhardt*. The brief says *Vorlesung*,
   *Kurs*, *Semester*, *Dozent*. The nouns in the model layer follow one or the
   other and cannot follow both.
2. **No flashcards, no Anki export.** The brief lists both. No board draws
   either. Screen 03 has one `Export` button with no menu drawn behind it.
3. **Chat is drawn but not in the brief.** Screens 03 and 04 both have a Chat
   rail that answers questions against the notes and the transcript and cites
   timestamps and note numbers.
4. **Chapters are drawn but not in the brief.** Screen 03's rail lists
   timestamped chapters and sub-entries, with markers flagged by an amber dot.
5. **⌘⇧M is a typed annotation, not a bare marker.** The brief says the hotkey
   marks a spot as exam-relevant. The design shows a composer — "Anmerkung —
   geht an die KI" — whose text appears in the notes as "Von dir · 00:46:41" and
   is fed to the model.
6. **⌘⇧P resumes** a paused recording. The brief does not mention it.
7. **A live power reading** — "8,6 W" — is drawn in the title bar and in the
   popover header. Nothing in the brief asks for one, and reading it costs
   something.
8. **Topic detection.** Screen 01 labels the topic "automatisch erkannt". The
   brief does not describe where the topic comes from.
9. **The Base URL shown is `http://localhost:1234/v1`** while the locked
   decision is to call `/api/v0/chat/completions`. Both can be true — the stored
   value is the `/v1` base and the client swaps the path — but the settings
   field says `/v1` and must keep saying it.
10. **No light appearance is drawn.** Dark only.
