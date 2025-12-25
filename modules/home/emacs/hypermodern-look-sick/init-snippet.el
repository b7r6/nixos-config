;; --- hypermodern look-sick (glow-up) ---
(require 'hypermodern-ui nil 'noerror)
(when (featurep 'hypermodern-ui)
  ;; default: your minimal taste, with a subtle glow layer
  (setq hypermodern/ui-theme 'base16-stylix
        hypermodern/ui-density 'tight
        hypermodern/ui-signal 'minimal
        hypermodern/ui-font-preset 'auto

        ;; glow-up defaults (still disciplined)
        hypermodern/ui-glow-level 'subtle
        hypermodern/ui-glow-halo 'auto
        hypermodern/ui-enable-pulse t
        hypermodern/ui-cursor-style nil)

  (hypermodern/ui-init)
  (global-set-key (kbd "C-c o u") #'hypermodern/ui-menu))
