# Core

Personal Doom Emacs configuration (`$DOOMDIR` = `/home/brian/.config/doom`). Not an application —
a literate Emacs config. No test suite, no build artifacts beyond tangling.

## Hard invariant

`config.org` is the ONLY source of truth for `config.el`. `config.el` is tangled output
(Doom `:config literate` module) and is **gitignored** — editing it is always wrong; `doom sync`
overwrites it. Same for `custom.el` (gitignored, Emacs-managed).

## Source map

| File | Edit | Role |
|------|------|------|
| `config.org` | yes | ~1650 lines, literate source; every `#+BEGIN_SRC emacs-lisp` block tangles into `config.el` |
| `config.el` | NO | generated, gitignored |
| `init.el` | yes | `doom!` module list only |
| `packages.el` | yes | `package!`/`unpin!` declarations only — never configuration |
| `elfeed-config.el` | yes | standalone; `load!`-ed from config.org line ~228 |
| `remarkable-config.el` | yes | standalone; `load!`-ed at end of config.org; embedded pseudo-package |
| `CHEATSHEET.md` | yes | user-facing keybinding/capture reference — update when bindings change |
| `.github/copilot-instructions.md` | yes | long-form module/keybinding/org docs |
| `banner/`, `snippets/` | — | splash images; yasnippet dir (empty) |

## config.org top-level sections

Flat, one org heading per domain, each wrapping one big src block delimited by
`;;; BEGIN_<Name>` / `;;; END_<Name>` comment markers:
`Interface Tweaks` → `General` → `Code` → `LLM/ML` → `Org` → `Map` → `Elfeed Enhancements`
→ `reMarkable Integration`. Locate work by section marker, not by line number.

Notable: the `Map` section holds nearly all keybindings; the `Org` section holds
org/org-roam/capture/agenda (the largest section, ~500 lines).

## Further reading

- Languages, Doom modules, package sources and how Emacs itself is provisioned: `mem:tech_stack`
- Tangle/sync/reload commands and Doom CLI specifics: `mem:suggested_commands`
- Doom-macro vs. plain-Emacs style rules, naming prefixes, keybinding footguns: `mem:conventions`
- What to run before declaring a config change done: `mem:task_completion`

## Paths referenced by the config

- `org-directory` = `~/Documents/org/`; `org-roam-directory` = `~/Documents/org/roam/`
- per-host inbox: `roam/inbox-<system-name>.org`
- nixd LSP resolves flake expressions against `~/.dotfiles`
- API keys come from `~/.authinfo.gpg` — never inline a key in config.org
