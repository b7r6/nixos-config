{ pkgs, ... }: {
  home.packages = with pkgs; [
    cargo-all-features
    rust-analyzer
    rust-bindgen
    rust-cbindgen
    rustc
    rustup
  ];
}
