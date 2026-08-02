# Conventions

## Placement

- All elisp changes go into a `#+BEGIN_SRC emacs-lisp` block in `config.org`, inside the
  matching `;;; BEGIN_<Section>` / `;;; END_<Section>` region — see the section list in `mem:core`.
- `packages.el` holds declarations only; the corresponding configuration goes in `config.org`.
- Every standalone `.el` file starts with `;;; <filename>.el -*- lexical-binding: t; -*-`.

## Modern Emacs over deprecated Doom macros

- `with-eval-after-load` — not `after!`
- `use-package` — not `use-package!`
- `setopt` for `defcustom` variables (it type-validates). Use `setq` for non-defcustom vars —
  Doom's `+`-prefixed vars, plain `defvar`s — and for complex template structures that fail
  `setopt` validation (org capture templates, agenda commands).
- Wrap package configuration in `with-eval-after-load`.

## Still use the Doom macro

- `map!` for keybindings, **not** `define-key`. Exception: `define-key` is correct (and used)
  when building a standalone sparse keymap inside a `defvar` initializer — e.g.
  `bmg/ai-command-map`, `remarkable-command-map` — because `map!` cannot yield a keymap value.

## Keybinding footgun

Never re-label an existing Doom `:prefix` with a which-key label
(`(:prefix ("n" . "notes") ...)` over a Doom-owned prefix) — it silently wipes every binding
under that prefix (Doom commit 635bc939d). Use a bare `(:prefix "n" ...)` or
`which-key-add-keymap-based-replacements`.

Related: within `org-mode-map` the localleader `P` is Doom's org-publish prefix, so the config
deliberately uses `B` instead.

## Naming

- Custom functions/vars: `bmg/` prefix.
- Exception: `remarkable-config.el` uses a `remarkable-` prefix — it is an embedded
  pseudo-package with its own `defgroup` and `defcustom`s. Keep that prefix inside that file.

## Editor model

No evil mode (see `mem:tech_stack`) — standard Emacs keybindings throughout; leader is
`C-c`/`M-SPC` style via Doom's `+bindings`.

## Docs to keep in sync

Keybinding or capture-template changes should be reflected in `CHEATSHEET.md`, and larger
structural changes in `.github/copilot-instructions.md`.
