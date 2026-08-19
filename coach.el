;;; coach.el --- Suggest faster ways to do what you just did -*- lexical-binding: t; -*-
;;; Commentary:
;; Watches which commands run; when a slower route is used where a faster one
;; exists, says so once.  Design: docs/superpowers/specs/2026-08-16-emacs-coach-design.md
;;; Code:

(require 'ring)
(require 'cl-lib)
(require 'seq)

(defgroup coach nil
  "Suggest faster ways to do what you just did."
  :group 'convenience
  :prefix "coach-")

(defcustom coach-history-size 200
  "How many recent commands the detectors may look at."
  :type 'integer
  :group 'coach)

(defvar coach--ring nil
  "Ring of (COMMAND MODE EVENT), newest first via `ring-elements'.")

(defsubst coach-entry-command (entry) (nth 0 entry))
(defsubst coach-entry-mode (entry) (nth 1 entry))
(defsubst coach-entry-event (entry) (nth 2 entry))

(defun coach--ensure-ring ()
  "Return the ring, rebuilt if `coach-history-size' changed."
  (unless (and (ring-p coach--ring)
               (= (ring-size coach--ring) coach-history-size))
    (setq coach--ring (make-ring coach-history-size)))
  coach--ring)

(defun coach--record ()
  "Push the command that just ran.  Runs in `post-command-hook', so no analysis here."
  (with-demoted-errors "coach: %S"
    (when (symbolp this-command)
      (ring-insert (coach--ensure-ring)
                   (list this-command major-mode last-command-event)))))

(defun coach-snapshot ()
  "Return recorded entries, newest first."
  (when (ring-p coach--ring)
    (ring-elements coach--ring)))

;;;; Rules

(cl-defstruct (coach-rule (:constructor coach-make-rule))
  "One thing worth noticing.  PREDICATE is a pure function of a snapshot."
  id modes predicate message (cooldown 600))

(defvar coach-rules nil
  "List of `coach-rule' structs.")

(defun coach-register-rule (rule)
  "Add RULE, replacing any rule with the same id.  Return RULE."
  (setq coach-rules
        (cons rule (cl-remove (coach-rule-id rule) coach-rules
                              :key #'coach-rule-id)))
  rule)

(defun coach--leading-run (snapshot commands)
  "Count SNAPSHOT's newest entries running a command in COMMANDS.
Stops at the first miss, so this measures a run and not a total."
  (let ((n 0))
    (catch 'done
      (dolist (entry snapshot)
        (if (memq (coach-entry-command entry) commands)
            (setq n (1+ n))
          (throw 'done n)))
      n)))

(defun coach--rule-applies-p (rule)
  "Return non-nil if RULE's modes allow the current buffer."
  (let ((modes (coach-rule-modes rule)))
    (or (null modes) (apply #'derived-mode-p modes))))

(defun coach--matching-rules (snapshot)
  "Return rules whose predicate fires on SNAPSHOT in this buffer."
  (seq-filter (lambda (rule)
                (and (coach--rule-applies-p rule)
                     (funcall (coach-rule-predicate rule) snapshot)))
              coach-rules))

;;;; Rules: motion

(coach-register-rule
 (coach-make-rule
  :id 'repeated-line-motion
  :predicate (lambda (snapshot)
               (>= (coach--leading-run snapshot '(next-line previous-line)) 8))
  :message "8+ line motions in a row -- M-j (avy) or C-c s b (consult-line) is one jump"))

(defun coach--leading-run-by (snapshot pred)
  "Count SNAPSHOT's newest entries satisfying PRED."
  (let ((n 0))
    (catch 'done
      (dolist (entry snapshot)
        (if (funcall pred entry)
            (setq n (1+ n))
          (throw 'done n)))
      n)))

(coach-register-rule
 (coach-make-rule
  :id 'repeated-char-motion
  :predicate (lambda (snapshot)
               (>= (coach--leading-run snapshot '(forward-char backward-char)) 10))
  :message "10+ character motions -- M-f/M-b move by word, M-j (avy) jumps anywhere"))

;; <up> and C-p both run `previous-line', so only the event tells them apart.
(defconst coach--arrow-events '(up down left right))

(coach-register-rule
 (coach-make-rule
  :id 'arrow-keys
  :predicate (lambda (snapshot)
               (>= (coach--leading-run-by
                    snapshot
                    (lambda (e) (memq (coach-entry-event e) coach--arrow-events)))
                   3))
  :message "arrow keys -- C-n/C-p/C-f/C-b keep your hands on the home row"))

(coach-register-rule
 (coach-make-rule
  :id 'mouse-jump
  :modes '(prog-mode)
  :predicate (lambda (snapshot)
               (eq 'mouse-set-point (coach-entry-command (car snapshot))))
  :message "mouse to move point -- M-j (avy) reaches anything on screen"))

(defconst coach--switch-commands
  '(consult-buffer switch-to-buffer +vertico/switch-workspace-buffer))

(defconst coach--xref-commands
  '(xref-find-definitions +lookup/definition))

(defconst coach--return-commands
  '(better-jumper-jump-backward xref-go-back pop-global-mark))

(defun coach--no-return-p (snapshot)
  "Non-nil if a definition jump was left by switching buffers by hand.
Newest ten entries only; a larger index is older, so the jump must predate
the switch."
  (let* ((window (seq-take snapshot 10))
         (commands (mapcar #'coach-entry-command window))
         (switch (cl-position-if (lambda (c) (memq c coach--switch-commands)) commands))
         (jump (cl-position-if (lambda (c) (memq c coach--xref-commands)) commands)))
    (and switch jump (> jump switch)
         (not (seq-some (lambda (c) (memq c coach--return-commands)) commands)))))

(coach-register-rule
 (coach-make-rule
  :id 'no-return
  :predicate #'coach--no-return-p
  :message "switched buffers by hand after a jump -- M-, returns from where you came"))

;;;; Rules: magit

(defun coach--count-command (snapshot commands)
  "Count entries anywhere in SNAPSHOT whose command is in COMMANDS."
  (seq-count (lambda (e) (memq (coach-entry-command e) commands)) snapshot))

(coach-register-rule
 (coach-make-rule
  :id 'stage-whole-file
  :predicate (lambda (snapshot)
               (>= (coach--count-command snapshot '(magit-stage-file)) 2))
  :message "staging whole files -- s on a hunk stages just that hunk, TAB expands it"))

(coach-register-rule
 (coach-make-rule
  :id 'repeated-amend
  :predicate (lambda (snapshot)
               (>= (coach--count-command snapshot '(magit-commit-amend)) 2))
  :message "repeated amends -- C-c v c f makes a fixup, then rebase --autosquash"))

;;;; Rules: notes and files

;; Kept outside the ring so no path ever reaches *coach* or the log.
(defvar coach--file-visits (make-hash-table :test #'equal)
  "Absolute path -> visits this session.")

(defun coach--note-visit (path)
  "Record a visit to PATH."
  (when path
    (puthash path (1+ (or (gethash path coach--file-visits) 0)) coach--file-visits)))

(defun coach--note-visit-h ()
  "Record this buffer's file.  Runs in `find-file-hook'."
  (with-demoted-errors "coach: %S"
    (coach--note-visit buffer-file-name)))

(add-hook 'find-file-hook #'coach--note-visit-h)

(coach-register-rule
 (coach-make-rule
  :id 'refind-file
  :cooldown 1800
  :predicate (lambda (_snapshot)
               (catch 'hit
                 (maphash (lambda (_path count) (when (>= count 2) (throw 'hit t)))
                          coach--file-visits)
                 nil))
  :message "opened the same file again -- C-x r m bookmarks it, C-c s m jumps back"))

(coach-register-rule
 (coach-make-rule
  :id 'project-notes
  :cooldown 14400
  :predicate (lambda (snapshot)
               (memq 'projectile-switch-project
                     (mapcar #'coach-entry-command (seq-take snapshot 5))))
  :message "new project -- C-c z p N opens its notes, C-c z p t captures a todo"))

;;;; Throttle

(defcustom coach-global-cooldown 120
  "Minimum seconds between any two nudges, whatever the rule."
  :type 'integer
  :group 'coach)

(defvar coach--rule-last-fired (make-hash-table :test #'eq)
  "Rule id -> float time it last fired.")

(defvar coach--last-nudge nil
  "Float time of the last nudge of any kind.")

(defvar coach--pending nil
  "Entries shown but not yet written to `coach-log-file'.")

(defun coach--may-fire-p (rule now)
  "Return non-nil if RULE may fire at NOW.
NOW is passed in rather than read from the clock so this is testable."
  (and (or (null coach--last-nudge)
           (>= (- now coach--last-nudge) coach-global-cooldown))
       (let ((last (gethash (coach-rule-id rule) coach--rule-last-fired)))
         (or (null last)
             (>= (- now last) (coach-rule-cooldown rule))))))

(defun coach--note-fired (rule now)
  "Record that RULE fired at NOW."
  (puthash (coach-rule-id rule) now coach--rule-last-fired)
  (setq coach--last-nudge now))

;;;; Presenter

(defcustom coach-buffer-name "*coach*"
  "Buffer holding the running history of suggestions."
  :type 'string
  :group 'coach)

(defun coach--present (rule now)
  "Show RULE's message, append it to `coach-buffer-name', queue it for the log."
  (message "coach: %s" (coach-rule-message rule))
  (with-current-buffer (get-buffer-create coach-buffer-name)
    (goto-char (point-max))
    (insert (format-time-string "[%F %T] " now)
            (format "%s: %s\n" (coach-rule-id rule) (coach-rule-message rule))))
  (push (list :id (coach-rule-id rule)
              :time now
              :message (coach-rule-message rule))
        coach--pending))

;;;; Log

(defcustom coach-log-file
  (expand-file-name "coach.log" (or (bound-and-true-p doom-cache-dir)
                                    user-emacs-directory))
  "Append-only record read by the review commands.
Rule ids, times and messages only -- never paths or buffer contents."
  :type 'file
  :group 'coach)

(defvar coach--flush-timer nil)

(defun coach--flush ()
  "Append pending entries to `coach-log-file'.  Non-nil if any were."
  (when coach--pending
    (with-demoted-errors "coach: %S"
      (let ((entries (nreverse coach--pending)))
        (setq coach--pending nil)
        (with-temp-buffer
          (dolist (entry entries)
            (prin1 entry (current-buffer))
            (insert "\n"))
          (write-region (point-min) (point-max) coach-log-file t 'silent))
        t))))

;;;; Driver

(defcustom coach-idle-delay 1.0
  "Seconds idle before detectors run.
Never in `post-command-hook': typing stays fast and nudges land at a pause."
  :type 'number
  :group 'coach)

(defvar coach--idle-timer nil)

(defun coach--check ()
  "Run detectors over the current snapshot and nudge at most once."
  (with-demoted-errors "coach: %S"
    (let ((snapshot (coach-snapshot)))
      (when snapshot
        (let* ((now (float-time))
               (rule (seq-find (lambda (r) (coach--may-fire-p r now))
                               (coach--matching-rules snapshot))))
          (when rule
            (coach--note-fired rule now)
            (coach--present rule now)))))))

;;;; Commands

(defun coach-show-log ()
  "Show the running history of suggestions."
  (interactive)
  (pop-to-buffer (get-buffer-create coach-buffer-name)))

(defun coach-snooze (&optional minutes)
  "Silence nudges for MINUTES, default 30."
  (interactive "P")
  (let ((mins (if (numberp minutes) minutes 30)))
    (setq coach--last-nudge (+ (float-time) (* 60 mins) (- coach-global-cooldown)))
    (message "coach: snoozed for %d min" mins)))

(defun coach-list-rules ()
  "List rules and when each may next fire."
  (interactive)
  (let ((now (float-time)))
    (with-current-buffer (get-buffer-create "*coach rules*")
      (erase-buffer)
      (dolist (rule (reverse coach-rules))
        (insert (format "%-24s %-8s %s\n"
                        (coach-rule-id rule)
                        (if (coach--may-fire-p rule now) "ready" "cooling")
                        (coach-rule-message rule))))
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

;;;; Review

;; Without this an LLM suggests keys that are not bound here, and wrong
;; advice costs more to unlearn than none.
(defcustom coach-context-commands
  '(avy-goto-char-timer avy-goto-line consult-line consult-imenu consult-outline
    consult-mark consult-global-mark
    +default/search-project +default/search-project-for-symbol-at-point
    xref-find-definitions better-jumper-jump-backward pop-global-mark
    sp-forward-sexp sp-up-sexp sp-down-sexp mark-sexp er/expand-region
    magit-status magit-commit-fixup magit-stage-file
    org-roam-capture org-roam-node-find bookmark-set bookmark-jump
    vertico-repeat embark-act ace-window)
  "Commands whose real bindings are shipped as context to a review."
  :type '(repeat symbol)
  :group 'coach)

(defun coach-keymap-context ()
  "Return a table of `coach-context-commands' and their real keys."
  (mapconcat
   (lambda (command)
     ;; No `fboundp' guard: Doom binds lazily, so an unloaded command still
     ;; has a key, and gating on fboundp reports it as UNBOUND.
     (let ((keys (where-is-internal command)))
       (format "%-32s %s" command
               (if keys (mapconcat #'key-description keys "  ") "UNBOUND"))))
   coach-context-commands
   "\n"))

(defun coach--log-tail (n)
  "Return the last N lines of `coach-log-file', flushing pending first."
  (coach--flush)
  (if (not (file-readable-p coach-log-file))
      ""
    (with-temp-buffer
      (insert-file-contents coach-log-file)
      (mapconcat #'identity
                 (last (split-string (buffer-string) "\n" t) n)
                 "\n"))))

(defconst coach--review-system
  "You are reviewing how someone drives Emacs, to make them faster.
You are given the keys actually bound in their config, and a log of
suggestions their local rules already fired.
Never suggest a key absent from the bindings table -- name the command
instead. Prefer three concrete changes over a survey. Say what pattern in
the log no existing rule covers.")

(defun coach--review-prompt (n)
  "Build the review prompt from the last N log entries."
  (format "BINDINGS\n%s\n\nSUGGESTION LOG (last %d)\n%s"
          (coach-keymap-context) n (coach--log-tail n)))

(defun coach-review-quick (&optional n)
  "Review the last N log entries with gptel.  N defaults to 100."
  (interactive "P")
  (let ((n (if (numberp n) n 100)))
    (bmg/llm--request
     (coach--review-prompt n)
     :system coach--review-system
     :label "Coach review"
     :callback (lambda (response _info)
                 (bmg/llm--display-org-buffer "*coach review*" response)))))

(defun coach-review-deep (&optional n)
  "Open an agent-shell primed to review the last N log entries.
Unlike `coach-review-quick' the agent can verify a binding exists."
  (interactive "P")
  (let ((n (if (numberp n) n 200)))
    (coach--flush)
    (kill-new
     (format "Review my Emacs usage. Read %s (the last %d lines matter most) \
and ~/.config/doom/coach.el. Verify every key you suggest is really bound by \
checking config.org or running emacsclient --eval '(where-is-internal ...)'. \
Then propose at most three new detector rules for coach.el, as elisp I can paste."
             coach-log-file n))
    (call-interactively #'agent-shell-anthropic-start-claude-code)
    (message "coach: review prompt is on the kill ring -- yank it at the Claude> prompt")))

;;;; Keymap

(defvar coach-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m") #'coach-mode)
    (define-key map (kbd "c") #'coach-show-log)
    (define-key map (kbd "s") #'coach-snooze)
    (define-key map (kbd "r") #'coach-review-quick)
    (define-key map (kbd "R") #'coach-review-deep)
    (define-key map (kbd "?") #'coach-list-rules)
    map)
  "Keymap for coach commands.")

;; Doom's leader is C-c and `doom-leader-map' wins for C-c sequences, so a
;; parallel global-set-key would be dead weight.  "m" was unbound.
;; Top-level, not `with-eval-after-load': there is no `doom-keybinds' feature.
(define-key doom-leader-map (kbd "m") (cons "coach" coach-command-map))

;;;; Mode

;;;###autoload
(define-minor-mode coach-mode
  "Watch for slower-than-necessary interaction and suggest faster routes."
  :global t
  :group 'coach
  (if coach-mode
      (progn
        (add-hook 'post-command-hook #'coach--record)
        (add-hook 'kill-emacs-hook #'coach--flush)
        (setq coach--idle-timer (run-with-idle-timer coach-idle-delay t #'coach--check)
              coach--flush-timer (run-with-idle-timer 60 t #'coach--flush)))
    (remove-hook 'post-command-hook #'coach--record)
    (remove-hook 'kill-emacs-hook #'coach--flush)
    (coach--flush)
    (dolist (timer (list coach--idle-timer coach--flush-timer))
      (when (timerp timer) (cancel-timer timer)))
    (setq coach--idle-timer nil
          coach--flush-timer nil)))

(provide 'coach)
;;; coach.el ends here
