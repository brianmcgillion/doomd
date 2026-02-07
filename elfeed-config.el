;;; elfeed-congig.el -*- lexical-binding: t; -*-

(after! elfeed
  ;; update elfeed when opened or at least every 24 hours
  (add-hook! 'elfeed-search-mode-hook 'elfeed-update)
  (run-at-time nil (* 24 60 60) #'elfeed-update)

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
           (tags (mapcar #'symbol-name (elfeed-entry-tags entry)))
           (tags-str (mapconcat
                      (lambda (s) (propertize s 'face
                                              'elfeed-search-tag-face))
                      tags ","))
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
                            entry-authors (elfeed-clamp
                                           elfeed-search-title-min-width
                                           authors-width
                                           131)
                            :left))
           (entry-score (elfeed-format-column (number-to-string (elfeed-score-scoring-get-score-from-entry entry)) 15 :right)))

      (insert (propertize date 'face 'elfeed-search-date-face) " ")
      (insert (propertize title-column
                          'face title-faces 'kbd-help title) " ")
      (insert (propertize authors-column
                          'face 'elfeed-search-date-face
                          'kbd-help entry-authors) " ")
      (when entry-authors
        (insert (propertize feed-title
                            'face 'elfeed-search-feed-face) " "))
      (insert entry-score " ")))

  (defun bmg/elfeed-show-refresh--better-style ()
    "Update the buffer to match the selected entry, using a mail-style."
    (interactive)
    (let* ((inhibit-read-only t)
           (title (elfeed-entry-title elfeed-show-entry))
           (date (seconds-to-time (elfeed-entry-date elfeed-show-entry)))
           (author (elfeed-meta elfeed-show-entry :author))
           (link (elfeed-entry-link elfeed-show-entry))
           (tags (elfeed-entry-tags elfeed-show-entry))
           (tagsstr (mapconcat #'symbol-name tags ", "))
           (nicedate (format-time-string "%a, %e %b %Y %T %Z" date))
           (content (elfeed-deref (elfeed-entry-content elfeed-show-entry)))
           (type (elfeed-entry-content-type elfeed-show-entry))
           (feed (elfeed-entry-feed elfeed-show-entry))
           (feed-title (elfeed-feed-title feed))
           (base (and feed (elfeed-compute-base (elfeed-feed-url feed)))))
      (erase-buffer)
      (insert "\n")
      (insert (format "%s\n\n" (propertize title 'face 'elfeed-show-title-face)))
      (when (and author elfeed-show-entry-author)
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

  (defun bmg/elfeed-entry-to-arxiv ()
    "Fetch an arXiv paper into the local library from the current elfeed entry.

  This is a customized version from the one in https://gist.github.com/rka97/57779810d3664f41b0ed68a855fcab54
  New features to this version:

  - Update the bib entry with the pdf file location
  - Add a TODO entry in my papers.org to read the paper
  "
    (interactive)
    (let* ((link (elfeed-entry-link elfeed-show-entry))
           (match-idx (string-match "arxiv.org/abs/\\([0-9.]*\\)" link))
           (matched-arxiv-number (match-string 1 link))
           (last-arxiv-key "")
           (last-arxiv-title ""))
      (when matched-arxiv-number
        (message "Going to arXiv: %s" matched-arxiv-number)
        (arxiv-get-pdf-add-bibtex-entry matched-arxiv-number citar-bibliography (nth 0 citar-library-paths))
        ;; Now, we are updating the reading list
        (message "Update reading list")
        (save-window-excursion
          ;; Get the bib file
          (find-file citar-bibliography)
          ;; get to last line
          (goto-char (point-max))
          ;; get to the first line of bibtex
          (bibtex-beginning-of-entry)
          (let* ((entry (bibtex-parse-entry))
                 (key (cdr (assoc "=key=" entry)))
                 (title (bibtex-completion-apa-get-value "title" entry)))
            (message (concat "checking for key: " key))
            (setq last-arxiv-key key)
            (setq last-arxiv-title title)))
        ;; (message (concat "outside of save window, key: " last-arxiv-key))
        ;; Add a TODO entry with the cite key and title
        ;; This is a bit hacky solution as I don't know how to add the org entry programmatically
        (save-window-excursion
          (find-file (concat org-roam-directory "papers.org"))
          (goto-char (point-max))
          (insert (format "** TODO Read paper [cite:@%s] %s" last-arxiv-key last-arxiv-title))
          (save-buffer)
          )
        )
      )
    )
  (map! (:after elfeed
                (:map elfeed-show-mode-map
                 :desc "Fetch arXiv paper to the local library" "a" #'bmg/elfeed-entry-to-arxiv)))
  (setq! elfeed-search-print-entry-function #'bmg/my-search-print-fn)
  (setq! elfeed-show-refresh-function #'bmg/elfeed-show-refresh--better-style)
  (setq! elfeed-search-date-format '("%y-%m-%d" 10 :center))
  (setq! elfeed-search-title-max-width 110))

;;; END elfeed

;; Try to add a weighting to the elfeeds
(use-package! elfeed-score
  :after elfeed
  :config
  (setq elfeed-score-serde-score-file (concat org-directory "elfeed.score"))
  (elfeed-score-enable)
  ;; Auto-sort by score (highest first)
  (setq elfeed-search-sort-function #'elfeed-score-sort)
  (define-key elfeed-search-mode-map "=" elfeed-score-map))

(use-package! org-ref
  :after org
  :config
  (defun bmg/reformat-bib-library (&optional filename)
    "Formats the bibliography using biber & rebiber and updates the PDF -metadata."
    (interactive "P")
    (or filename (setq filename citar-bibliography))
    (let ((cmnd (concat
                 (format "rebiber -i %s &&" filename) ; Get converence versions of arXiv papers
                 ;;(format "biber --tool --output_align --output_indent=2 --output_fieldcase=lower --configfile=~/bib-lib/biber-myconf.conf --output_file=%s %s && " filename filename) ; Properly format the bibliography
                 (format "sed -i -e 's/arxiv/arXiv/gI' -e 's/journaltitle/journal     /' -e 's/date      /year      /' %s &&" filename) ; Some replacements
                 )))
      (async-shell-command cmnd)))
  (defun bmg/reformat-bib-lib-hook ()
    "Reformat the main bib library whenever it is saved.."
    (when (equal (buffer-file-name) citar-bibliography) (bmg/reformat-bib-library)))
  (add-hook 'after-save-hook 'bmg/reformat-bib-lib-hook)
  (setq bibtex-dialect 'biblatex))
