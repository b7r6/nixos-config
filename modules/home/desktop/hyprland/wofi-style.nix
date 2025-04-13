{ config }:

let
  inherit (config.lib.stylix) colors;
in
''
  window {
    margin: 0px;
    background-color: ${colors.base00};
    border-radius: 0px;
    border: 2px solid ${colors.base0D};
  }
  #input {
    margin: 5px;
    border: 2px solid ${colors.base02};
    border-radius: 0px;
    color: ${colors.base05};
    background-color: ${colors.base01};
  }
  #inner-box {
    margin: 5px;
    background-color: ${colors.base00};
    border-radius: 0px;
  }
  #outer-box {
    margin: 5px;
    padding: 10px;
    background-color: ${colors.base00};
    border-radius: 0px;
  }
  #scroll {
    margin: 5px;
    background-color: ${colors.base00};
    border-radius: px;
  }
  #text {
    margin: 5px;
    color: ${colors.base05};
  }
  #entry:selected {
    background-color: ${colors.base02};
    border-radius: 5px;
  }
  #text:selected {
    color: ${colors.base0D};
  }
''
