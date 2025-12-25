;; --- hypermodern look-sick (glow-up) ---
(require 'hypermodern-ui nil 'noerror)
(when (featurep 'hypermodern-ui)
  ;; default: your minimal taste, with a subtle glow layer
  (setq hypermodern/ui-theme 'base16-ono-sendai-blue-tuned
        hypermodern/ui-density 'tight
        hypermodern/ui-signal 'minimal
        hypermodern/ui-font-preset 'auto

        ;; glow-up defaults (still disciplined)
        hypermodern/ui-glow-level 'subtle
        hypermodern/ui-glow-halo 'auto
        hypermodern/ui-enable-pulse t
        hypermodern/ui-cursor-style nil)

  ;; Try to ensure the theme is available before initializing
  (ignore-errors (require 'base16-ono-sendai-blue-tuned-theme))
  (hypermodern/ui-init)
  (global-set-key (kbd "C-c o u") #'hypermodern/ui-menu))
