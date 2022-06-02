{ compiler-nix-name ? "ghc8107"}:

(final: prev: 
  let pkgs = final.evalPackages; in {
  haskell-nix-extras = with final.haskell-nix-extras; with final.haskell-nix; {
    inherit (final) haskell-nix;  
    hackage-repo-tool = hackage-tool { name = "hackage-repo-tool"; inherit compiler-nix-name; };
    nix-tools' = final.evalPackages.haskell-nix.nix-tools-unchecked.${compiler-nix-name};
    cabal-install' = final.evalPackages.haskell-nix.cabal-install-unchecked.${compiler-nix-name};

    # Silly debug wrapper over runCommand
    runCommandVerbose = name: args: script: final.evalPackages.runCommand name args ''
      set -x
      ${script}
      set +x
    '';

    makeSdistFromRepo  = {
        name ? "sdist",
        subPackages ? ["all"],
        preSdist ? "",
        src
      }:
      let cleanedSource = src; in
      runCommandVerbose name {
        nativeBuildInputs = [ nix-tools' cabal-install' ];
        preferLocalBuild = true;
      } ''
          tmp=$(mktemp -d)
          cd $tmp
          cp -r ${cleanedSource}/* .
          chmod +w -R .

          nullglobRestore=$(shopt -p nullglob)
          shopt -u nullglob
          for hpackFile in $(find . -name package.yaml); do (
            # Look to see if a `.cabal` file exists
            for cabalFile in $(dirname $hpackFile)/*.cabal; do
              if [ -e "$cabalFile" ]; then
                echo Ignoring $hpackFile as $cabalFile exists
              else
                # warning: this may not generate the proper cabal file.
                # hpack allows globbing, and turns that into module lists
                # without the source available (we cleaneSourceWith'd it),
                # this may not produce the right result.
                echo No .cabal file found, running hpack on $hpackFile
                hpack $hpackFile
              fi
            done
           )
          done
          $nullglobRestore

          homedir=$(mktemp -d)
          ${final.lib.concatStrings (map (name: ''
            HOME=$homedir cabal v2-sdist --builddir $out ${name}
          '') subPackages)}
        '';

    snakeoil-hackage-keys = runCommandVerbose "snakeoil-hackage-keys" {}
      ''
        mkdir $out
        cp -r ${./snakeoil-keys}/{mirrors,root,snapshot,timestamp,target} $out/
      '';

    mkExtraHackageRepo = {
        name ? "local-hackage-repo",
        sdists ? []
    }: runCommandVerbose "local-hackage-repo" {  nativeBuildInputs = [ hackage-repo-tool ]; preferLocalBuild = true; }
      ''
        mkdir -p $out/{package,index}
        ${final.lib.concatStrings (map (name: ''
          ln -svf ${name}/sdist/* $out/package/
        '') sdists)}
        ${hackage-repo-tool}/bin/hackage-repo-tool --expire-root 1000 --expire-mirrors 1000 bootstrap --keys ${snakeoil-hackage-keys} --repo $out/
        rm -fr $out/*.json
      '';
    mkExtraHackageNix = {
        name ? "local-hackage-nix",
        repoContents
    }: let
      repoUrl = "magic://"; # non-working URL, sources are overwritten with direct links on tarballs later.
      in runCommandVerbose "local-hackage-to-nix-${name}" {
          nativeBuildInputs = [ cabal-install' pkgs.evalPackages.curl nix-tools' ];
          LOCALE_ARCHIVE = pkgs.lib.optionalString (pkgs.evalPackages.stdenv.buildPlatform.libc == "glibc") "${pkgs.evalPackages.glibcLocales}/lib/locale/locale-archive";
          LANG = "en_US.UTF-8";
          preferLocalBuild = true;
      }
      ''
        mkdir -p $out
        hackage-to-nix $out ${repoContents}/01-index.tar ${repoUrl}
        #find $out/hackage -name \*.nix | xargs -n1 sed -i "s,pkgs\.fetchUrl,pkgs.fetchurlWithMagicSupport,"
        # Workaround with discard context. FIXME: investigate and fix.
        cp ${./magic.nix} $out/default.nix
        # Bookmark repoContents, $out require it anyway
        echo ${repoContents} >$out/magic
      '';

    cabalProjectWithExtras = { extraDependencies ? [], extraSdists ? [], extra-hackages ? [], extra-hackage-tarballs ? {}, modules ? [], ...}@args:
      let
        inherit (pkgs.lib) mapAttrsToList flatten mkForce;
        args' = removeAttrs args ["extraDependencies" "extraSdists"];
        sdists = extraSdists ++ (builtins.map (each: makeSdistFromRepo { src = each; }) extraDependencies);
        localHackage = mkExtraHackageRepo { name = "sdists-hackage"; sdists = sdists; };
        tarballs = { extra-sdists = "${localHackage}/01-index.tar.gz"; };
        localHackageNix = import (mkExtraHackageNix { repoContents = localHackage; });
        localHackageModules = flatten
          (mapAttrsToList 
            (pname: hPkg: mapAttrsToList 
              (ver: vPkg: 
               { packages.${pname}.src = mkForce "${localHackage}/package/${pname}-${ver}.tar.gz"; }
               ) hPkg)
          localHackageNix);
      in final.haskell-nix.cabalProject' (args' // {
          extra-hackages = extra-hackages ++ [ localHackageNix ];
          extra-hackage-tarballs = extra-hackage-tarballs // tarballs;
          modules = modules ++ localHackageModules;
      });
  };
})
