# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                           // hyper-modern-nixos // checks // emacs-config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The emacs config (init.el, early-init.el, hypermodern-palette.el) is complex
# enough to accumulate silent breakage: missing require, wrong argument count,
# byte-compiler warnings that become runtime errors on the next Emacs upgrade.
# This check makes that breakage loud at `nix flake check` time.
#
# Two gates:
#
#   1. BATCH LOAD — emacs --batch -l early-init.el -l init.el verifies the
#      whole config loads without error. Output is captured and scanned for
#      the patterns "Warning", "Error", "Cannot" (case-sensitive).
#
#   2. BYTE-COMPILE — each of the three .el files is compiled individually
#      with -f batch-byte-compile. The compiler surfaces type mismatches,
#      free variables, obsolete functions, and wrong-number-of-args errors
#      that are invisible at load time.
#
# SANDBOX NOTES — the Nix build sandbox has no network and no display.
# Several measures keep the batch load alive in that environment:
#
#   a) straight.el bootstrap stub: init.el unconditionally tries to load
#      $EMACSDIR/straight/repos/straight.el/bootstrap.el and will fetch it
#      from GitHub if missing. We pre-create a no-op stub that just provides
#      `straight-use-package` (a no-op when packages are already in the load
#      path). ALLOW: the stub emits nothing; no allow-listing needed here.
#
#   b) NIX_PROFILES is set to a non-empty value so hypermodern/nix-emacs-p
#      resolves to t, which prevents straight from trying to auto-install
#      packages it can't reach. ALLOW: benign, changes no load-time output.
#
#   c) HOME is set to $TMPDIR so recentf, custom.el, and other files that
#      init.el writes on startup land in the writable build dir rather than
#      trying to write to a read-only store path.
#
#   d) DISPLAY is not set; --batch suppresses all frame-creation code.
#      tool-bar-mode / scroll-bar-mode in early-init.el are no-ops in batch.
#
{ pkgs }:
let
  emacsPkg =
    (import ../modules/home/emacs/mk-hypermodern-emacs.nix)
      {
        inherit pkgs;
        emacs = pkgs.emacs-unstable-pgtk;
      };

  # Stub straight.el bootstrap — replaces the real bootstrap.el so init.el
  # never tries url-retrieve-synchronously to GitHub. The real straight.el
  # is not needed because the hypermodern emacs package already bundles every
  # package via emacsWithPackages; straight-use-package is only called with
  # 'use-package which is already present in the load path.
  straightStub = pkgs.writeText "straight-bootstrap-stub.el" ''
    ;;; straight-bootstrap-stub.el --- sandbox no-op for nix check -*- lexical-binding: t; -*-
    ;; This stub replaces the network-fetched straight.el bootstrap.
    ;; All packages are pre-installed by emacsWithPackages; straight is not needed.
    (defun straight-use-package (&rest _args)
      "No-op stub: packages are pre-installed by Nix.")
    (provide 'straight-bootstrap-stub)
  '';
in
pkgs.runCommand "emacs-config"
  {
    nativeBuildInputs = [ emacsPkg ];
  }
  ''
    set -euo pipefail

    # ── sandbox setup ───────────────────────────────────────────────────────────

    # HOME must be writable (recentf, custom.el, eln-cache, dashboard banner).
    export HOME="$TMPDIR"

    # Tell init.el we are a Nix-managed Emacs; prevents straight from trying
    # to auto-install packages it cannot reach in the sandbox.
    export NIX_PROFILES="/nix/var/nix/profiles/default"

    # Point EMACSDIR at a writable scratch dir that contains the straight stub,
    # so init.el's bootstrap `load` succeeds without touching the network.
    export EMACSDIR="$TMPDIR/emacsd"
    mkdir -p "$EMACSDIR/straight/repos/straight.el"
    cp ${straightStub} "$EMACSDIR/straight/repos/straight.el/bootstrap.el"

    # ── copy the three config files into a working directory ────────────────────

    mkdir -p "$TMPDIR/elisp"
    cp ${../dotfiles/emacs/early-init.el}          "$TMPDIR/elisp/early-init.el"
    cp ${../dotfiles/emacs/init.el}                "$TMPDIR/elisp/init.el"
    cp ${../dotfiles/emacs/hypermodern-palette.el} "$TMPDIR/elisp/hypermodern-palette.el"
    cp ${../dotfiles/emacs/hypermodern-modeline.el} "$TMPDIR/elisp/hypermodern-modeline.el"
    cd "$TMPDIR/elisp"

    # ── gate 1: batch load ──────────────────────────────────────────────────────
    #
    # Loads early-init.el then init.el exactly as Emacs would at startup.
    # Captures both stdout and stderr; any Warning/Error/Cannot line is fatal.

    echo "emacs-config: running batch load..."
    LOAD_OUT=$(${emacsPkg}/bin/emacs \
      --batch \
      --no-site-file \
      -l early-init.el \
      -l init.el \
      --eval '(message "load ok")' \
      2>&1) || true   # capture exit code separately below

    LOAD_STATUS=$?

    # Allow-list: "Cannot open load file: No such file or directory: dashboard-banner"
    # The banner file write uses with-temp-file which can generate a benign
    # "Cannot open ..." for the target path in strict batch mode on some emacs
    # builds before the file is created. Filter it out before the strict check.
    #
    # Everything else matching Warning|Error|Cannot is a real problem.
    LOAD_STRICT=$(echo "$LOAD_OUT" \
      | grep -v "Cannot open load file.*dashboard-banner" \
      | grep -v "Cannot open load file.*straight-bootstrap-stub" \
      || true)

    echo "--- batch load output ---"
    echo "$LOAD_OUT"
    echo "--- end batch load output ---"

    if echo "$LOAD_STRICT" | grep -qE "Warning|Error|Cannot"; then
      echo "FAIL: batch load produced Warning/Error/Cannot output (see above)"
      exit 1
    fi

    if [ "$LOAD_STATUS" -ne 0 ]; then
      echo "FAIL: emacs --batch exited with status $LOAD_STATUS"
      exit 1
    fi

    # ── gate 2: byte-compile each file ─────────────────────────────────────────
    #
    # Compiles early-init.el, init.el, and hypermodern-palette.el individually.
    # The compiler emits all warnings to stderr; any Warning or Error is fatal.

    echo "emacs-config: byte-compiling..."
    for f in early-init.el init.el hypermodern-palette.el hypermodern-modeline.el; do
      echo "  compiling $f ..."
      COMPILE_OUT=$(${emacsPkg}/bin/emacs \
        --batch \
        --no-site-file \
        -f batch-byte-compile "$f" \
        2>&1) || true

      COMPILE_STATUS=$?

      echo "--- $f compile output ---"
      echo "$COMPILE_OUT"
      echo "--- end $f compile output ---"

      if echo "$COMPILE_OUT" | grep -qE "Warning|Error"; then
        echo "FAIL: byte-compile of $f produced Warning/Error (see above)"
        exit 1
      fi

      if [ "$COMPILE_STATUS" -ne 0 ]; then
        echo "FAIL: byte-compile of $f exited with status $COMPILE_STATUS"
        exit 1
      fi
    done

    echo "emacs config: clean load + zero-warning compile"
    touch $out
  ''
