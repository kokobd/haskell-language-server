/*
  Some examples:
  nix build .#ghc923:haskell-language-server:exe:haskell-language-server
  nix develop .#ghc923
  nix develop .#ghc923-fhs
  nix run .#ghc8107:hls-selection-range-plugin:test:tests

  You can find supported GHC versions at https://haskell-language-server.readthedocs.io/en/latest/supported-versions.html
*/

{
  description = "Haskell Language Server";

  inputs = {
    haskellNix.url = "github:kokobd/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    rawNixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rawNixpkgs, flake-utils, haskellNix, flake-compat }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system:
      let
        # List of supported compilers. The first is the default.
        compilers = [ "ghc923" "ghc922" "ghc902" "ghc8107" "ghc884" "ghc865" ];

        hlsDrvName = compiler: "haskell-language-server-dev-${compiler}";

        overlays = [
          haskellNix.overlay
          (final: prev:
            let buildHLS = compiler: {
              name = hlsDrvName compiler;
              value = final.haskell-nix.project' {
                src = ./.;
                compiler-nix-name = compiler;
                projectFileName = "cabal.project";
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
            };
            in
            {
              haskell-nix = prev.haskell-nix //
              {
                packageToolName = prev.haskell-nix.packageToolName // {
                  implicit-hie = "gen-hie";
                };
              };
            } // builtins.listToAttrs (map buildHLS compilers))
        ];
        pkgs = import nixpkgs { inherit system overlays; inherit (haskellNix) config; };

        buildFlake = compiler: {
          name = compiler;
          value = pkgs."${hlsDrvName compiler}".flake { };
        };
        flakes = builtins.listToAttrs (map buildFlake compilers);
        prependCompiler = compiler: field: isShell: with pkgs.lib;
          if isShell
          then { "${compiler}" = field; }
          else
            let
              packages = field;
              newNames = map (name: compiler + ":" + name) (attrNames packages);
              values = attrValues packages;
            in
            builtins.listToAttrs (zipListsWith (name: value: { inherit name; inherit value; }) newNames values);
        mergeFlakeField = field: builtins.foldl' (acc: cur: acc // cur) { } (pkgs.lib.attrValues
          (pkgs.lib.mapAttrs (compiler: flake: prependCompiler compiler flake."${field}" (field == "devShell")) flakes));

        rawNixpkgs' = import rawNixpkgs { inherit system; };
        mkDevShellFHS = compiler:
          let name = compiler + "-fhs"; in
          {
            inherit name;
            value = (rawNixpkgs'.buildFHSUserEnv {
              inherit name;
              targetPkgs = pkgs: with pkgs; [
                coreutils
                binutils
                gcc
                zlib.dev
                gmp.dev
                ncurses.dev
                python
                haskell.compiler."${compiler}"
                cabal-install
                stack
                haskellPackages.hoogle
                haskellPackages.implicit-hie
                stylish-haskell
                pre-commit
              ];
              profile = "export PATH=~/.cabal/bin:~/.local/bin:$PATH";
            }).env;
          };

        devShellsFHS = builtins.listToAttrs (map mkDevShellFHS compilers);
      in
      rec {
        packages = mergeFlakeField "packages";
        checks = mergeFlakeField "checks";
        apps = mergeFlakeField "apps";
        defaultPackage = packages."${builtins.head compilers}:haskell-language-server:exe:haskell-language-server";
        devShells = mergeFlakeField "devShell" // devShellsFHS;
        devShell = devShells."${builtins.head compilers}";
      });
}
