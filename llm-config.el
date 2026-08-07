;;; llm-config.el --- LLM integration and AI knowledge management -*- lexical-binding: t; -*-

;;; Commentary:

;; Everything that talks to an LLM, split out of config.org where it had grown
;; to roughly a quarter of the file.  It is a self-contained unit -- its own
;; `bmg/llm' defgroup, its own defcustoms, and a set of commands that operate on
;; the org-roam knowledge base -- so it follows the same pattern as
;; `elfeed-config.el' and `remarkable-config.el' and lives in its own file.
;;
;; Three layers:
;;   - Package setup: copilot (inline completion), gptel (via the GitHub Copilot
;;     backend, no separate API key), agent-shell (Claude via ACP).
;;   - `bmg/llm--request', a thin wrapper over `gptel-request' giving every
;;     command the same error handling and empty-response reporting.
;;   - The commands themselves, bound under SPC z a and SPC A in config.org.

;;; Code:

;; Inline code completions via GitHub Copilot
;; Primary LLM interaction is via GitHub Copilot CLI (external)
;; Doom's :tools llm module provides gptel-magit for commit messages
(use-package copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("TAB" . 'copilot-accept-completion)
              ("C-TAB" . 'copilot-accept-completion-by-word)
              ("C-<tab>" . 'copilot-accept-completion-by-word))
  :config
  (setopt copilot-indent-offset-warning-disable t))

;; Configure gptel with GitHub Copilot as the backend
;; Uses existing GitHub Copilot subscription - no separate API key needed
;; Authentication handled automatically via GitHub login
(with-eval-after-load 'gptel
  (setopt gptel-model 'claude-opus-4.5
         gptel-backend (gptel-make-gh-copilot "Copilot")))

;; Claude Agent via ACP (agent-shell + acp.el, driven by the claude-agent-acp
;; adapter). The elisp is declared in packages.el and built by straight; only
;; the claude-agent-acp/claude binaries come from Nix (dotfiles:
;; modules/profiles/client.nix). Uses the Claude subscription — run `claude`
;; once in a terminal to log in; no API key needed here.
;; Start with M-x agent-shell-anthropic-start-claude-code.
;;
;; Upstream's Doom instructions say to `require' acp and agent-shell eagerly.
;; Don't: that loads ~70 files at every startup for a command used
;; occasionally. `:commands' gets the same reachability lazily. It is still
;; needed despite straight generating autoloads, because
;; agent-shell-anthropic-start-claude-code carries no upstream autoload cookie
;; (only ~25 generic commands do). agent-shell.el requires
;; agent-shell-anthropic, so autoloading "agent-shell" defines it anyway.
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
BUDGET is counted from `point-min', not from absolute position zero: in a
narrowed buffer a plain (min (point-max) BUDGET) is an absolute position
that can fall before `point-min', which signals args-out-of-range."
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

(defun bmg/kb--search-files (question)
  "Return org files under `org-roam-directory' ranked by relevance to QUESTION.
Extracts keywords (words longer than 3 chars) from QUESTION and ranks files
by how many *distinct* keywords they contain.

One ripgrep invocation, not one per keyword: with a 1700-file vault the old
per-keyword loop blocked Emacs for a shell round-trip per word.  Passing each
keyword as its own -e pattern and printing matches with -o lets the distinct
count be recovered here instead."
  (unless (executable-find "rg")
    (user-error "rg (ripgrep) not found in PATH"))
  (let ((keywords (seq-uniq
                   (seq-filter (lambda (w) (> (length w) 3))
                               (split-string (downcase question) "[^[:alnum:]]+" t))))
        (hits (make-hash-table :test #'equal)))
    (when keywords
      (with-temp-buffer
        ;; -o prints each match on its own line so a file that matches two
        ;; different keywords is distinguishable from one that matches the
        ;; same keyword twice.  Exit status 1 just means "no matches".
        (apply #'call-process "rg" nil t nil
               "--no-heading" "--with-filename" "--no-line-number"
               "-o" "-i" "--glob" "*.org"
               (append (mapcan (lambda (kw) (list "-e" kw)) keywords)
                       (list (expand-file-name org-roam-directory))))
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            ;; rg output is FILE:MATCH; split on the last colon-free prefix.
            (when (string-match "\\`\\(.*?\\):\\(.*\\)\\'" line)
              (let ((file (match-string 1 line))
                    (match (downcase (match-string 2 line))))
                (cl-pushnew match (gethash file hits) :test #'equal))))
          (forward-line)))
      (let (ranked)
        (maphash (lambda (f ms) (push (cons f (length ms)) ranked)) hits)
        (mapcar #'car (seq-sort-by #'cdr #'> ranked))))))

(defun bmg/ask-knowledge-base (question)
  "Ask a question answered from your org-roam notes (RAG).
Searches notes, retrieves relevant content, and uses LLM to answer.
Bound to SPC s Q."
  (interactive "sQuestion: ")
  (when (string-empty-p (string-trim question))
    (user-error "Please provide a question"))
  (message "Searching knowledge base...")
  (let* ((top-files (seq-take (bmg/kb--search-files question) 5))
         (context ""))
    (if (null top-files)
        (message "No relevant notes found for: %s" question)
      ;; Build context from top matching files
      (dolist (file top-files)
        (when (and file (file-exists-p file))
          (condition-case nil
              (with-temp-buffer
                (insert-file-contents file nil 0 bmg/llm-context-small)
                (setq context (concat context
                                      "\n\n--- " (file-name-nondirectory file) " ---\n"
                                      (buffer-string))))
            (file-error nil))))  ; Skip files that can't be read
      (if (string-empty-p context)
          (message "Could not read any matching files for: %s" question)
        (bmg/llm--request
         (format "Context from knowledge base:\n%s\n\n---\n\nQuestion: %s" context question)
         :label "Knowledge base query"
         :system "You are a research assistant with access to the user's personal knowledge base.
Answer the question based ONLY on the provided context from their notes.
- Cite which notes/files support your answer
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
                                  (seq-filter #'identity top-files)
                                  ""))))))))

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
    ;; Find recently modified org-roam files
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
    ;; Count all tags
    (dolist (node nodes)
      (dolist (tag (org-roam-node-tags node))
        (puthash tag (1+ (gethash tag tag-counts 0)) tag-counts)))
    ;; Build report
    (let* ((sorted-tags (let (acc)
                          (maphash (lambda (k v) (push (cons k v) acc)) tag-counts)
                          (sort acc (lambda (a b) (> (cdr a) (cdr b))))))
           ;; Potential duplicates: same tag under different casing
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
        ;; definition and are not orphans wanting attention.  The org-roam node
        ;; list this replaced was implicitly scoped this way.
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
