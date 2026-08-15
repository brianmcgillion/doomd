# Doom Emacs Org-mode Cheat Sheet

> **Leader is `C-c`.** This config runs **no Evil mode**, so Doom's `SPC` leader
> never activates — plain `SPC` self-inserts. Everything below uses the real
> bindings (`doom-leader-alt-key` = `C-c`, `doom-localleader-alt-key` = `C-c l`).

## Quick Reference

### Global Capture (`C-c n n`)
| Key | Action | Target |
|-----|--------|--------|
| `t` | Personal todo | `roam/inbox-{host}.org` → Inbox |
| `n` | Personal note | `roam/inbox-{host}.org` → Inbox |
| `j` | Journal entry | `roam/inbox-{host}.org` → datetree |
| `p t` | Project todo | `roam/projects/{project}/todo.org` → Inbox |
| `p n` | Project note | `roam/projects/{project}/notes.org` → Inbox |
| `p c` | Project changelog | `roam/projects/{project}/changelog.org` |

### Org-Roam (`C-c z`)
| Key | Action | Description |
|-----|--------|-------------|
| `c` | Capture | New roam note (choose template) |
| `f` | Find | Search all roam nodes |
| `i` | Insert | Insert link to roam node |
| `t` | Toggle buffer | Show/hide backlinks |
| `g` | Graph | Visualize connections |
| `r` | Refile | Move current node |

### Org-Roam Capture Templates (`C-c z c`)
| Key | Template | Location |
|-----|----------|----------|
| `d` | Default note | `roam/{slug}.org` |
| `f` | Fleeting (quick) | `roam/inbox-{host}.org` → Inbox |
| `r` | Reference | `roam/refs/{slug}.org` |
| `m` | Meeting | `roam/meetings/{date}-{slug}.org` |

### Dailies (`C-c z d`)
| Key | Action |
|-----|--------|
| `t` | Go to today |
| `n` | Capture today |
| `y` | Go to yesterday |
| `d` | Go to specific date |
| `b/f` | Previous/next note |

### Project Notes (`C-c z p`)
| Key | Action | Target |
|-----|--------|--------|
| `t` | Project TODO | `projects/{project}/todo.org` → Inbox |
| `n` | Project note | `projects/{project}/notes.org` → Inbox |
| `p` | Project roam note | `projects/{project}/{slug}.org` (new file) |
| `T` | Open project TODO | Opens `todo.org` directly |
| `N` | Open project notes | Opens `notes.org` directly |

`t` and `n` append a `:REFILE:`-tagged **heading** to one shared file per
project — no capture buffer, you type straight into the file. `p` runs
`org-roam-capture` and creates a **new file with an `:ID:`**, i.e. a real
roam node: linkable with `C-c z i`, findable with `C-c z f`, present in
backlinks and the graph. The shared files have no ID and are none of those
things, which is why `T`/`N` exist to open them directly. Both kinds reach
the agenda, since org-mem indexes files regardless of ID.

### Node Properties (`C-c z o`)
| Key | Action |
|-----|--------|
| `a/A` | Add/remove alias |
| `t/T` | Add/remove tag |
| `r/R` | Add/remove ref |

### Agenda (`C-c n a`)
| Key | Action |
|-----|--------|
| `i` | Clock in |
| `R` | Refile item |
| `t` | Change TODO state |
| `s` | Schedule |
| `d` | Set deadline |

---

## GTD Workflow

### 1. Capture (Get it out of your head)
- **Quick thought**: `C-c n n t` (personal todo) or `C-c z c f` (fleeting)
- **Project task**: `C-c z p t` (while in project directory)
- **Meeting notes**: `C-c z c m`
- **Reference**: `C-c z c r`

All inbox captures automatically get `:REFILE:` tag.

### 2. Process (Empty your inboxes)
- Open agenda: `C-c n a`
- **"📥 Inbox"** group shows all `:REFILE:` items at the very top
- For each item, decide:
  - **Do it** (if < 2 min) → complete and remove REFILE tag
  - **Delegate** (change state to `WAIT` with `t`)
  - **Defer** (schedule with `s` or set deadline with `d`)
  - **Delete** (change state to `KILL` with `t`)
  - **Refile** to proper location with `R`

### 3. Organize (Refile to proper location)
- `R` in agenda to refile to another heading/file
- `C-c C-w` in org buffer to refile
- **Remove `:REFILE:` tag** with `C-c C-c` on the tag, or edit heading
- Move from `* Inbox` to `* Active` or other heading in same file

### 4. Review
- **Daily**: Check agenda (`C-c n a`)
- **Weekly**: `M-x bmg/org-roam-review-week`

### Complete Processing Example

```
1. CAPTURE: C-c z p t → "Fix login bug"
   Creates: projects/my-app/todo.org
   └── * Inbox
       └── ** TODO Fix login bug :REFILE:

2. AGENDA: C-c n a
   Shows: 📥 Inbox - Process these first
          └── TODO Fix login bug  :REFILE:  (my-app/todo.org)

3. PROCESS: On the item, press:
   - `t` → change state (TODO → STRT if starting now)
   - `s` → schedule for a date
   - `d` → set deadline
   - `R` → refile to different file/heading
   
4. REMOVE TAG: 
   - Open file: `C-c z p T`
   - Move item from "* Inbox" to "* Active" with `C-c C-w`
   - Or delete :REFILE: tag manually

5. RESULT:
   └── * Active
       └── ** STRT Fix login bug   ← now in "Ongoing" agenda group
```

---

## Finding Your Items

| What you want | How to find it |
|---------------|----------------|
| All inbox items | Agenda (`C-c n a`) → "📥 Inbox" section |
| Project's todos | `C-c z p T` (opens project's todo.org) |
| Any roam node | `C-c z f` then type title |
| Project nodes only | `C-c z f` then type `#project` |
| Today's tasks | Agenda → "Today" section |
| Search all org | `C-c z s` (consult-org-roam-search) |

---

## Directory Structure

```
~/Documents/org/
├── roam/                          ← org-roam-directory
│   ├── inbox-{hostname}.org       ← machine-specific inbox
│   ├── daily/                     ← daily notes
│   │   └── 2026-01-31.org
│   ├── refs/                      ← literature/references
│   │   └── smith2024-paper.org
│   ├── meetings/                  ← meeting notes
│   │   └── 20260131-standup.org
│   ├── projects/                  ← project-specific files
│   │   ├── my-app/
│   │   │   ├── todo.org          ← project tasks
│   │   │   ├── notes.org         ← project notes
│   │   │   └── architecture.org  ← roam nodes
│   │   └── doom-config/
│   │       └── todo.org
│   └── *.org                      ← general roam notes
└── emacs_lit.bib                  ← bibliography
```

---

## Filetags for Filtering

In `C-c z f` (`consult-org-roam-file-find`, a wrapper around
`org-roam-node-find`), type `#tag` to filter:

| Tag | Content |
|-----|---------|
| `#project` | Project roam notes (`C-c z p p`) |
| `#meeting` | Meeting notes |
| `#daily` | Daily notes |
| `#reference` | Literature/references |

**Not findable this way:** `projects/{project}/todo.org` and `notes.org` are
written with `:project:todo:` / `:project:notes:` filetags, but they carry no
`:ID:`, so org-roam never indexes them as nodes — no tag filter will surface
them. Open them directly with `C-c z p T` / `C-c z p N`. Of the three project
capture keys only `C-c z p p` creates a real node; `t` and `n` append a
`:REFILE:` heading to those shared files instead.

---

## TODO States (Doom defaults)

| State | Meaning | Key |
|-------|---------|-----|
| `TODO` | Task to do | `t` |
| `PROJ` | Project (contains subtasks) | `p` |
| `LOOP` | Recurring task | `r` |
| `STRT` | Started/in progress | `s` |
| `WAIT` | Waiting on someone | `w` |
| `HOLD` | On hold (by me) | `h` |
| `IDEA` | Unconfirmed idea/someday | `i` |
| `DONE` | Completed | `d` |
| `KILL` | Cancelled | `k` |

Change state with `t` in agenda or `C-c C-t` in buffer.

---

## AI-Powered Knowledge Management

### Standard Emacs Bindings (`C-c A`)
| Key | Action | Description |
|-----|--------|-------------|
| `C-c A t` | Suggest tags | AI suggests filetags for current buffer |
| `C-c A s` | Summarize paper | Generate AI summary, insert at end |
| `C-c A p` | Process inbox | GTD processing suggestions for item |
| `C-c A r` | Find related | AI finds semantically related notes |
| `C-c A q` | Ask KB | RAG-based Q&A over your notes |
| `C-c A k` | Search KB | Multi-source search (notes, PDFs, bib) |
| `C-c A w` | Weekly review | AI-generated weekly summary |
| `C-c A c` | Check tags | Report tag frequency and duplicates |
| `C-c A o` | Find orphans | Notes with no links in or out |

### Org-Roam AI Bindings (`C-c z`)
| Key | Action |
|-----|--------|
| `S` | Suggest tags for buffer |
| `R` | Find related notes |
| `w` | Generate weekly review |
| `a t` | Suggest tags |
| `a s` | Summarize paper |
| `a r` | Find related notes |
| `a w` | Weekly review |
| `a c` | Check tag consistency |
| `a o` | Find orphan notes |

### Org-Roam UI (`C-c z u`)
| Key | Action |
|-----|--------|
| `u` | Open graph in browser |
| `m` | Toggle UI mode |

### Search Bindings (`C-c s`)
| Key | Action |
|-----|--------|
| `Q` | Ask knowledge base (RAG) |
| `k` | Search knowledge base (consult async: notes, bib, Papers, EPUB) |
| `P` | Search papers (consult async: documents only) |

### Search Syntax (`C-c s k`, `C-c s P`)

Both are consult async searches over `rga` (ripgrep-all) — results narrow as
you type. Hits in text files (`.org`, `.bib`) preview live and jump to the
exact line.

**Flags go straight after the query, with no separator.** Write
`neural --glob *.pdf` — *not* `neural -- --glob *.pdf`. Nothing goes through a
shell, so `*.pdf` needs no quoting.

| Input | Effect |
|-------|--------|
| `neural` | Sent to rga as the search string (one pass over the corpus, ~1.4s) |
| `neural#2024` | `#` splits it: `neural` goes to rga, `2024` filters the results instantly inside Emacs — no new search. The filter only sees the ≤5 hits per file rga already returned, so a file with more matches than that can lose results silently; prepend `--max-count=200` first when you need completeness |
| `neural --glob *.pdf` | Scope to PDFs |
| `neural --glob *.org` | Scope to org files |
| `neural --max-count=200` | Raises the default per-file cap of 5 |
| `neural -i` | Forces case-insensitive (default is `--smart-case`: a capital letter makes it case-sensitive) |
| `C-u C-c s k` | Prompt for which directories/files to search |

> ⚠️ **A bare `--` is an escape, not a separator.** It *ends* option parsing and
> hands everything after it back to the search string. So
> `neural -- --glob *.pdf` searches for lines containing `neural` **and the
> literal text** `--glob` **and** `*.pdf` — which matches nothing, silently.
> Its only real use is searching for text that starts with a dash:
> `-- --max-count` finds that literal string.

**Exporting results** — these are minibuffer bindings, live only while the
search is open (`C-;` is `embark-act` globally):

| Key | Action |
|-----|--------|
| `C-c C-;` | `embark-export` — the old-style static `grep-mode` buffer (still capped at 5 hits/file — re-run with `--max-count=200` first for a complete export) |
| `C-c C-e` | Same, but `wgrep`-editable |
| `C-c C-l` | `embark-collect` |

**PDF and EPUB hits**

| | behaviour |
|---|---|
| `RET` on a PDF | Opens at the **matching page**, read from rga's `Page N:` marker |
| `RET` on an EPUB | Opens at the top — pandoc emits no page markers |
| auto-preview | Off for both. rga's line numbers index extracted text, so previewing would render a page only to land nowhere |
| `C-SPC` | Previews explicitly — but **only for files under 1MB** (`consult-preview-partial-size`). Above that consult reads a 10KB chunk, hits NUL bytes and silently aborts: ~49% of Papers and ~97% of EPUBs |
| `embark-consult-goto-grep` | Still lands on page 1 — it takes its own path, not RET's |

Text hits (`.org`, `.bib`) preview automatically and jump to the exact line.

### Org-mode Local (`C-c l` in org buffers)
| Key | Action |
|-----|--------|
| `B` | Process inbox item |
| `S` | Summarize paper |

`B` and not `P`: `C-c l P` is Doom's org-publish prefix.

### AI Workflow Examples

**Tag a new paper note:**
```
1. Open paper note
2. C-c A t (or C-c z S)
3. Tags copied to kill ring
4. C-y to yank into #+filetags: line
```

**Process GTD inbox:**
```
1. In agenda, go to REFILE item
2. Open the item (RET)
3. C-c A p (or C-c l B in org buffer)
4. Review AI suggestions for:
   - Is it actionable?
   - Suggested project
   - Recommended tags
   - Should it be a roam note?
```

**Ask your knowledge base:**
```
1. C-c A q (or C-c s Q)
2. Type question: "What do my notes say about TPM attestation?"
3. AI searches notes, retrieves context, answers with citations
```

**Weekly review:**
```
1. C-c A w (or C-c z w)
2. AI summarizes notes modified this week
3. Identifies themes, suggests connections
```

---

## Code Formatting

Format-on-save is **gated**: it runs only in projects that declare a formatter
(`treefmt.nix`, `.clang-format`, `rustfmt.toml`, `.pre-commit-config.yaml`,
`.prettierrc*`, a `formatter =` in `flake.nix`, `[tool.ruff]` in
`pyproject.toml`, ...). Other people's repos are never reformatted on save.

`.editorconfig` deliberately does **not** count — it declares indent width, not
a formatter, and plenty of hand-formatted projects ship one.

### Keys
| Key | Action |
|-----|--------|
| `C-x C-s` | Save (formats only if the project declares a formatter) |
| `C-x M-s` | Save **without** formatting, one-off (`+format/save-buffer-no-reformat`) |
| `C-c c f` | Format region, or whole buffer if no region — always works, even in gated projects |

Note: `C-u C-x C-s` does **not** skip formatting, despite what Doom's format
module suggests. Its remap targets `basic-save-buffer`, but `C-x C-s` is bound
to `save-buffer`, so the remap never fires. Use `C-x M-s`.

### Commands
| Command | Action |
|---------|--------|
| `M-x +format/region-or-buffer` | Format on demand, ignores the gate |
| `M-x bmg/format-on-save-reset-cache` | Re-check projects after adding a formatter config mid-session |
| `M-x apheleia-goto-error` | Jump to the formatter's error output |

### Per-project override

Put this in a `.dir-locals.el` at the project root:

```elisp
;; force format-on-save ON in a project with no formatter config
((nil . ((bmg/format-on-save . t))))

;; force it OFF even though the project declares a formatter
((nil . ((bmg/format-on-save . nil))))
```

`bmg/format-on-save` is a safe local variable (`t` / `nil` / `auto`), so
there's no "unsafe local variable" prompt. Default is `auto`.

### Why a one-line edit used to rewrite whole files

With `(format +lsp +onsave)`, formatting is delegated to the LSP server, and
`textDocument/formatting` is **always whole-buffer** — there is no "just the
lines I touched" mode. In a project whose style disagrees with the formatter,
any save rewrote the entire file. Hence the gate. See the `FormatOnSave`
section in `config.org`.

### Caveat: Nix

Emacs formats `.nix` via nixd → `nixfmt` only. In `~/.dotfiles` the canonical
formatter is treefmt (nixfmt + deadnix + statix + nixf-diagnose + shfmt +
keep-sorted), so a file saved in Emacs can still fail the
`treefmt --fail-on-change` pre-commit hook. Run `nix fmt` before committing.

---

## Spelling & Grammar

Three tools, deliberately non-overlapping: **jinx** spell-checks everything as
you type, **harper-ls** grammar-checks comments in code automatically, and
**LanguageTool** grammar-checks prose on demand.

Doom's `:checkers spell` is **disabled** in `init.el` — jinx replaces spell-fu
entirely, so `spell-fu-mode` no longer exists.

### Spelling (jinx)
| Key | Action |
|-----|--------|
| `M-$` | Correct nearest misspelled word — or the whole region, if one is active |
| `C-u M-$` | Correct every misspelling in the buffer |
| `C-u C-u M-$` | Correct the word before point |
| `C-c t s` | Toggle `jinx-mode` in this buffer |

`jinx-languages` is `"en_GB en_US"` — enchant checks both at once, so `colour`
and `color` both pass. `jinx-camel-modes` is `t`, so camelCase is split before
checking and `callPackage` reads as `call` + `Package`.

Personal dictionary: `~/.config/enchant/en_GB.dic`, one word per line, editable
by hand. Saving from the `M-$` menu appends to it. This is **not**
`ispell-personal-dictionary` — jinx goes through enchant, never ispell.

Flake refs (`github:owner/repo`) are excluded in `nix-ts-mode`, otherwise every
input name in a `flake.nix` gets flagged.

### Grammar in prose (LanguageTool, `C-c g`)
| Key | Action |
|-----|--------|
| `c` | Check buffer |
| `d` | Clear results |
| `f` | Correct buffer interactively |
| `.` | Correct at point |
| `m` | Show the full message at point |
| `n` / `p` | Next / previous error |
| `w` | Toggle `writegood-mode` |

The server is a **systemd service** (`services.languagetool` in `~/.dotfiles`),
enabled at boot on `127.0.0.1:8081`. Emacs never spawns it — langtool.el runs in
HTTP-client mode. It appears as ~97 rows in htop; that is one JVM with 97
threads, press `H` to hide threads.

### Grammar in code (harper-ls)

Runs automatically as an LSP **add-on** server beside nixd/clangd/etc., in the
modes listed in `bmg/harper-modes`. No keybindings — diagnostics arrive through
flycheck like any other LSP warning.

harper has no parser for **elisp, yaml or json**; it falls back to linting those
files as plain English, which is why activation is an explicit whitelist rather
than all of `prog-mode`.

Five linters are disabled because they misfire on code comments: `SpellCheck`
(jinx owns spelling), `ToDoHyphen` (TODO is a code convention, not "to-do"),
`OrthographicConsistency`, `SentenceCapitalization`, `NumericRangeEnDash`.

harper keeps a separate dictionary at `~/.config/harper-ls/dictionary.txt`.

---

## Undo

| Key | Action |
|-----|--------|
| `C-/` or `C-x u` | **vundo** — visual undo tree |
| `C-_` | Linear undo (`undo-fu-only-undo`) |
| `M-_` | Linear redo (`undo-fu-only-redo`) |
| `C-M-_` | Redo everything (`undo-fu-only-redo-all`) |
| `C-x r u` / `C-x r U` | Save / recover undo session |

`C-/` is one chord instead of two, but **cannot be sent over a TTY** — it is not
an ASCII character. `C-_` is ASCII 0x1F and works everywhere, which is why it
keeps the linear undo.

### Inside vundo
| Key | Action |
|-----|--------|
| `f` / `b` | Forward / back along the current branch |
| `n` / `p` | Move between branches |
| `a` / `e` | Jump to branch root / end |
| `l` | Go to the last saved state |
| `d` | Diff against the marked node |
| `RET` | Accept the selected state and close |
| `q` or `C-g` | Cancel — returns to where you started |

The buffer updates live as you move, so `RET` keeps what you are looking at and
`q` throws it away. vundo renders the **built-in** `buffer-undo-list` and stores
nothing of its own — unlike undo-tree there is no parallel history file to
corrupt. Doom's `:emacs (undo)` has no `+tree` flag, so undo-tree is not
installed at all.

History survives restarts via `undo-fu-session` (zstd-compressed, under
`.local/cache/undo-fu-session/`).

If `C-x` sequences ever go dead, check for a stuck transient — an open transient
menu installs `overriding-terminal-local-map`, which sits above every other
keymap and can bind `C-x` itself. `q` or `C-g` in that frame clears it.

---

## Navigation

| Key | Action |
|-----|--------|
| `M-RET` | Follow the LSP document link under point |
| `C-.` | `+lookup/file` — open the path at point (ffap) |
| `C-c s f` | Same command, Doom's original binding |
| `M-.` / `M-,` | Jump to definition / back |
| `C-M-,` | Forward again |

`M-RET` uses the language server's resolved target, so in nix a `../services`
import opens the file nixd actually resolves it to. `C-.` is heuristic (ffap) and
needs no LSP, so it works in comments, strings and log output. Both push the
xref marker stack, so `M-,` returns from either.

Directories open in Dirvish, since `dirvish-override-dired-mode` is on.

---

## Tips

- **Quick find**: `C-c z f` then type part of title
- **Insert link**: While typing, `C-c z i` to link to another note
- **Backlinks**: `C-c z t` to see what links to current note
- **Graph view**: `C-c z g` for visual connections
- **Search all org**: `C-c z s` (consult-org-roam-search)
- **AI tag suggestions**: `C-c A t` for smart tagging
- **Ask your notes**: `C-c A q` to query your knowledge base

---

## Setup Requirements

### AI Features (gptel via GitHub Copilot)
gptel is backed by GitHub Copilot (`gptel-make-gh-copilot`) — no
Anthropic API key or `~/.netrc` entry is needed. Authenticate once
with your GitHub account when prompted (Copilot subscription required).
Other API keys, if ever needed, belong in `~/.authinfo.gpg`.

The `agent-shell` integration authenticates separately via
`claude` login (packages come from Nix, not packages.el — see the
"Claude Agent via ACP" note in config.org).

Test with `M-x gptel` after running `doom sync`.
