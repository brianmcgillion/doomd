;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here, run 'doom sync' on
;; the command line, then restart Emacs for the changes to take effect.
;; Alternatively, use M-x doom/reload.
;;
;; WARNING: Disabling core packages listed in ~/.emacs.d/core/packages.el may
;; have nasty side-effects and is not recommended.


;; All of Doom's packages are pinned to a specific commit, and updated from
;; release to release. To un-pin all packages and live on the edge, do:
;;(unpin! t)

;; ...but to unpin a single package:
;;(unpin! pinned-package)
;; Use it to unpin multiple packages
;;(unpin! pinned-package another-pinned-package)


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;;(package! some-package)

;; To install a package directly from a particular repo, you'll need to specify
;; a `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/raxod502/straight.el#the-recipe-format
;;(package! another-package
;;  :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;;(package! this-package
;;  :recipe (:host github :repo "username/repo"
;;           :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, for whatever reason,
;; you can do so here with the `:disable' property:
;;(package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;;(package! builtin-package :recipe (:nonrecursive t))
;;(package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see raxod502/straight.el#279)
;;(package! builtin-package :recipe (:branch "develop"))

;; For RSS and Atom feeds
(package! elfeed-score)

;; a modern agenda and styled capture
(package! org-super-agenda)

(package! inheritenv)

;; Add style to org
;; (package! doct
;;   :recipe (:host github :repo "progfolio/doct"))

;; roam and related packages
(unpin! org-roam)
(package! websocket)
(package! org-roam-ui :recipe (:host github :repo "org-roam/org-roam-ui" :files ("*.el" "out")))
(package! emacsql-sqlite3)

(package! org-mem)

;; roam and org related packages for literature
(package! biblio)
(package! org-ref)

;; General helper packages
(package! super-save)
(package! crux)
;; Download repos from git forges into local dirs under a main repo structure
(package! my-repo-pins)

(package! license-snippets)

;; Copilot
(package! copilot
  :recipe (:host github :repo "copilot-emacs/copilot.el" :files ("*.el")))

;; mcp for gptel
(package! mcp
  :recipe (:host github :repo "lizqwerscott/mcp.el" :files ("*.el")))

(package! aidermacs)
;; Example of overloading a package to do local development
;;(package! aidermacs :recipe (:local-repo "/home/brian/projects/code/github.com/MatthewZMD/aidermacs"))

;; Yuck mode is for ew
(package! yuck-mode)

;; just file mode
(package! justl :recipe (:host github :repo "psibi/justl.el"))
(package! just-mode)
