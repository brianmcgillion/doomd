# Tech Stack

- Language: Emacs Lisp only, embedded in org-mode (`#+BEGIN_SRC emacs-lisp`). No compiled code.
- Framework: Doom Emacs, `$EMACSDIR` = `~/.config/emacs` (not `~/.emacs.d`).
- Emacs is provisioned by **Nix** (`/run/current-system/sw/bin/emacs` →
  `/nix/store/...-emacs-git-with-packages-*`), declared in
  `~/.dotfiles/modules/features/development/emacs.nix`.
- **Nix-supplied elisp is invisible to `M-x`.** Nix drops packages into site-lisp and relies on
  package.el to evaluate their `*-autoloads.el`, but Doom sets `package-enable-at-startup` to nil
  (`~/.config/emacs/lisp/doom.el`), so `package-activate-all` never runs. The library lands on
  `load-path` (so `require` works and `locate-library` succeeds) yet **no command is ever
  defined**. Symptom: `M-x <pkg>-` completes to nothing, and any
  `with-eval-after-load '<pkg>` config block silently never fires.
- Therefore: **only native-dependency packages belong in Nix** (vterm, pdf-tools,
  tree-sitter-langs, treesit-grammars, djvu, nov, org-pdftools). Pure elisp belongs in
  `packages.el` so straight builds it and Doom generates the autoloads. `agent-shell`/`acp`/
  `shell-maker` and `claude-code` were moved out of Nix on 2026-07-29 for exactly this reason.
  Straight builds shadow Nix site-lisp copies on `load-path`.
- Package manager: straight.el via Doom's `package!` macro. Doom pins packages; `unpin!` is used
  for `org-roam` and `nix-ts-mode`.
- No language servers/linters for this repo itself; LSP config in it targets other languages
  (`nixd` with flake exprs at `~/.dotfiles`, `clangd` with background index + clang-tidy,
  pyright, rust-analyzer, gopls...).

## Doom module highlights (init.el)

Completion: `corfu +orderless +icons +dabbrev` + `vertico +icons` — **not** company/ivy/helm.
Editor: `format +lsp +onsave` (format-on-save is on), `snippets`, `whitespace +guess +trim`.
Emacs: `dired +icons +dirvish`, `tramp`, `vc`. Term: `vterm`.
Tools: `biblio`, `direnv`, `docker +lsp`, `eval +overlay`, `lookup +dictionary +docsets +offline`,
`llm`, `lsp +peek`, `magit +forge`, `pdf`, `tree-sitter`.
Lang: cc, data, emacs-lisp, go, json, javascript, latex, markdown `+grip`, nix, org
(`+pandoc +pretty +present +roam +noter`), python (`+pyright +uv`), rust, sh, yaml — all `+lsp
+tree-sitter` where available.
App: `rss +org`. Config: `literate`, `default +bindings +smartparens`.

**`:editor evil` is absent — this is a vanilla-keybinding Doom setup.** Never write evil-specific
config or `:n`/`:v` state keys in `map!`.

## Notable third-party packages (packages.el)

`elfeed-score`, `org-super-agenda`, `inheritenv`, `org-roam-ui`, `org-mem`, `biblio`, `org-ref`,
`crux`, `my-repo-pins`, `license-snippets`, `copilot` (github recipe, inline completions),
`yuck-mode` (ElKowar's eww widget config, not the Emacs browser), `justl` + `just-mode`,
`consult-org-roam`, `nasm-mode`, `x86-lookup`.
