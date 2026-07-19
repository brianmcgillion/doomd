;;; remarkable-config.el --- reMarkable Paper Pro integration -*- lexical-binding: t; -*-

;;; Commentary:

;; Integration between the reMarkable Paper Pro tablet and Emacs org-mode.
;; Uses the USB Web Interface (http://10.11.99.1) -- NO developer mode required.
;;
;; Setup:
;;   1. On reMarkable: Settings -> Storage -> Enable "USB web interface"
;;   2. Connect the device via USB cable
;;   3. Test: C-c r t  (remarkable-test-connection)
;;
;; Loaded from config.org via (load! "remarkable-config.el").

;;; Code:

;;;; Core Configuration

;; Declare external variables to avoid byte-compile warnings
(defvar org-directory)
(defvar org-roam-directory)
(defvar citar-library-paths)
(defvar org-latex-classes)
(defvar org-latex-default-class)

;; Declare external functions
(declare-function org-roam-node-at-point "org-roam-node")
(declare-function org-roam-node-title "org-roam-node")
(declare-function org-roam-node-slug "org-roam-node")
(declare-function org-roam-node-read "org-roam-node")
(declare-function org-roam-node-file "org-roam-node")
(declare-function org-roam-db-update-file "org-roam-db")
(declare-function org-roam-dailies-goto-today "org-roam-dailies")
(declare-function org-latex-export-to-pdf "ox-latex")
(declare-function org-get-heading "org")
(declare-function org-narrow-to-subtree "org")
(declare-function org-noter "org-noter")

(defgroup remarkable nil
  "reMarkable tablet integration via USB web interface."
  :group 'tools
  :prefix "remarkable-")

(defcustom remarkable-url "http://10.11.99.1"
  "USB web interface URL for reMarkable tablet."
  :type 'string
  :group 'remarkable)

(defcustom remarkable-local-dir
  (expand-file-name "remarkable" org-directory)
  "Local directory for reMarkable sync."
  :type 'directory
  :group 'remarkable)

(defcustom remarkable-papers-dir
  (car citar-library-paths)
  "Directory for academic papers."
  :type 'directory
  :group 'remarkable)

(defcustom remarkable-epub-dir
  (expand-file-name "~/Documents/EPUB")
  "Directory for ebooks."
  :type 'directory
  :group 'remarkable)

;; Defer directory creation until first use (avoid startup I/O)
(defun remarkable--ensure-directories ()
  "Ensure remarkable directories exist. Called lazily on first use."
  (dolist (subdir '("downloads" "outbox" "notes"))
    (make-directory (expand-file-name subdir remarkable-local-dir) t)))

;;;; USB Web Interface Functions
(defun remarkable--curl (destination &rest args)
  "Run curl with ARGS, sending output to DESTINATION.
DESTINATION is as in `call-process': t inserts output into the
current buffer, nil discards it.  Always passes --silent and a 3s
connect timeout.  Returns non-nil when curl exits successfully."
  (unless (executable-find "curl")
    (user-error "curl not found in PATH"))
  (zerop (apply #'call-process "curl" nil destination nil
                "--silent" "--connect-timeout" "3" args)))

(defun remarkable--api-request (endpoint &optional method)
  "Make HTTP request to reMarkable USB web interface ENDPOINT.
METHOD defaults to GET."
  (let ((url (concat remarkable-url endpoint)))
    (with-temp-buffer
      (if (remarkable--curl t "--request" (or method "GET") url)
          (buffer-string)
        nil))))

(defun remarkable--device-connected-p ()
  "Check if reMarkable is connected via USB."
  (remarkable--api-request "/documents/"))

(defun remarkable--get-documents (&optional parent-id)
  "Get documents list from reMarkable, optionally from PARENT-ID folder."
  (let* ((endpoint (if parent-id
                       (format "/documents/%s" parent-id)
                     "/documents/"))
         (response (remarkable--api-request endpoint)))
    (when response
      (json-read-from-string response))))

(defun remarkable--safe-filename (name)
  "Convert NAME to a safe filename.
NAME comes from the device (VissibleName) and must never be able
to escape the target directory: every char outside [a-zA-Z0-9_-],
including dots and slashes, becomes an underscore."
  (replace-regexp-in-string "[^a-zA-Z0-9_-]" "_" name))

(defun remarkable--download-document (uuid output-file)
  "Download document UUID as PDF to OUTPUT-FILE.
Downloads to a .part file first so an interrupted transfer never
leaves a truncated PDF at OUTPUT-FILE -- the sync's file-exists-p
guard would otherwise treat it as done and never retry."
  (let ((url (format "%s/download/%s/pdf" remarkable-url uuid))
        (part (concat output-file ".part")))
    (if (remarkable--curl nil "--fail" "-o" part url)
        (progn (rename-file part output-file t) t)
      (when (file-exists-p part) (delete-file part))
      nil)))

(defun remarkable--upload-file (file)
  "Upload FILE to reMarkable via USB web interface."
  (let* ((filename (file-name-nondirectory file))
         (content-type (if (string-suffix-p ".epub" filename t)
                           "application/epub+zip"
                         "application/pdf")))
    ;; curl -F parses unquoted values up to the next ';' or ',', so a
    ;; filename like "Smith, J. - Title.pdf" breaks the unquoted form.
    ;; Quote both values; curl has no escape for a literal '"' inside.
    (when (string-match-p "\"" file)
      (user-error "Cannot upload file with a double quote in its name: %s" file))
    ;; First list root to set upload destination
    (remarkable--api-request "/documents/")
    ;; Upload file
    (remarkable--curl nil "--fail"
                      "-H" (format "Origin: %s" remarkable-url)
                      "-H" "Accept: */*"
                      "-H" (format "Referer: %s/" remarkable-url)
                      "-F" (format "file=@\"%s\";filename=\"%s\";type=%s"
                                   file filename content-type)
                      (concat remarkable-url "/upload"))))

;;;; Sync Functions
;;;###autoload
(defun remarkable-test-connection ()
  "Test connection to reMarkable USB web interface."
  (interactive)
  (if (remarkable--device-connected-p)
      (message "✓ reMarkable is connected via USB at %s" remarkable-url)
    (message "✗ Cannot reach reMarkable. Ensure USB is connected and web interface enabled.")))

;;;###autoload
(defun remarkable--sync-folder (parent-id dir path-label)
  "Download all documents under PARENT-ID into DIR, recursing into folders.
PARENT-ID nil means the device root.  PATH-LABEL is the
human-readable path prefix used in progress messages.  Returns the
number of newly downloaded documents."
  (let ((docs (append (remarkable--get-documents parent-id) nil))
        (seen (make-hash-table :test #'equal))
        (count 0))
    (make-directory dir t)
    (dolist (doc docs)
      (let* ((type (alist-get 'Type doc))
             (id (alist-get 'ID doc))
             (name (alist-get 'VissibleName doc))
             (safe (remarkable--safe-filename name))
             ;; Two docs with the same VissibleName in one folder:
             ;; disambiguate with an ID fragment, or the second one
             ;; would never be synced.
             (base (if (gethash safe seen)
                       (format "%s--%.8s" safe id)
                     safe))
             (label (if (string-empty-p path-label)
                        name
                      (concat path-label "/" name))))
        (puthash safe t seen)
        (cond
         ((string= type "DocumentType")
          (let ((output-file (expand-file-name (concat base ".pdf") dir)))
            (unless (file-exists-p output-file)
              (message "Downloading: %s..." label)
              (if (remarkable--download-document id output-file)
                  (setq count (1+ count))
                (message "Failed to download: %s" label)))))
         ((string= type "CollectionType")
          (setq count (+ count (remarkable--sync-folder
                                id (expand-file-name base dir) label)))))))
    count))

(defun remarkable-sync-from-device ()
  "Download all documents from reMarkable (with annotations pre-rendered)."
  (interactive)
  (unless (remarkable--device-connected-p)
    (user-error "reMarkable not connected. Connect via USB and enable web interface"))
  (remarkable--ensure-directories)
  (let* ((downloads-dir (expand-file-name "downloads" remarkable-local-dir))
         (count (remarkable--sync-folder nil downloads-dir "")))
    (message "Downloaded %d new documents to %s" count downloads-dir)))

;;;###autoload
(defun remarkable-sync-to-device ()
  "Upload PDFs/EPUBs from outbox to reMarkable via USB web interface."
  (interactive)
  (unless (remarkable--device-connected-p)
    (user-error "reMarkable not connected. Connect via USB and enable web interface"))
  (remarkable--ensure-directories)
  (let* ((outbox (expand-file-name "outbox" remarkable-local-dir))
         (files (directory-files outbox t "\\.\\(pdf\\|epub\\)$" t))
         (processed-dir (expand-file-name ".processed" outbox))
         (count 0))
    (if (null files)
        (message "No PDFs or EPUBs in outbox to upload")
      (make-directory processed-dir t)
      (dolist (file files)
        (message "Uploading: %s..." (file-name-nondirectory file))
        (if (remarkable--upload-file file)
            (progn
              (rename-file file (expand-file-name (file-name-nondirectory file) processed-dir) t)
              (setq count (1+ count))
              (message "Uploaded: %s" (file-name-nondirectory file)))
          (message "Failed to upload: %s" (file-name-nondirectory file))))
      (message "Uploaded %d files to reMarkable" count))))

;;;###autoload
(defun remarkable-list-documents ()
  "List documents on reMarkable device."
  (interactive)
  (unless (remarkable--device-connected-p)
    (user-error "reMarkable not connected"))
  (let ((documents (remarkable--get-documents))
        (buf (get-buffer-create "*reMarkable Documents*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "Documents on reMarkable:\n")
      (insert "========================\n\n")
      (dolist (doc (append documents nil))
        (let* ((type (alist-get 'Type doc))
               (id (alist-get 'ID doc))
               (name (alist-get 'VissibleName doc)))
          (if (string= type "CollectionType")
              (progn
                (insert (format "📁 %s/\n" name))
                (let ((folder-docs (remarkable--get-documents id)))
                  (dolist (subdoc (append folder-docs nil))
                    (insert (format "   📄 %s  [%s]\n"
                                    (alist-get 'VissibleName subdoc)
                                    (alist-get 'ID subdoc))))))
            (insert (format "📄 %s  [%s]\n" name id))))))
    (pop-to-buffer buf)
    (goto-char (point-min))))

;;;; Send Papers/EPUBs to reMarkable
;;;###autoload
(defun remarkable-send-paper ()
  "Send a paper from Papers directory to reMarkable."
  (interactive)
  (remarkable--send-file-to-device remarkable-papers-dir "Paper"))

;;;###autoload
(defun remarkable-send-epub ()
  "Send an EPUB/PDF from EPUB directory to reMarkable."
  (interactive)
  (remarkable--send-file-to-device remarkable-epub-dir "Book"))

(defun remarkable--send-file-to-device (source-dir type-name)
  "Send a file from SOURCE-DIR to reMarkable outbox.
TYPE-NAME is used in prompts (e.g., \"Paper\", \"Book\")."
  ;; The predicate must admit directories or completion hides every
  ;; subdirectory of SOURCE-DIR (they were typeable but invisible).
  (let* ((file (read-file-name (format "%s to send: " type-name) source-dir nil t nil
                               (lambda (f)
                                 (or (file-directory-p f)
                                     (string-suffix-p ".pdf" f t)
                                     (string-suffix-p ".epub" f t)))))
         (outbox (expand-file-name "outbox" remarkable-local-dir))
         (dest (expand-file-name (file-name-nondirectory file) outbox)))
    (make-directory outbox t)
    (copy-file file dest t)
    (message "Copied to outbox: %s" (file-name-nondirectory file))
    (when (y-or-n-p "Upload to reMarkable now? ")
      (remarkable-sync-to-device))))

;;;###autoload
(defun remarkable-send-current-buffer ()
  "Send current PDF or EPUB buffer to reMarkable."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Buffer is not visiting a file"))
    (unless (or (string-suffix-p ".pdf" file t)
                (string-suffix-p ".epub" file t))
      (user-error "Buffer is not a PDF or EPUB file"))
    (when (and (buffer-modified-p)
               (y-or-n-p "Buffer modified; save before sending? "))
      (save-buffer))
    (let* ((outbox (expand-file-name "outbox" remarkable-local-dir))
           (dest (expand-file-name (file-name-nondirectory file) outbox)))
      (make-directory outbox t)
      (copy-file file dest t)
      (message "Copied to outbox: %s" (file-name-nondirectory file))
      (when (y-or-n-p "Upload to reMarkable now? ")
        (remarkable-sync-to-device)))))

;;;; Export Org-Roam to reMarkable
;;;###autoload
(defun remarkable-export-roam-node ()
  "Export current org-roam node to PDF for reMarkable."
  (interactive)
  (unless (and (featurep 'org-roam) (org-roam-node-at-point))
    (user-error "Not in an org-roam node"))
  (let* ((node (org-roam-node-at-point))
         (title (org-roam-node-title node))
         (slug (org-roam-node-slug node))
         (org-latex-default-class "remarkable")
         (outbox (expand-file-name "outbox" remarkable-local-dir))
         (output-name (format "%s.pdf" slug)))
    (make-directory outbox t)
    (let ((pdf-file (org-latex-export-to-pdf)))
      (when pdf-file
        (rename-file pdf-file (expand-file-name output-name outbox) t)
        (message "Exported '%s' to outbox" title)
        (when (y-or-n-p "Upload to reMarkable now? ")
          (remarkable-sync-to-device))))))

;;;###autoload
(defun remarkable-export-subtree ()
  "Export current org subtree to PDF for reMarkable."
  (interactive)
  (let* ((title (org-get-heading t t t t))
         (slug (replace-regexp-in-string "[^a-zA-Z0-9]" "-" (downcase title)))
         (org-latex-default-class "remarkable")
         (outbox (expand-file-name "outbox" remarkable-local-dir))
         (output-name (format "%s.pdf" slug)))
    (make-directory outbox t)
    (save-restriction
      (org-narrow-to-subtree)
      (let ((pdf-file (org-latex-export-to-pdf)))
        (widen)
        (when pdf-file
          (rename-file pdf-file (expand-file-name output-name outbox) t)
          (message "Exported subtree '%s' to outbox" title)
          (when (y-or-n-p "Upload to reMarkable now? ")
            (remarkable-sync-to-device)))))))

;;;; Import Handwritten Notes to Org-Roam
(defun remarkable--list-downloaded-pdfs ()
  "List available PDFs from downloads directory."
  (let ((downloads-dir (expand-file-name "downloads" remarkable-local-dir)))
    (when (file-directory-p downloads-dir)
      (directory-files-recursively downloads-dir "\\.pdf$"))))

;;;###autoload
(defun remarkable-import-handwritten-note ()
  "Import a downloaded PDF note from reMarkable into org-roam."
  (interactive)
  (let* ((pdfs (remarkable--list-downloaded-pdfs)))
    (unless pdfs
      (user-error "No PDFs found. Run remarkable-sync-from-device first"))
    (let* ((choice (completing-read "Select PDF: " pdfs nil t))
           (title (file-name-base choice))
           (notes-dir (expand-file-name "notes" remarkable-local-dir))
           (pdf-dest (expand-file-name (file-name-nondirectory choice) notes-dir))
           (action (completing-read
                    "Action: "
                    '("Create new org-roam node"
                      "Link to existing node"
                      "Add to today's daily note")
                    nil t)))
      ;; Copy to notes directory
      (make-directory notes-dir t)
      (copy-file choice pdf-dest t)
      ;; Handle based on action
      (pcase action
        ("Create new org-roam node"
         (remarkable--create-roam-node-from-handwritten title pdf-dest))
        ("Link to existing node"
         (remarkable--link-to-existing-node title pdf-dest))
        ("Add to today's daily note"
         (remarkable--add-to-daily-note title pdf-dest))))))

(defun remarkable--handwritten-block (heading pdf-file &optional link-label)
  "Format an org heading block for an imported handwritten note.
HEADING is the headline text, PDF-FILE the note's PDF path, and
LINK-LABEL the link description.  Kept as a single-line format
string: a multi-line string would put headline asterisks at
column 0 of this file, terminating the surrounding org src block
and silently dropping it from the tangle."
  (format "\n* %s\n:PROPERTIES:\n:RM_IMPORTED: %s\n:END:\n\n[[file:%s][%s]]\n\n"
          heading
          (format-time-string "[%Y-%m-%d %a %H:%M]")
          pdf-file
          (or link-label "View handwritten notes (PDF)")))

(defun remarkable--create-roam-node-from-handwritten (title pdf-file)
  "Create a new org-roam node for handwritten note TITLE linking to PDF-FILE."
  (let* ((slug (remarkable--safe-filename title))
         (org-file (expand-file-name (format "%s.org" slug) org-roam-directory)))
    (when (file-exists-p org-file)
      (user-error "Note file already exists: %s" org-file))
    (find-file org-file)
    (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s\n#+created: %s\n#+filetags: :remarkable:handwritten:\n"
                    (org-id-new)
                    title
                    (format-time-string "[%Y-%m-%d %a]"))
            (remarkable--handwritten-block "Handwritten Notes" pdf-file)
            "* Summary / Key Points\n\n")
    (save-buffer)
    ;; org-mem-roamy-db-mode handles DB updates; no need for direct call
    (message "Created org-roam node: %s" title)))

(defun remarkable--link-to-existing-node (title pdf-file)
  "Link handwritten note PDF-FILE to an existing org-roam node."
  (let ((node (org-roam-node-read nil nil nil 'require-match)))
    (find-file (org-roam-node-file node))
    (goto-char (point-max))
    (insert (remarkable--handwritten-block
             (format "Handwritten Notes: %s :remarkable:" title) pdf-file))
    (save-buffer)
    (message "Linked to: %s" (org-roam-node-title node))))

(defun remarkable--add-to-daily-note (title pdf-file)
  "Add handwritten note PDF-FILE to today's org-roam daily note."
  (require 'org-roam-dailies)
  (org-roam-dailies-goto-today)
  (goto-char (point-max))
  (insert (remarkable--handwritten-block
           (format "%s :remarkable:" title) pdf-file "View handwritten notes"))
  (save-buffer)
  (message "Added to today's daily note"))

;;;; Open Downloaded PDFs
;;;###autoload
(defun remarkable-open-downloaded ()
  "Open a downloaded PDF from reMarkable in Emacs."
  (interactive)
  (let ((files (remarkable--list-downloaded-pdfs)))
    (if (null files)
        (user-error "No downloaded PDFs found.  Run remarkable-sync-from-device first")
      (let ((file (completing-read "PDF: " files nil t)))
        (find-file file)))))

;;;###autoload
(defun remarkable-open-in-noter ()
  "Open a downloaded PDF from reMarkable in org-noter."
  (interactive)
  (remarkable-open-downloaded)
  (org-noter))

;;;###autoload
(defun remarkable-browse-downloads ()
  "Browse downloaded PDFs directory."
  (interactive)
  (let ((downloads-dir (expand-file-name "downloads" remarkable-local-dir)))
    (make-directory downloads-dir t)
    (dired downloads-dir)))

;;;###autoload
(defun remarkable-browse-notes ()
  "Browse notes directory."
  (interactive)
  (let ((notes-dir (expand-file-name "notes" remarkable-local-dir)))
    (make-directory notes-dir t)
    (dired notes-dir)))

;;;; LaTeX Class for reMarkable
;; A5 format optimized for reMarkable's 10.3" screen
(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("remarkable"
                 "\\documentclass[11pt,a5paper]{article}
\\usepackage[margin=1.2cm]{geometry}
\\usepackage{libertine}
\\usepackage{inconsolata}
\\usepackage{parskip}
\\usepackage{graphicx}
\\usepackage{amsmath}
\\usepackage{amssymb}
\\usepackage[normalem]{ulem}
\\usepackage[colorlinks=false]{hyperref}
\\setlength{\\parindent}{0pt}
\\pagestyle{plain}
[NO-DEFAULT-PACKAGES]
[PACKAGES]
[EXTRA]"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
                 ("\\paragraph{%s}" . "\\paragraph*{%s}"))))

;;;; Keybindings
;; Define remarkable keymap for C-c r prefix
(defvar remarkable-command-map
  (let ((map (make-sparse-keymap)))
    ;; Connection
    (define-key map (kbd "t") #'remarkable-test-connection)
    (define-key map (kbd "l") #'remarkable-list-documents)
    ;; Sync
    (define-key map (kbd "s") #'remarkable-sync-from-device)
    (define-key map (kbd "u") #'remarkable-sync-to-device)
    ;; Send content
    (define-key map (kbd "p") #'remarkable-send-paper)
    (define-key map (kbd "b") #'remarkable-send-epub)
    (define-key map (kbd "c") #'remarkable-send-current-buffer)
    ;; Export from Emacs
    (define-key map (kbd "e") #'remarkable-export-roam-node)
    (define-key map (kbd "E") #'remarkable-export-subtree)
    ;; Import to Emacs
    (define-key map (kbd "i") #'remarkable-import-handwritten-note)
    ;; Open/Browse
    (define-key map (kbd "o") #'remarkable-open-downloaded)
    (define-key map (kbd "n") #'remarkable-open-in-noter)
    (define-key map (kbd "d") #'remarkable-browse-downloads)
    (define-key map (kbd "N") #'remarkable-browse-notes)
    map)
  "Keymap for reMarkable commands.")

;; Bind to leader r (C-c r / M-SPC r); the leader map wins for C-c
;; sequences, so a parallel global-set-key would be dead weight.
(define-key doom-leader-map (kbd "r") (cons "reMarkable" remarkable-command-map))

(provide 'remarkable-config)
;;; remarkable-config.el ends here
