;;; llm-config.el --- LLM integration and AI knowledge management -*- lexical-binding: t; -*-

;;; Commentary:

;; Everything that talks to an LLM, split out of config.org where it had grown
;; to roughly a quarter of the file.  Self-contained: its own `bmg/llm'
;; defgroup, defcustoms, and commands operating on the org-roam knowledge base
;; -- same pattern as `elfeed-config.el' and `remarkable-config.el'.
;;
;; Three layers: package setup (copilot for inline completion, gptel via the
;; GitHub Copilot backend, agent-shell for Claude via ACP); `bmg/llm--request'
;; wraps `gptel-request' for uniform error handling; the commands themselves,
;; bound under SPC z a and SPC A in config.org.

;;; Code:

;; Primary LLM interaction is via GitHub Copilot CLI (external); Doom's
;; :tools llm module provides gptel-magit for commit messages.
(use-package copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("TAB" . 'copilot-accept-completion)
              ("C-TAB" . 'copilot-accept-completion-by-word)
              ("C-<tab>" . 'copilot-accept-completion-by-word))
  :config
  (setopt copilot-indent-offset-warning-disable t))

;; Uses the existing GitHub Copilot subscription -- no separate API key;
;; authentication handled automatically via GitHub login.
(with-eval-after-load 'gptel
  (setopt gptel-model 'claude-opus-4.5
         gptel-backend (gptel-make-gh-copilot "Copilot")))

;; Claude Agent via ACP (agent-shell + acp.el, driven by the claude-agent-acp
;; adapter). Elisp declared in packages.el, built by straight; only the
;; claude-agent-acp/claude binaries come from Nix (dotfiles:
;; modules/profiles/client.nix). Uses the Claude subscription -- run `claude'
;; once in a terminal to log in, no API key needed. Start with
;; M-x agent-shell-anthropic-start-claude-code.
;;
;; Upstream's Doom instructions say to `require' acp and agent-shell eagerly.
;; Don't: that loads ~70 files at every startup for an occasional command.
;; `:commands' gets the same reachability lazily, and is still needed despite
;; straight's autoloads -- agent-shell-anthropic-start-claude-code carries no
;; upstream autoload cookie (only ~25 generic commands do). agent-shell.el
;; requires agent-shell-anthropic, so autoloading "agent-shell" defines it
;; anyway.
(use-package agent-shell
  :commands (agent-shell
             agent-shell-new-shell
             agent-shell-prompt-compose
             agent-shell-anthropic-start-claude-code)
  :config
  (setopt agent-shell-anthropic-authentication
          (agent-shell-anthropic-make-authentication :login t))
  ;; Inherit PATH/HOME so the spawned claude-agent-acp process finds `claude`,
  ;; the adapter binary, and the login credentials.
  (setopt agent-shell-anthropic-claude-environment
          (agent-shell-make-environment-variables :inherit-env t)))

;;; AI-Powered Knowledge Management Functions

(defgroup bmg/llm nil
  "Configuration for LLM-powered knowledge management."
  :group 'tools
  :prefix "bmg/llm-")

(defcustom bmg/llm-context-small 4000
  "Small context window size for quick LLM operations (e.g., tag suggestions)."
  :type 'integer
  :group 'bmg/llm)

(defcustom bmg/llm-context-medium 8000
  "Medium context window size for detailed LLM operations (e.g., summaries)."
  :type 'integer
  :group 'bmg/llm)

(defcustom bmg/llm-context-tiny 2000
  "Tiny context window size for minimal LLM operations."
  :type 'integer
  :group 'bmg/llm)

;; Retrieval budgets are deliberately separate from the buffer-head sizes above.
;; Those bound "how much of this one file do I send"; these bound an assembled
;; set of matching passages, which is far denser per character.
(defcustom bmg/llm-context-rag 12000
  "Character budget for the context assembled by `bmg/ask-knowledge-base'."
  :type 'integer
  :group 'bmg/llm)

(defcustom bmg/llm-rag-context-lines 3
  "Lines of surrounding context to keep around each retrieved match."
  :type 'integer
  :group 'bmg/llm)

(defcustom bmg/llm-rag-max-per-file 3
  "Maximum matches to take from any one file.
Passed to rga as `--max-count'.  This is the difference between a few
thousand candidate lines and tens of thousands."
  :type 'integer
  :group 'bmg/llm)

(defcustom bmg/llm-rag-max-files 12
  "How many files may contribute passages to one answer.
A broad question matches hundreds of files; spreading the budget across
all of them yields one line each, which is worse than several lines from
the dozen most relevant."
  :type 'integer
  :group 'bmg/llm)

(cl-defun bmg/llm--request (prompt &key system callback (label "LLM request"))
  "Send PROMPT to the LLM via gptel with uniform error handling.
SYSTEM is the system prompt.  CALLBACK is called as (response info)
only for a non-nil, non-empty response; nil/empty responses and
request errors are all reported as \"LABEL failed: ...\" messages."
  (condition-case err
      (gptel-request prompt
        :system system
        :callback (lambda (response info)
                    (cond
                     ((not response)
                      (message "%s failed: %s" label (plist-get info :status)))
                     ((string-empty-p (string-trim response))
                      (message "%s failed: LLM returned an empty response" label))
                     (t (funcall callback response info)))))
    (error (message "%s failed: %s" label (error-message-string err)))))

(defun bmg/llm--display-org-buffer (name &rest content)
  "Show CONTENT strings in an org-mode buffer called NAME."
  (with-current-buffer (get-buffer-create name)
    (erase-buffer)
    (apply #'insert content)
    (org-mode)
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

(defun bmg/llm--buffer-head (budget)
  "Return at most BUDGET characters from the start of the accessible region.
BUDGET is counted from `point-min': in a narrowed buffer, (min (point-max)
BUDGET) can otherwise fall before `point-min' and signal args-out-of-range."
  (buffer-substring-no-properties
   (point-min)
   (min (point-max) (+ (point-min) budget))))

(defun bmg/suggest-tags-for-buffer ()
  "Use LLM to suggest filetags for current org-roam buffer.
Copies suggested tags to kill ring for easy insertion.
Bound to SPC z S."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org buffer"))
  (let ((content (bmg/llm--buffer-head bmg/llm-context-small)))
    (when (string-empty-p (string-trim content))
      (user-error "Buffer is empty, nothing to analyze"))
    (message "Requesting tag suggestions...")
    (bmg/llm--request content
      :label "Tag suggestion"
      :system "Suggest org-mode filetags for this note. Return ONLY a single line in colon-separated format like :paper:security:tpm: with no explanation.
Focus on these categories:
- Document types: paper, website, book, meeting, project, reference
- Security domains: security, tpm, tee, sgx, trustzone, confidential_computing, attestation, secure_boot
- Attack types: exploit, side_channel, vulnerability, fuzzing
- Systems: virtualization, containers, android, linux, firmware, hardware
- Topics: cryptography, ml, networking, performance, architecture
Keep to 3-6 most relevant tags."
      :callback (lambda (response _info)
                  (let ((tags (string-trim response)))
                    (kill-new tags)
                    (message "Suggested tags: %s (copied to kill ring)" tags))))))

(defun bmg/summarize-paper ()
  "Generate AI summary for current paper note and insert at end of buffer.
Bound to SPC z a s and C-c A s."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org buffer"))
  (let ((content (bmg/llm--buffer-head bmg/llm-context-medium)))
    (when (string-empty-p (string-trim content))
      (user-error "Buffer is empty, nothing to summarize"))
    (message "Generating summary...")
    (bmg/llm--request content
      :label "Summarization"
      :system "Summarize this academic paper or research note. Provide:

1. **One-paragraph summary** - The key contribution and findings
2. **Key contributions** (3-5 bullet points)
3. **Methodology** - How they achieved their results
4. **Relevance** - How this connects to security/systems research
5. **Potential connections** - Related areas or follow-up questions

Use org-mode formatting with ** for headings."
      :callback (lambda (response info)
                  ;; Insert into the buffer the request came from,
                  ;; not whatever is current when the reply arrives.
                  (let ((buf (plist-get info :buffer)))
                    (if (not (buffer-live-p buf))
                        (message "Buffer gone, summary discarded")
                      (with-current-buffer buf
                        (save-excursion
                          (goto-char (point-max))
                          (insert "\n\n* AI Summary\n:PROPERTIES:\n:GENERATED: "
                                  (format-time-string "[%Y-%m-%d %a %H:%M]")
                                  "\n:END:\n\n" response))
                        (message "Summary inserted at end of %s" (buffer-name)))))))))

(defun bmg/process-inbox-item ()
  "Get AI suggestions for processing current GTD inbox item.
Run on a heading tagged :REFILE: for processing guidance.
Bound to localleader B in org-mode and C-c A p."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org buffer"))
  (when (org-before-first-heading-p)
    (user-error "Point must be on an inbox item"))
  ;; save-restriction, not a manual widen: save-excursion does not save
  ;; the restriction, so the old code wiped any narrowing the user had.
  (let ((content (save-restriction
                   (org-narrow-to-subtree)
                   (bmg/llm--buffer-head bmg/llm-context-medium))))
    (bmg/llm--request content
      :label "Inbox processing"
      :system "You are a GTD (Getting Things Done) assistant. Analyze this inbox item and suggest:

1. **Actionable?** - Is this actionable or reference material?
2. **Next action** - If actionable, what's the specific next physical action?
3. **Project** - Suggested project category:
   - @Project (code/engineering work)
   - @Research (academic/investigation)
   - @Reading (papers, books, articles)
   - @Training (learning, courses)
   - @Someday (future/maybe items)
4. **Tags** - 2-3 relevant org-mode tags in :tag1:tag2: format
5. **Org-roam?** - Should this become a permanent note in the knowledge base?
6. **Priority** - Suggested priority (A/B/C)

Be concise and actionable."
      :callback (lambda (response _info)
                  (bmg/llm--display-org-buffer "*Inbox Processing*"
                                               "* Processing Suggestion\n\n"
                                               response)))))

;; `bmg/kb--search-files' lived here: it ranked whole org files by keyword
;; hits, then the caller read the first 4000 bytes of each -- ranking the
;; right files but sending the wrong part of them, so it appeared to work
;; while answering from front matter.  `bmg/kb--passages' below replaces
;; both halves; keyword extraction survives as `bmg/kb--keywords'.

(defun bmg/kb--keywords (question)
  "Return the distinct search keywords in QUESTION.
Words of three characters or fewer are dropped as too common to rank on."
  (seq-uniq (seq-filter (lambda (w) (> (length w) 3))
                        (split-string (downcase question) "[^[:alnum:]]+" t))))

(defun bmg/kb--passages (question)
  "Return an alist of (FILE . PASSAGE-LINES) matching QUESTION.
Searches notes *and* the document roots, so papers and books are eligible.

Passages come from rga itself rather than being reconstructed here: `-C'
gives the surrounding lines, and for PDFs each line keeps its `Page N:'
prefix, so answers can cite a page.  `--max-count' is the load-bearing
bound; on a three-keyword query across all roots the unbounded output is
~46,000 lines against ~4,500 with it."
  (unless (executable-find "rga")
    (user-error "rga (ripgrep-all) not found in PATH"))
  (let ((keywords (bmg/kb--keywords question))
        (groups nil))
    (when keywords
      (with-temp-buffer
        ;; Exit status 1 just means "no matches"; anything else is still
        ;; readable from whatever landed in the buffer.
        (apply #'call-process "rga" nil t nil
               (append (split-string-and-unquote bmg/rga-common-args)
                       (list "-i"
                             (format "-C%d" bmg/llm-rag-context-lines)
                             (format "--max-count=%d" bmg/llm-rag-max-per-file))
                       (mapcan (lambda (kw) (list "-e" kw)) keywords)
                       (list (expand-file-name org-roam-directory))
                       (mapcar #'expand-file-name bmg/document-search-roots)))
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            ;; rga emits FILE:LINE:TEXT for matches and FILE-LINE-TEXT for
            ;; context lines; both start with the path.
            (when (string-match "\\`\\(/[^:]*?\\)[-:]\\([0-9]+\\)[-:]\\(.*\\)\\'" line)
              (let ((file (match-string 1 line))
                    (text (match-string 3 line)))
                (unless (string-empty-p (string-trim text))
                  (push text (alist-get file groups nil nil #'equal))))))
          (forward-line)))
      (mapcar (lambda (cell) (cons (car cell) (nreverse (cdr cell)))) groups))))

(defun bmg/kb--build-context (groups)
  "Assemble a bounded context string from GROUPS, an alist of (FILE . LINES).
Returns (FILES . CONTEXT).

Selects at most `bmg/llm-rag-max-files' first, ranked by how many passages
each contributed and weighted two-to-one toward notes so the distilled
material leads and papers corroborate it, then fills `bmg/llm-context-rag'
characters round-robin so no single verbose source eats the budget.
Capping files before filling is load-bearing: a broad question matches
hundreds, and spreading the budget across all of them returns one line each."
  (let* ((notes-dir (expand-file-name org-roam-directory))
         (notep (lambda (g) (string-prefix-p notes-dir (car g))))
         (rank (lambda (gs) (seq-sort-by (lambda (g) (length (cdr g))) #'> gs)))
         (notes (funcall rank (seq-filter notep groups)))
         (docs (funcall rank (seq-remove notep groups)))
         (want-notes (max 1 (/ (* 2 bmg/llm-rag-max-files) 3)))
         (chosen (append
                  (seq-take notes want-notes)
                  ;; Any note slots left unfilled fall through to documents.
                  (seq-take docs (- bmg/llm-rag-max-files
                                    (min want-notes (length notes))))))
         (budget bmg/llm-context-rag)
         (taken (make-hash-table :test #'equal))
         (used nil))
    (catch 'full
      (while (seq-some (lambda (g) (< (gethash (car g) taken 0) (length (cdr g)))) chosen)
        (dolist (g chosen)
          (let* ((file (car g))
                 (i (gethash file taken 0)))
            (when (< i (length (cdr g)))
              (let ((line (nth i (cdr g))))
                (setq budget (- budget (length line) 1))
                (when (< budget 0) (throw 'full nil))
                (puthash file (1+ i) taken)
                (cl-pushnew file used :test #'equal)))))))
    ;; nreverse is destructive: reverse once, then reuse.
    (setq used (nreverse used))
    (cons used
          (mapconcat
           (lambda (file)
             (format "\n\n--- %s ---\n%s"
                     (file-name-nondirectory file)
                     (string-join (seq-take (alist-get file groups nil nil #'equal)
                                            (gethash file taken 0))
                                  "\n")))
           used ""))))

(defun bmg/ask-knowledge-base (question)
  "Ask a question answered from your notes, papers and books (RAG).
Retrieves the passages that actually match, not the head of each file,
and answers from those.  Bound to SPC s Q."
  (interactive "sQuestion: ")
  (when (string-empty-p (string-trim question))
    (user-error "Please provide a question"))
  (message "Searching knowledge base...")
  (let ((groups (bmg/kb--passages question)))
    (if (null groups)
        (message "No relevant material found for: %s" question)
      (pcase-let ((`(,files . ,context) (bmg/kb--build-context groups)))
        (if (string-empty-p (string-trim context))
            (message "Matches found but no readable passages for: %s" question)
          (message "Answering from %d passages across %d files..."
                   (apply #'+ (mapcar (lambda (f)
                                        (length (alist-get f groups nil nil #'equal)))
                                      files))
                   (length files))
          (bmg/llm--request
           (format "Context from knowledge base:\n%s\n\n---\n\nQuestion: %s"
                   context question)
           :label "Knowledge base query"
           :system "You are a research assistant with access to the user's personal knowledge base.
The context is a set of matching passages, not whole documents, so it may start
mid-argument. Answer the question based ONLY on the provided context.
- Cite which notes/files support your answer
- Where a passage carries a `Page N:' marker, cite the page
- Quote relevant passages when helpful
- If the context doesn't contain relevant information, say so clearly
- Be concise but thorough
- Use org-mode formatting"
           :callback (lambda (response _info)
                       (bmg/llm--display-org-buffer "*KB Answer*"
                         "* Answer to: " question "\n\n" response "\n\n* Sources\n"
                         (mapconcat (lambda (f)
                                      (format "- [[file:%s][%s]]\n"
                                              f (file-name-nondirectory f)))
                                    files "")))))))))

(defun bmg/find-related-notes ()
  "Use AI to find semantically related notes to current buffer.
Analyzes current note and suggests related notes from org-roam.
Bound to SPC z R."
  (interactive)
  (require 'org-roam)
  (let* ((node-at-point (org-roam-node-at-point))
         (current-title (or (and node-at-point (org-roam-node-title node-at-point))
                            (org-get-title)
                            (buffer-name)))
         (current-tags (if node-at-point
                           (org-roam-node-tags node-at-point)
                         '()))
         (current-content (bmg/llm--buffer-head bmg/llm-context-tiny))
         (all-nodes (org-roam-node-list))
         ;; The whole DB does not fit in the prompt, so send the 100
         ;; most plausible candidates -- ranked by shared tags and
         ;; title-word overlap -- instead of whatever arbitrary order
         ;; the DB returned (which silently biased the old sample).
         (title-words (seq-filter (lambda (w) (> (length w) 3))
                                  (split-string (downcase current-title)
                                                "[^[:alnum:]]+" t)))
         (sample-nodes
          (seq-take
           (seq-sort-by
            (lambda (n)
              (+ (* 2 (length (seq-intersection (org-roam-node-tags n)
                                                current-tags #'equal)))
                 (length (seq-intersection
                          (split-string (downcase (org-roam-node-title n))
                                        "[^[:alnum:]]+" t)
                          title-words #'equal))))
            #'> all-nodes)
           100)))
    (unless all-nodes
      (user-error "No org-roam nodes found. Is org-roam database initialized?"))
    (when (string-empty-p (string-trim current-content))
      (user-error "Buffer is empty, nothing to analyze"))
    (let ((node-list (mapcar (lambda (n)
                               (format "- %s [tags: %s]"
                                       (org-roam-node-title n)
                                       (string-join (or (org-roam-node-tags n) '()) ", ")))
                             sample-nodes)))
      (message "Finding related notes among %d of %d nodes..."
               (length sample-nodes) (length all-nodes))
      (bmg/llm--request
       (format "Current note: %s
Tags: %s

Content excerpt:
%s

---

Candidate notes from the knowledge base (a relevance-ranked sample of %d out of %d):
%s

---

Which 5-10 notes are most likely related to the current note? Consider:
1. Topic similarity
2. Shared concepts or terminology
3. Research connections (same authors, citations, domains)
4. Potential for linking

For each suggested note, briefly explain WHY it might be related."
               current-title
               (string-join current-tags ", ")
               current-content
               (length sample-nodes)
               (length all-nodes)
               (string-join node-list "\n"))
       :label "Related-notes search"
       :system "You are a knowledge management assistant helping discover connections in a Zettelkasten.
Identify notes that are semantically or conceptually related, even if they don't share obvious tags.
Focus on finding non-obvious but meaningful connections."
       :callback (lambda (response _info)
                   (bmg/llm--display-org-buffer "*Related Notes*"
                                                "* Notes Related to: " current-title
                                                "\n\n" response))))))

(defun bmg/generate-weekly-review ()
  "Generate AI-powered weekly review of knowledge base activity.
Summarizes notes modified this week, identifies themes, suggests connections."
  (interactive)
  (require 'org-roam)
  (let* ((week-ago (time-subtract (current-time) (days-to-time 7)))
         (recent-files '())
         (summaries ""))
    (dolist (file (org-roam-list-files))
      (when (time-less-p week-ago (file-attribute-modification-time (file-attributes file)))
        (push file recent-files)))
    (if (null recent-files)
        (message "No notes modified in the past week")
      ;; Build summary of each file; one unreadable file (deleted but
      ;; still indexed) must not abort the whole review
      (dolist (file (seq-take recent-files 15))
        (if (not (file-readable-p file))
            (message "Skipping unreadable file: %s" file)
          (with-temp-buffer
            (insert-file-contents file nil 0 1500)
            (setq summaries (concat summaries
                                    "\n\n--- " (file-name-nondirectory file) " ---\n"
                                    (buffer-string))))))
      (message "Generating weekly review for %d notes..." (length recent-files))
      (bmg/llm--request summaries
        :label "Weekly review"
        :system "Generate a weekly review of knowledge base activity. Based on the notes modified this week:

1. **Activity Summary** - What areas received attention this week?
2. **Key Themes** - What patterns or topics emerge across the notes?
3. **Notable Insights** - Any interesting ideas or connections worth highlighting?
4. **Suggested Connections** - Notes that might benefit from being linked together
5. **Gaps Identified** - Areas that might need more exploration
6. **Recommended Focus** - Suggestions for next week's focus

Use org-mode formatting. Be concise but insightful."
        :callback (lambda (response _info)
                    (bmg/llm--display-org-buffer "*Weekly Review*"
                      (format "#+title: Weekly Review %s\n#+filetags: :review:weekly:\n\n"
                              (format-time-string "%Y-%m-%d"))
                      response
                      (format "\n\n* Files Modified This Week (%d total)\n"
                              (length recent-files))
                      (mapconcat (lambda (f)
                                   (format "- [[file:%s][%s]]\n"
                                           f (file-name-nondirectory f)))
                                 (seq-take recent-files 20)
                                 "")))))))

(defun bmg/check-tag-consistency ()
  "Scan org-roam notes and report on tag usage patterns.
Shows tag frequency, potential duplicates, and suggestions."
  (interactive)
  (require 'org-roam)
  (let ((tag-counts (make-hash-table :test 'equal))
        (nodes (org-roam-node-list)))
    (dolist (node nodes)
      (dolist (tag (org-roam-node-tags node))
        (puthash tag (1+ (gethash tag tag-counts 0)) tag-counts)))
    (let* ((sorted-tags (let (acc)
                          (maphash (lambda (k v) (push (cons k v) acc)) tag-counts)
                          (sort acc (lambda (a b) (> (cdr a) (cdr b))))))
           (dup-lines (let ((lower-tags (make-hash-table :test 'equal))
                            (lines ""))
                        (dolist (tag-count sorted-tags)
                          (let ((lower (downcase (car tag-count))))
                            (push (car tag-count) (gethash lower lower-tags))))
                        (maphash (lambda (_k v)
                                   (when (> (length v) 1)
                                     (setq lines (concat lines (format "- %s\n" (string-join v ", "))))))
                                 lower-tags)
                        lines)))
      (bmg/llm--display-org-buffer "*Tag Consistency Report*"
        "* Tag Consistency Report\n\n"
        (format "Total nodes: %d\n" (length nodes))
        (format "Unique tags: %d\n\n" (hash-table-count tag-counts))
        "** Tag Frequency\n"
        (mapconcat (lambda (tc) (format "| %s | %d |\n" (car tc) (cdr tc)))
                   sorted-tags "")
        "\n** Potential Duplicates (case variations)\n"
        dup-lines))))

(defun bmg/find-orphan-notes ()
  "Find org-roam notes with no id links in or out.
These might need attention or could be candidates for archival.

Answered from org-mem's in-memory link table rather than per-node queries.
The previous version ran one `org-roam-backlinks-get' SQLite query *and* read
one whole file per node to grep for \"[[id:\"; measured on this vault that was
1749 queries plus 1749 file reads and took 46 seconds of blocked UI."
  (interactive)
  (require 'org-mem)
  (let ((linked-to (make-hash-table :test #'equal))
        (links-out (make-hash-table :test #'equal))
        ;; Confined to `org-roam-directory' on purpose.  `org-mem-all-id-nodes'
        ;; spans everything org-mem indexes, which reaches beyond the roam dir
        ;; -- notably archive.org_archive, whose entries are archived by
        ;; definition and are not orphans wanting attention.
        (nodes (seq-filter (lambda (entry)
                             (file-in-directory-p (org-mem-entry-file entry)
                                                  org-roam-directory))
                           (org-mem-all-id-nodes))))
    (dolist (link (org-mem-links-of-type "id"))
      (when-let* ((target (org-mem-link-target link)))
        (puthash target t linked-to))
      ;; The id of the entry the link sits in -- nil for a link outside any
      ;; id'd entry, which cannot make its enclosing note non-orphan anyway.
      (when-let* ((source (org-mem-link-nearby-id link)))
        (puthash source t links-out)))
    (let ((orphans (seq-filter
                    (lambda (entry)
                      (let ((id (org-mem-entry-id entry)))
                        (and (not (gethash id linked-to))
                             (not (gethash id links-out)))))
                    nodes)))
      (bmg/llm--display-org-buffer "*Orphan Notes*"
        "* Orphan Notes (no links in or out)\n\n"
        (format "Found %d orphan notes out of %d total\n\n"
                (length orphans) (length nodes))
        (mapconcat (lambda (entry)
                     (format "- [[file:%s][%s]] [%s]\n"
                             (org-mem-entry-file entry)
                             (org-mem-entry-title entry)
                             (string-join (org-mem-entry-tags entry) ", ")))
                   orphans "")))))

(provide 'llm-config)
;;; llm-config.el ends here
