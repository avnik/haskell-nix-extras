{
  inputs = {
    haskellNix = { url = "github:input-output-hk/haskell.nix"; };
    flake-utils = { url = "github:numtide/flake-utils"; };
  };

  outputs = { self, flake-utils, haskellNix }@inputs:
    let libs = rec {
      supportedSystems = config: f: flake-utils.lib.eachSystem config.supported-systems f;
      mkFlake = config: src:
        supportedSystems config (system:
          let
          pkgs = self.legacyPackages.${system};
          project = import ./nix/project.nix {
            inherit config pkgs src;
          };
          flake = project.flake {
            # This adds support for `nix build .#js-unknown-ghcjs-cabal:hello:exe:hello`
            #crossPlatforms = p: [p.ghcjs];
          };
        in flake // {
        # Built by `nix build .`
          defaultPackage = flake.packages."${config.project-name}:exe:nau-exe";
        });
    };
    systems = flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ] (system: {
       overlays = [ 
         inputs.haskellNix.overlay
         (import ./nix/extras.nix {})
       ];

       legacyPackages = import haskellNix.inputs.nixpkgs { inherit system; overlays = self.overlays.${system}; };
    });
    in systems // { lib = libs; };
}
