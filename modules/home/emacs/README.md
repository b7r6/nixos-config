# Including Custom Emacs Libraries with Home Manager

When using Home Manager to manage your Emacs configuration, you have several options for including custom libraries in your `.emacs.d` directory:

## Option 1: Use `extraPackages`

You can add Emacs packages from nixpkgs using the `extraPackages` option:

```nix
programs.emacs = {
  enable = true;
  extraPackages = epkgs: [
    # Standard packages from nixpkgs
    epkgs.magit
    epkgs.evil
    # etc.
  ];
};
```

## Option 2: Use `packageRequires` for your own packages

For your custom libraries, you can create a derivation and include it:

```nix
let
  myCustomEmacsPackage = pkgs.emacsPackages.trivialBuild {
    pname = "my-custom-package";
    version = "1.0";
    src = ./path/to/your/library;  # Directory containing your .el files
    # Define package dependencies if needed
    packageRequires = with pkgs.emacsPackages; [ s dash ];
  };
in
{
  programs.emacs = {
    enable = true;
    extraPackages = epkgs: [
      myCustomEmacsPackage
      # other packages...
    ];
  };
}
```

## Option 3: Use `emacsWithPackages` for a more custom setup

```nix
let
  myEmacs = pkgs.emacsWithPackages (epkgs: [
    # Standard packages
    epkgs.magit

    # Your custom package
    (epkgs.trivialBuild {
      pname = "my-custom-lib";
      version = "1.0";
      src = ./path/to/your/lib;
    })
  ]);
in
{
  programs.emacs.enable = true;
  programs.emacs.package = myEmacs;
}
```

## Option 4: Use `extraConfig` to add load paths

If you just want to store your libraries in a specific location:

```nix
programs.emacs = {
  enable = true;
  extraConfig = ''
    ;; Add your custom library directory to load-path
    (add-to-list 'load-path "~/path/to/your/emacs/libs")
  '';
};
```

## Option 5: Create a file in `home.file`

You can also place files directly in your `.emacs.d` directory:

````nix
{
  programs.emacs.enable = true;

  home.file = {
    ".emacs.d/lisp/my-custom-lib.el".source = ./path/to/my-custom-lib.el;
    # You can add more files as needed
  };
}
# Including Custom Emacs Libraries with Home Manager

When using Home Manager to manage your Emacs configuration, you have several options for including custom libraries in your `.emacs.d` directory:

## Option 1: Use `extraPackages`

You can add Emacs packages from nixpkgs using the `extraPackages` option:

```nix
programs.emacs = {
  enable = true;
  extraPackages = epkgs: [
    # Standard packages from nixpkgs
    epkgs.magit
    epkgs.evil
    # etc.
  ];
};
````

## Option 2: Use `packageRequires` for your own packages

For your custom libraries, you can create a derivation and include it:

```nix
let
  myCustomEmacsPackage = pkgs.emacsPackages.trivialBuild {
    pname = "my-custom-package";
    version = "1.0";
    src = ./path/to/your/library;  # Directory containing your .el files
    # Define package dependencies if needed
    packageRequires = with pkgs.emacsPackages; [ s dash ];
  };
in
{
  programs.emacs = {
    enable = true;
    extraPackages = epkgs: [
      myCustomEmacsPackage
      # other packages...
    ];
  };
}
```

## Option 3: Use `emacsWithPackages` for a more custom setup

```nix
let
  myEmacs = pkgs.emacsWithPackages (epkgs: [
    # Standard packages
    epkgs.magit

    # Your custom package
    (epkgs.trivialBuild {
      pname = "my-custom-lib";
      version = "1.0";
      src = ./path/to/your/lib;
    })
  ]);
in
{
  programs.emacs.enable = true;
  programs.emacs.package = myEmacs;
}
```

## Option 4: Use `extraConfig` to add load paths

If you just want to store your libraries in a specific location:

```nix
programs.emacs = {
  enable = true;
  extraConfig = ''
    ;; Add your custom library directory to load-path
    (add-to-list 'load-path "~/path/to/your/emacs/libs")
  '';
};
```

## Option 5: Create a file in `home.file`

You can also place files directly in your `.emacs.d` directory:

```nix
{
  programs.emacs.enable = true;

  home.file = {
    ".emacs.d/lisp/my-custom-lib.el".source = ./path/to/my-custom-lib.el;
    # You can add more files as needed
  };
}
```
