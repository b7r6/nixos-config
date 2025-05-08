;;; machine-mode.el --- major mode for .machine files  -*- lexical-binding: t; -*-

;;; Code:

(defvar machine-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Both " and ' are strings.
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?' "\"" table)

    ;; Comments can start with //, /* or # characters.
    (modify-syntax-entry ?/ ". 124" table)
    (modify-syntax-entry ?* ". 23b" table)
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)
    table)
  )

(defgroup machine-mode nil
  "A major mode for editing `.machine` files."
  :group 'languages)

(defcustom machine-mode-indent-level 2
  "Indentation amount used in `.machine` files."
  :type 'integer
  :group 'machine-mode
  :safe #'integerp
  )

(defface machine-mode-operator-face
  '((t :inherit font-lock-builtin-face))
  "Face used to highlight `.machine` operators."
  :group 'machine-mode)

(defface machine-mode-modifier-face
  '((t :inherit font-lock-keyword-face))
  "Face used to highlight `.machine` modifiers."
  :group 'machine-mode)

(defface machine-mode-keyword-face
  '((t :inherit font-lock-keyword-face))
  "Face used to highlight `.machine` keywords."
  :group 'machine-mode)

(defface machine-mode-type-face
  '((t :inherit font-lock-type-face))
  "Face used to highlight `.machine` types."
  :group 'machine-mode)

(defface machine-mode-native-face
  '((t :inherit font-lock-constant-face))
  "Face used to highlight `.machine` native references."
  :group 'machine-mode)

(defface machine-mode-state-or-event-face
  '((t :inherit font-lock-function-name-face))
  "Face used to highlight `.machine` states."
  :group 'machine-mode)

(defcustom machine-mode-operators
  '(
    "->"
    "=>"
    "otherwise"
    )
  "`.machine` Operators"
  :type 'list
  :group 'machine-mode
  :safe #'listp
  )

(defcustom machine-mode-modifiers
  '(
    "start"
    "emit"
    "invoke"
    "send"
    )
  "`.machine` Modifiers"
  :type 'list
  :group 'machine-mode
  :safe #'listp
  )

(defcustom machine-mode-keywords
  '(
    "native"
    "with"
    "on"
    "transition"
    "when"
    "via"
    )
  "`.machine` Keywords"
  :type 'list
  :group 'machine-mode
  :safe #'listp
  )

(defcustom machine-mode-types
  '(
    "include"
    "namespace"
    "machine"
    "state"
    "event"
    "action"
    "guard"
    "generator"
    )
  "`.machine` Keywords"
  :type 'list
  :group 'machine-mode
  :safe #'listp
  )

(defvar machine-mode-font-lock-keywords
  (append
   `(
     (,(rx "`" (one-or-more
		(or
		 (any "A-Z")
		 (any "a-z")
		 (any "0-9")
		 "_"
		 "::"
		 "<"
		 ">"))
	   "`")
      . 'machine-mode-native-face)

     (,(rx (one-or-more (any "A-Z")) (0+ "_") (one-or-more (any "A-Z")))
      . 'machine-mode-state-or-event-face)

     ;; operators
     (,(regexp-opt machine-mode-operators 'symbols)
      . 'machine-mode-operator-face)

     (,(rx " :: ") . 'machine-mode-operator-face)
     (,(rx " : ") . 'machine-mode-operator-face)
     (,(rx " . ") . 'machine-mode-operator-face)

     ;; modifiers
     (,(regexp-opt machine-mode-modifiers 'symbols)
      . 'machine-mode-modifier-face)

     ;; keywords
     (,(regexp-opt machine-mode-keywords 'symbols)
      . 'machine-mode-keyword-face)

     ;; types
     (,(regexp-opt machine-mode-types 'symbols)
      . 'machine-mode-type-face)

     ;; states and events
     ;; (,(rx space (one-or-more (any "A-Z")))
     ;;  . 'machine-mode-state-or-event-face)
     )
   ))

(defun machine-indent-line ()
  "Indent the current line of Machine code."
  (interactive)

  (let* ((point-offset (- (current-column) (current-indentation)))
         (ppss (syntax-ppss (line-beginning-position)))
         (paren-depth (nth 0 ppss))
         (current-paren-pos (nth 1 ppss))

         (current-line
	  (buffer-substring (line-beginning-position) (line-end-position)))

	 (closing-delimeter-p
	  (or
	   (string-match-p (rx bol (0+ space) "}") current-line)
	   (string-match-p (rx bol (0+ space) "]") current-line)
	   (string-match-p (rx bol (0+ space) ")") current-line)
	   (string-match-p (rx bol (0+ space) ">") current-line)
	   ))
	 )

    (cond
     (closing-delimeter-p
      (indent-line-to (* machine-mode-indent-level (1- paren-depth))))

     (t
      (indent-line-to (* machine-mode-indent-level paren-depth)))
     )
    ))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.machine$" . machine-mode))

;;;###autoload
(define-derived-mode machine-mode prog-mode "machine"
  "Major mode for editing `.machine` files."
  (setq-local font-lock-defaults '(machine-mode-font-lock-keywords))
  (setq-local indent-line-function 'machine-indent-line)
  (setq-local comment-start "// ")
  )

(provide 'machine-mode)
;;; machine-mode.el ends here
