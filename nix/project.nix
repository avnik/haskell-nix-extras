{ config
, pkgs
, src
}:

let
  sources = import ./filter.nix {
    inherit (pkgs) haskell-nix lib;
    inherit src;
    # We need to remove euler-x/ when building transpiler itself.
    excludedFiles = config.excluded-files;
  };
in
  let project = pkgs.haskell-nix-extras.cabalProjectWithExtras {
      inherit (config) extraDependencies;
      inherit (config.project) compiler-nix-name;
      evalPackages = pkgs;
      src = sources;
      # This is used by `nix develop .` to open a shell for use with
      # `cabal`, `hlint` and `haskell-language-server`
      shell = {
        tools = config.shell.tools;
        exactDeps = true;
        withHoogle = config.features.hoogle;
        # FIXME: add assertion to environment
        # All variables from `shell = {}` except ["packages" "components" "additional" "withHoogle" "tools"] fall-thru to shell environmentA
        # (passed as is to mkShell/mkDerivation)
      }
       // { buildInputs = if builtins.isFunction config.buildInputs then config.buildInputs pkgs else config.buildInputs; };
      modules = builtins.map (f: f project) config.extraModules;
  } // config.environment;
in project
