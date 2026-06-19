# hypermodern — look sick (glow-up edition)

This is an aesthetics layer that fits your existing config.

## What you get

- Minimal default, but a *universe* of curated variations:
  - Ono-Sendai palette family (memphis/chiba/razorgirl/sprawl/github/tuned/spectrum…)
  - density presets (tight/normal/comfy/cinema)
  - signal presets (minimal/normal/loud)
  - glow presets (off/subtle/neon)
  - font presets (auto/berkeley/iosevka/jetbrains/system)
  - optional toggles: pulse glow, writing mode, transparency, dim inactive windows, solaire,
    ligatures

## The glow (what “glow me up” means here)

Subtle by default, cyber when you ask:

- **Frame halo**: internal border is tinted from your current theme’s accent.
- **Cursor glow**: cursor color follows the theme accent (without turning into a flashlight).
- **Holo-parens**: show-paren match gets a glassy accent background.
- **Pulse glow**: jumping around pulses the current line (feels *intentional*).

Everything is guarded — if a face/feature doesn’t exist in your build, it just skips.

## Emacs: install

### 1) Put `lib/hypermodern-ui.el` somewhere on your `load-path`

If you use the included `default.nix`, it auto-loads all `./lib/*.el`.

### 2) In your init.el:

```elisp
(require 'hypermodern-ui nil 'noerror)
(when (featurep 'hypermodern-ui)
  (hypermodern/ui-init)
  ;; open the control room
  (global-set-key (kbd "C-c o u") #'hypermodern/ui-menu))
```

If you use `general` + your `hypermodern/leader`, bind it like:

```elisp
(with-eval-after-load 'general
  (when (fboundp 'hypermodern/leader)
    (hypermodern/leader "u" #'hypermodern/ui-menu)))
```

## Usage

- `M-x hypermodern/ui-menu` — the control room (uses transient if installed)
- `M-x hypermodern/ui-style` — pick a full preset (theme+density+signal+glow+extras)
- `M-x hypermodern/ui-theme` — theme picker (curated + installed themes only)
- `M-x hypermodern/ui-glow` — set glow intensity
- `M-x hypermodern/ui-toggle-glow` — cycle glow (off→subtle→neon)
- `M-x hypermodern/ui-save` — persist your choices to your `custom-file`

## Nix: theme universe

`default.nix` builds Emacs themes from `ono-sendai-blue.nix` palettes so you can switch themes
instantly at runtime without rebuilding your OS theme.

Themes show up as:

- `base16-ono-sendai-memphis`
- `base16-ono-sendai-chiba`
- `base16-ono-sendai-razorgirl`
- `base16-ono-sendai-sprawl`
- `base16-ono-sendai-github`
- `base16-ono-sendai-tuned`
- `base16-ono-sendai-spectrum`
- `base16-ono-sendai-untuned`

Then in Emacs: `M-x hypermodern/ui-theme`.

## Notes

- Everything is guarded: missing optional packages won’t break startup.
- Default stays quiet: no rainbow confetti unless you ask for it.
- Pulse is gated by a command list (`hypermodern/ui-pulse-commands`). Add/remove freely.
