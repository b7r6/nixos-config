;;; early-init.el --- hypermodern visuals bootstrap -*- lexical-binding: t; -*-

;; Keep collection bounded even if init fails or this file is reloaded after
;; startup. File-name handlers remain installed throughout initialization.
(setq gc-cons-threshold (* 256 1024 1024)
      gc-cons-percentage 0.1
      frame-inhibit-implied-resize t
      inhibit-compacting-font-caches t)

;; Enable package.el for Nix-provided packages (autoloads)
;; Vanilla Emacs bootstraps straight.el in init.el.
(setq package-enable-at-startup t)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message "")

(provide 'early-init)
;;; early-init.el ends here
