;;; early-init.el --- hypermodern visuals bootstrap -*- lexical-binding: t; -*-

;; Fast, clean startup (esp. pgtk)
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6
      package-enable-at-startup nil
      frame-inhibit-implied-resize t
      inhibit-compacting-font-caches t)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message "")

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 256 1024 1024)
                  gc-cons-percentage 0.1)))

(provide 'early-init)
;;; early-init.el ends here
