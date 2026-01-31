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

## Tips

- **Quick find**: `SPC z f` then type part of title
- **Insert link**: While typing, `SPC z i` to link to another note
- **Backlinks**: `SPC z t` to see what links to current note
- **Graph view**: `SPC z g` for visual connections
- **Search all org**: `SPC s o` (org search)
