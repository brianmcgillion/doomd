# Task Completion

There is no linter, formatter, type checker or test suite for this repo. "Done" means the config
tangles, syncs and loads cleanly.

1. Confirm the edit landed in `config.org` (not `config.el` — see the invariant in `mem:core`).
   `git status` should never show `config.el` (gitignored).
2. `~/.config/emacs/bin/doom sync` — must exit 0. This is the real correctness gate: it tangles
   and byte-compiles.
3. `~/.config/emacs/bin/doom doctor` — check for new warnings/errors.
4. Reload: `M-x doom/reload` in a running Emacs, or restart Emacs. Exercise the changed
   binding/command once; elisp errors only surface at load or call time.
5. If keybindings or capture templates changed, update `CHEATSHEET.md`.

Do not claim success on the basis of the edit alone — steps 2–4 are where breakage appears.
Command details and the batch byte-compile shortcut for standalone `.el` files:
`mem:suggested_commands`.
