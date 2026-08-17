# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // checks // nvim-config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Boots dotfiles/nvim headless in a hermetic XDG sandbox, exactly the
# degraded-ladder bottom rung: no network, no plugins, no wintermute state.
# The config's contract is that this still yields a fully themed session —
# the palette engine computes the committed default vector and the theme
# applies. ANY startup error or warning line fails the gate (the emacs
# zero-warning discipline, one editor over).
#
# The palette math itself is pinned by checks.ono-sendai-parity (fifth
# implementation, `nvim -l`); this check owns startup correctness.
{ pkgs }:
pkgs.runCommand "nvim-config" { nativeBuildInputs = [ pkgs.neovim ]; } ''
  export HOME=$TMPDIR
  export XDG_CONFIG_HOME=$TMPDIR/config
  export XDG_DATA_HOME=$TMPDIR/data
  export XDG_STATE_HOME=$TMPDIR/state
  export HYPERMODERN_NVIM_NO_NET=1
  mkdir -p $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_STATE_HOME
  ln -s ${../dotfiles/nvim} $XDG_CONFIG_HOME/nvim

  nvim --headless \
    "+lua print('BOOT colors=' .. tostring(vim.g.colors_name))" \
    "+lua assert(vim.g.colors_name == 'hypermodern', 'theme did not apply')" \
    "+lua assert(require('hypermodern.theme').palette.base00 ~= nil, 'no computed palette')" \
    "+qa!" > out.log 2>&1 || {
      echo "── nvim startup failed:"; cat out.log; exit 1; }

  # zero-warning gate: nothing on stderr/stdout beyond our BOOT marker
  if grep -vE '^BOOT colors=hypermodern$' out.log | grep -q .; then
    echo "── unexpected startup output (warnings are failures here):"
    cat out.log
    exit 1
  fi
  grep -q '^BOOT colors=hypermodern$' out.log
  touch $out
''
