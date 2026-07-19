;;; elfeed-config.el -*- lexical-binding: t; -*-

(defvar bmg/elfeed-update-timer nil
  "Repeating timer for background elfeed updates.")

(with-eval-after-load 'elfeed
  ;; Background refresh once a day.  Deliberately NOT on
  ;; elfeed-search-mode-hook (that fired a full network fetch every
  ;; time the search buffer was entered) and not at load time (a nil
  ;; first arg to run-at-time fires immediately).  Manual refresh
  ;; stays on `r'.  Cancel-before-set keeps re-evals from stacking
  ;; timers.
  (when (timerp bmg/elfeed-update-timer)
    (cancel-timer bmg/elfeed-update-timer))
  (setq bmg/elfeed-update-timer
        (run-at-time (* 24 60 60) (* 24 60 60) #'elfeed-update-background))

  (defun concatenate-authors (authors-list)
    "Given AUTHORS-LIST, list of plists; return string of all authors
  concatenated."
    (mapconcat
     (lambda (author) (plist-get author :name))
     authors-list ", "))

  (defun bmg/my-search-print-fn (entry)
    "Print ENTRY to the buffer."
    (let* ((date (elfeed-search-format-date (elfeed-entry-date entry)))
           (title (or (elfeed-meta entry :title)
                      (elfeed-entry-title entry) ""))
           (title-faces (elfeed-search--faces (elfeed-entry-tags entry)))
           (feed (elfeed-entry-feed entry))
           (feed-title
            (when feed
              (or (elfeed-meta feed :title) (elfeed-feed-title feed))))
           (entry-authors (concatenate-authors
                           (elfeed-meta entry :authors)))
           (title-width (- (window-width) 10
                           elfeed-search-trailing-width))
           (title-column (elfeed-format-column
                          title (elfeed-clamp
                                 elfeed-search-title-min-width
                                 title-width
                                 elfeed-search-title-max-width)
                          :left))
           (authors-width 135)
           (authors-column (elfeed-format-column
                            entry-authors authors-width :left))
           (entry-score (elfeed-format-column (number-to-string (elfeed-score-scoring-get-score-from-entry entry)) 15 :right)))

      (insert (propertize date 'face 'elfeed-search-date-face) " ")
      (insert (propertize title-column
                          'face title-faces 'kbd-help title) " ")
      (insert (propertize authors-column
                          'face 'elfeed-search-date-face
                          'kbd-help entry-authors) " ")
      ;; Guard the value actually being inserted: entry-authors is
      ;; always a string (mapconcat returns "" for no authors), but
      ;; feed-title is nil for entries with no feed object, and one
      ;; (propertize nil ...) aborts rendering of the whole buffer.
      (when (and feed-title (not (string-empty-p feed-title)))
        (insert (propertize feed-title
                            'face 'elfeed-search-feed-face) " "))
      (insert entry-score " ")))

  (defun bmg/elfeed-show-refresh--better-style ()
    "Update the buffer to match the selected entry, using a mail-style."
    (interactive)
    (let* ((inhibit-read-only t)
           (title (elfeed-entry-title elfeed-show-entry))
           (date (seconds-to-time (elfeed-entry-date elfeed-show-entry)))
           ;; elfeed only stores the plural :authors key, as a list of
           ;; plists -- the singular :author was always nil here, so
           ;; the header never rendered.
           (author (concatenate-authors (elfeed-meta elfeed-show-entry :authors)))
           (tags (elfeed-entry-tags elfeed-show-entry))
           (tagsstr (mapconcat #'symbol-name tags ", "))
           (nicedate (format-time-string "%a, %e %b %Y %T %Z" date))
           (content (elfeed-deref (elfeed-entry-content elfeed-show-entry)))
           (type (elfeed-entry-content-type elfeed-show-entry))
           (feed (elfeed-entry-feed elfeed-show-entry))
           (base (and feed (elfeed-compute-base (elfeed-feed-url feed)))))
      (erase-buffer)
      (insert "\n")
      (insert (format "%s\n\n" (propertize title 'face 'elfeed-show-title-face)))
      (when (and (not (string-empty-p author)) elfeed-show-author)
        (insert (format "%s\n" (propertize author 'face 'elfeed-show-author-face))))
      (insert (format "%s\n\n" (propertize nicedate 'face 'elfeed-log-date-face)))
      (when tags
        (insert (format "%s\n"
                        (propertize tagsstr 'face 'elfeed-search-tag-face))))
      (cl-loop for enclosure in (elfeed-entry-enclosures elfeed-show-entry)
               do (insert (propertize "Enclosure: " 'face 'message-header-name))
               do (elfeed-insert-link (car enclosure))
               do (insert "\n"))
      (insert "\n")
      (if content
          (if (eq type 'html)
              (elfeed-insert-html content base)
            (insert content))
        (insert (propertize "(empty)\n" 'face 'italic)))
      (goto-char (point-min))))

  (defun bmg/elfeed-get-ai-tags-for-abstract (abstract callback)
    "Use AI to suggest tags for paper ABSTRACT, call CALLBACK with result."
    (require 'gptel)
    (gptel-request abstract
      :system "Suggest org-mode filetags for this paper abstract. Return ONLY a single line in colon-separated format like :paper:security:tpm: with no explanation.
Focus on these categories:
- Document type: paper
- Security domains: security, tpm, tee, sgx, trustzone, confidential_computing, attestation, secure_boot
- Attack types: exploit, side_channel, vulnerability, fuzzing
- Systems: virtualization, containers, android, linux, firmware, hardware
- Topics: cryptography, ml, networking, performance, architecture
Keep to 3-5 most relevant tags. Always include :paper: tag."
      :callback callback))

  (defun bmg/elfeed--create-arxiv-note (title cite-key link authors abstract)
    "Create an org-roam reference note under refs/ for an arXiv paper.
Returns the note's file name.  All feed-derived text (TITLE,
AUTHORS, ABSTRACT, LINK) is inserted literally; none of it passes
through org-capture template expansion, so %-escapes or %(elisp)
in a feed can never be interpreted."
    (let* ((slug (replace-regexp-in-string "[^a-zA-Z0-9_-]+" "_" (downcase title)))
           (dir (expand-file-name "refs" org-roam-directory))
           (file (expand-file-name (concat slug ".org") dir)))
      (make-directory dir t)
      (if (file-exists-p file)
          (message "Note already exists: %s" file)
        (with-current-buffer (find-file-noselect file)
          (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n"
                  "#+title: " title "\n"
                  "#+created: " (format-time-string "[%Y-%m-%d %a]") "\n"
                  (if cite-key (concat "#+roam_refs: @" cite-key "\n") "")
                  "#+filetags: :arxiv:paper:reference:\n\n"
                  "- Source :: " link "\n"
                  "- Authors :: " authors "\n\n"
                  "* Abstract\n\n" (or abstract "") "\n\n"
                  "* Notes\n\n")
          (save-buffer)))
      file))

  (defun bmg/elfeed-arxiv-intake ()
    "Full arXiv intake from the current elfeed entry.
Fetches the PDF into the citar library, appends a BibTeX entry,
queues a TODO in papers.org (deduped), creates an org-roam
reference note under refs/, and asks the LLM for tag suggestions.
Unifies the previous separate `C' (roam note only) and `a'
(PDF+BibTeX only) workflows.

Based on https://gist.github.com/rka97/57779810d3664f41b0ed68a855fcab54"
    (interactive)
    (unless (bound-and-true-p elfeed-show-entry)
      (user-error "Not in an elfeed entry buffer"))
    (let* ((entry elfeed-show-entry)
           (link (elfeed-entry-link entry))
           (title (elfeed-entry-title entry))
           (authors (concatenate-authors (elfeed-meta entry :authors)))
           (abstract (elfeed-deref (elfeed-entry-content entry)))
           (arxiv-id (and (string-match "arxiv\\.org/abs/\\([0-9]+\\.[0-9]+\\)" link)
                          (match-string 1 link)))
           cite-key)
      (unless arxiv-id
        (user-error "Not an arXiv entry (URL: %s)" link))
      (message "Fetching arXiv:%s ..." arxiv-id)
      (condition-case err
          (arxiv-get-pdf-add-bibtex-entry arxiv-id (car citar-bibliography)
                                          (nth 0 citar-library-paths))
        (error (user-error "arXiv fetch failed for %s: %s"
                           arxiv-id (error-message-string err))))
      ;; Key of the entry just appended to the bib file
      (save-window-excursion
        (find-file (car citar-bibliography))
        (goto-char (point-max))
        (bibtex-beginning-of-entry)
        (setq cite-key (cdr (assoc "=key=" (bibtex-parse-entry)))))
      ;; Reading list TODO (deduped)
      (let ((papers-file (expand-file-name "papers.org" org-roam-directory)))
        (save-window-excursion
          (find-file papers-file)
          (goto-char (point-min))
          (if (search-forward (format "[cite:@%s]" cite-key) nil t)
              (message "Paper already in reading list: %s" title)
            (goto-char (point-max))
            (insert (format "\n** TODO Read paper [cite:@%s] %s" cite-key title))
            (save-buffer)
            (message "Added to reading list: %s" title))))
      ;; Reference note (literal insertion, no template expansion)
      (bmg/elfeed--create-arxiv-note title cite-key link authors abstract)
      ;; AI-suggested tags, asynchronously
      (when abstract
        (bmg/elfeed-get-ai-tags-for-abstract
         abstract
         (lambda (response _info)
           (when response
             (let ((tags (string-trim response)))
               (message "AI suggested tags: %s (copied to kill ring)" tags)
               (kill-new tags))))))))
  (map! (:after elfeed
                (:map elfeed-show-mode-map
                 :desc "arXiv intake: PDF + BibTeX + roam note" "a" #'bmg/elfeed-arxiv-intake)))
  (setq elfeed-search-print-entry-function #'bmg/my-search-print-fn)
  (setq elfeed-show-refresh-function #'bmg/elfeed-show-refresh--better-style)
  (setq elfeed-search-date-format '("%y-%m-%d" 10 :center))
  (setq elfeed-search-title-max-width 110))

;;; END elfeed

;; Try to add a weighting to the elfeeds
(use-package elfeed-score
  :after elfeed
  :config
  (setq elfeed-score-serde-score-file (concat org-directory "elfeed.score"))
  (elfeed-score-enable)
  ;; Auto-sort by score (highest first)
  (setq elfeed-search-sort-function #'elfeed-score-sort)
  ;; Upstream-recommended binding; deliberately shadows
  ;; elfeed-search-set-feed-title (still reachable via M-x).
  (define-key elfeed-search-mode-map "=" elfeed-score-map))

(use-package org-ref
  :after org
  :config
  (defun bmg/reformat-bib-library (&optional filename)
    "Format the bibliography FILENAME using rebiber, then sed fixups.
Defaults to the main citar bibliography; with a prefix argument,
prompt for the file."
    (interactive (list (when current-prefix-arg
                         (read-file-name "Bib file: "))))
    (unless (executable-find "rebiber")
      (user-error "rebiber not found in PATH"))
    ;; expand-file-name BEFORE shell-quote-argument: quoting a raw
    ;; "~/..." path would defeat tilde expansion in the shell command.
    (let ((file (shell-quote-argument
                 (expand-file-name (or filename (car citar-bibliography))))))
      (async-shell-command
       (concat
        ;; Get conference versions of arXiv papers
        (format "rebiber -i %s && " file)
        ;;(format "biber --tool --output_align --output_indent=2 --output_fieldcase=lower --configfile=~/bib-lib/biber-myconf.conf --output_file=%s %s && " file file) ; Properly format the bibliography
        ;; Some replacements
        (format "sed -i -e 's/arxiv/arXiv/gI' -e 's/journaltitle/journal     /' -e 's/date      /year      /' %s" file)))))
  (defun bmg/reformat-bib-lib-hook ()
    "Reformat the main bib library whenever it is saved.
Compares truenames -- citar-bibliography is usually an
unexpanded ~/ path that `equal' against `buffer-file-name'
would never match.  Silently skips when rebiber is missing."
    (when (and buffer-file-name
               (equal (file-truename buffer-file-name)
                      (file-truename (car citar-bibliography)))
               (executable-find "rebiber"))
      (bmg/reformat-bib-library)))
  (add-hook 'after-save-hook 'bmg/reformat-bib-lib-hook)
  (setq bibtex-dialect 'biblatex))
