;;; smart-split -- Summary
;;; Commentary:

;;; Code:
(defgroup smart-split nil
  "Splits Frame into Windows For Coumns of Minimum Size"
  :group 'extensions
  :group 'convenience
  :version "1.0.0")

(defcustom smart-split-columns 100
  "Minimum Columns per Split"
  :type 'number
  :group 'lusty-explorer)

(defun smart-split--ordered-window-list ()
  "Get the list of windows in the selected frame, starting from the one at the top left."
  (window-list (selected-frame) 'no-minibuf (frame-first-window)))

(defun smart-split--resize-windows-destructively (windows)
  (when windows
    (condition-case nil
        (progn
          (adjust-window-trailing-edge
           (first windows)
           (- smart-split--columns (window-body-width (first windows))) t)
          (smart-split--resize-windows-destructively (cdr windows)))
      (error
       (if (cdr windows)
           (progn
             (delete-window (cadr windows))
             (smart-split--resize-windows-destructively (cons (car windows)
							                                                (cddr windows))))
         (ignore-errors (delete-window (car windows))))))))

(defun smart-split--subsplit (w)
  (when (> (window-body-width w) (* 2 (+ 1 smart-split--columns)))
    (let ((w2 (split-window w (+ 2 smart-split--columns) 'right)))
      (save-excursion
        (smart-split--subsplit w2)))))

(defun smart-split ()
  "Split the frame into exactly as many sub-windows as possible."
  (interactive)

  (setq smart-split--columns smart-split-columns)

  (smart-split--resize-windows-destructively
   (smart-split--ordered-window-list))

  (walk-windows 'smart-split--subsplit)
  (balance-windows)

  ;; Switch each window to a new blank buffer
  (walk-windows
   (lambda (w)
     (with-selected-window w
       (switch-to-buffer (generate-new-buffer " *blank*"))))))

(provide 'smart-split)
;;; smart-split.el ends here
