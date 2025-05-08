;;; ripper.el --- major mode for .ripper files  -*- lexical-binding: t; -*-

;;; Code:

(defvar ripper-mode-syntax-table
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

    table))

(defgroup ripper nil
  "A major mode for editing .ripper files."
  :group 'languages)

(defface ripper-ordinal-face
  '((t :foreground "orange"))
  "Face used to highlight Ripper indexes."
  :group 'ripper)

(defface ripper-doxygen-key-face
  '((t :foreground "SlateGray"))
  "Face used to highlight @foo in doxygen style comments."
  :group 'ripper)

(defvar ripper-font-lock-keywords
  `((,(regexp-opt
       '("namespace"
         "enum"
         "tuple"
         "struct"
         "variant"
         "vector"
         "on"
         "idx"
         "ordered"
         "rip"
         "from"
         "key"
         "at"
         )
       'symbols)
     . font-lock-keyword-face)
    (,(regexp-opt
       '("string"
         "object"
         "array"
         "number"
         "null"
         "decimal"
         "double"
         "float"
         "s32"
         "s64"
         "u32"
         "u64"
         "bool"
         "boolean"
         "raw"
         )
       'symbols)
     . font-lock-type-face
     )
    ;; Reserved words in thirftl.ll that don't currently do anything.
    (,(regexp-opt
       '("true" "false")
       'symbols)
     . font-lock-constant-face
     )
    ))

(defvar ripper-indent-level 2
  "Indentation amount used in Ripper files.")

(defun ripper-indent-line ()
  "Indent the current line of Ripper code.
Preserves point position in the line where possible."
  (interactive)
  (let* ((point-offset (- (current-column) (current-indentation)))
         (ppss (syntax-ppss (line-beginning-position)))
         (paren-depth (nth 0 ppss))
         (current-paren-pos (nth 1 ppss))
         (text-after-paren
          (when current-paren-pos
            (save-excursion
              (goto-char current-paren-pos)
              (buffer-substring
               (1+ current-paren-pos)
               (line-end-position)))))
         (in-multiline-comment-p (nth 4 ppss))
         (current-line (buffer-substring (line-beginning-position) (line-end-position))))
    ;; If the current line is just a closing paren, unindent by one level.
    (cond
     ;; In multiline comments, ensure the leading * is indented by one
     ;; more space. For example:
     ;; /*
     ;;  * <- this line
     ;;  */
     (in-multiline-comment-p
      ;; Don't modify lines that don't start with *, to avoid changing the indentation of commented-out code.
      (when (or (string-match-p (rx bol (0+ space) "*") current-line)
                (string= "" current-line))
        (indent-line-to (1+ (* ripper-indent-level paren-depth)))))
     ;; Indent 'throws' lines by one extra level. For example:
     ;; void foo ()
     ;;   throws (1: FooError fe)
     ((string-match-p (rx bol (0+ space) "throws" symbol-end) current-line)
      (indent-line-to (* ripper-indent-level (1+ paren-depth))))
     ;; Indent according to the last paren position, if there is text
     ;; after the paren. For example:
     ;; throws (1: FooError fe,
     ;;         2: BarError be, <- this line
     ((and
       text-after-paren
       (not (string-match-p (rx bol (0+ space) eol) text-after-paren)))
      (let (open-paren-column)
        (save-excursion
          (goto-char current-paren-pos)
          (setq open-paren-column (current-column)))
        (indent-line-to (1+ open-paren-column))))
     ;; Indent according to the amount of nesting.
     (t
      (indent-line-to (* ripper-indent-level paren-depth))))

    ;; Point is now at the beginning of indentation, restore it
    ;; to its original position (relative to indentation).
    (when (>= point-offset 0)
      (move-to-column (+ (current-indentation) point-offset)))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.ripper$" . ripper-mode))

;;;###autoload
(define-derived-mode ripper-mode prog-mode "Ripper"
  "Major mode for editing Ripper files."
  (setq-local font-lock-defaults '(ripper-font-lock-keywords))
  (setq-local indent-line-function 'ripper-indent-line)

  (setq-local comment-start "// "))

(provide 'ripper)
;;; ripper.el ends here
