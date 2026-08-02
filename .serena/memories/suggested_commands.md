# Suggested Commands

`doom` is not on `PATH` by default: use `~/.config/emacs/bin/doom`.

| Command | When |
|---------|------|
| `~/.config/emacs/bin/doom sync` | after ANY change to `config.org`, `init.el`, `packages.el`. Tangles config.org → config.el, installs/removes packages, rebuilds. |
| `~/.config/emacs/bin/doom doctor` | diagnose config problems / verify after sync |
| `~/.config/emacs/bin/doom upgrade` | update Doom + all packages |
| `~/.config/emacs/bin/doom env` | regenerate the env snapshot (needed after shell env changes) |
| `M-x doom/reload` (in Emacs) | apply changes without restarting; otherwise restart Emacs |

Byte-check a standalone file without a full sync:
`emacs --batch -f batch-byte-compile remarkable-config.el` (then delete the produced `.elc`).

Notes:
- Editing only `elfeed-config.el` / `remarkable-config.el` does not require tangling, but still
  needs `doom sync` or `M-x doom/reload` to take effect.
- `init.el` allowlists `^SSH_` into `doom-env-allow` — relevant when `doom env` output looks wrong.
- System utils behave as standard GNU/Linux (NixOS); no platform-specific command forms needed.
