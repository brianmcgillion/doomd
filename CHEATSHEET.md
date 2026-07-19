# Doom Emacs Org-mode Cheat Sheet

## Quick Reference

### Global Capture (`C-c n n` or `SPC X`)
| Key | Action | Target |
|-----|--------|--------|
| `t` | Personal todo | `roam/inbox-{host}.org` → Inbox |
| `n` | Personal note | `roam/inbox-{host}.org` → Inbox |
| `j` | Journal entry | `roam/inbox-{host}.org` → datetree |
| `p t` | Project todo | `roam/projects/{project}/todo.org` → Inbox |
| `p n` | Project note | `roam/projects/{project}/notes.org` → Inbox |
| `p c` | Project changelog | `roam/projects/{project}/changelog.org` |

### Org-Roam (`SPC z`)
| Key | Action | Description |
|-----|--------|-------------|
| `c` | Capture | New roam note (choose template) |
| `f` | Find | Search all roam nodes |
| `i` | Insert | Insert link to roam node |
| `t` | Toggle buffer | Show/hide backlinks |
| `g` | Graph | Visualize connections |
| `r` | Refile | Move current node |

### Org-Roam Capture Templates (`SPC z c`)
| Key | Template | Location |
|-----|----------|----------|
| `d` | Default note | `roam/{slug}.org` |
| `f` | Fleeting (quick) | `roam/inbox-{host}.org` → Inbox |
| `r` | Reference | `roam/refs/{slug}.org` |
| `m` | Meeting | `roam/meetings/{date}-{slug}.org` |

### Dailies (`SPC z d`)
| Key | Action |
|-----|--------|
| `t` | Go to today |
| `n` | Capture today |
| `y` | Go to yesterday |
| `d` | Go to specific date |
| `b/f` | Previous/next note |

### Project Notes (`SPC z p`)
| Key | Action | Target |
|-----|--------|--------|
| `t` | Project TODO | `projects/{project}/todo.org` → Inbox |
| `n` | Project note | `projects/{project}/notes.org` → Inbox |
| `p` | Project roam note | `projects/{project}/{slug}.org` (new file) |
| `T` | Open project TODO | Opens `todo.org` directly |
| `N` | Open project notes | Opens `notes.org` directly |

### Node Properties (`SPC z o`)
| Key | Action |
|-----|--------|
| `a/A` | Add/remove alias |
| `t/T` | Add/remove tag |
| `r/R` | Add/remove ref |

### Agenda (`SPC n a` or `SPC o a`)
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
- **Quick thought**: `SPC X t` (personal todo) or `SPC z c f` (fleeting)
- **Project task**: `SPC z p t` (while in project directory)
- **Meeting notes**: `SPC z c m`
- **Reference**: `SPC z c r`

All inbox captures automatically get `:REFILE:` tag.

### 2. Process (Empty your inboxes)
- Open agenda: `SPC n a` or `SPC o a`
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
- **Daily**: Check agenda (`SPC n a`)
- **Weekly**: `M-x bmg/org-roam-review-week`

### Complete Processing Example

```
1. CAPTURE: SPC z p t → "Fix login bug"
   Creates: projects/my-app/todo.org
   └── * Inbox
       └── ** TODO Fix login bug :REFILE:

2. AGENDA: SPC n a
   Shows: 📥 Inbox - Process these first
          └── TODO Fix login bug  :REFILE:  (my-app/todo.org)

3. PROCESS: On the item, press:
   - `t` → change state (TODO → STRT if starting now)
   - `s` → schedule for a date
   - `d` → set deadline
   - `R` → refile to different file/heading
   
4. REMOVE TAG: 
   - Open file: `SPC z p T`
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
| All inbox items | Agenda (`SPC n a`) → "📥 Inbox" section |
| Project's todos | `SPC z p T` (opens project's todo.org) |
| Any roam node | `SPC z f` then type title |
| Project nodes only | `SPC z f` then type `#project` |
| Today's tasks | Agenda → "Today" section |
| Search all org | `SPC s o` |

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

In `SPC z f` (org-roam-node-find), type `#tag` to filter:

| Tag | Content |
|-----|---------|
| `#project` | All project-related notes |
| `#meeting` | Meeting notes |
| `#daily` | Daily notes |
| `#reference` | Literature/references |
| `#todo` | Project todo files |

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

### Org-Roam AI Bindings (`M-SPC z` or `SPC z`)
| Key | Action |
|-----|--------|
| `z S` | Suggest tags for buffer |
| `z R` | Find related notes |
| `z w` | Generate weekly review |
| `z a t` | Suggest tags |
| `z a s` | Summarize paper |
| `z a r` | Find related notes |
| `z a w` | Weekly review |
| `z a c` | Check tag consistency |
| `z a o` | Find orphan notes |

### Org-Roam UI (`M-SPC z u` or `SPC z u`)
| Key | Action |
|-----|--------|
| `u u` | Open graph in browser |
| `u m` | Toggle UI mode |

### Search Bindings (`M-SPC s` or `SPC s`)
| Key | Action |
|-----|--------|
| `s Q` | Ask knowledge base (RAG) |
| `s k` | Search knowledge base |
| `s P` | Search papers (rga) |

### Org-mode Local (`C-c l` in org buffers)
| Key | Action |
|-----|--------|
| `P` | Process inbox item |
| `S` | Summarize paper |

### AI Workflow Examples

**Tag a new paper note:**
```
1. Open paper note
2. C-c A t (or M-SPC z S)
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
1. C-c A q (or M-SPC s Q)
2. Type question: "What do my notes say about TPM attestation?"
3. AI searches notes, retrieves context, answers with citations
```

**Weekly review:**
```
1. C-c A w (or M-SPC z w)
2. AI summarizes notes modified this week
3. Identifies themes, suggests connections
```

---

## Tips

- **Quick find**: `SPC z f` then type part of title
- **Insert link**: While typing, `SPC z i` to link to another note
- **Backlinks**: `SPC z t` to see what links to current note
- **Graph view**: `SPC z g` for visual connections
- **Search all org**: `SPC s o` (org search)
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
