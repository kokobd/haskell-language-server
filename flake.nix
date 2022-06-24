{
  description = "Haskell Language Server";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, haskellNix, flake-compat }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system:
      let
        overlays = [
          haskellNix.overlay
          (final: prev: {
            haskell-nix = prev.haskell-nix //
              {
                packageToolName = prev.haskell-nix.packageToolName // {
                  implicit-hie = "gen-hie";
                };
              };

            # This overlay adds our project to pkgs
            haskellLanguageServerDev =
              final.haskell-nix.project' {
                src = ./.;
                compiler-nix-name = "ghc923"; # TODO multiple compiler versions
                projectFileName = "cabal.project";
                modules = [
                  {
                    enableLibraryProfiling = true;
                    enableProfiling = true;
                    enableShared = true;
                    enableStatic = false;
                  }
                ];
                shell = {
                  withHoogle = true;

                  tools = {
                    cabal = "latest";
                    hlint = "latest";
                    implicit-hie = "latest";
                  };

                  buildInputs = with pkgs; [
                    stylish-haskell
                    nixfmt
                    pre-commit
                  ];
                };
              };
          })
        ];
        pkgs = import nixpkgs { inherit system overlays; inherit (haskellNix) config; };
        flake = pkgs.haskellLanguageServerDev.flake { };
      in
      flake // {
        defaultPackage = flake.packages."haskell-language-server:exe:haskell-language-server";
      });
}
