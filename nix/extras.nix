{ compiler-nix-name ? "ghc8107", haskellNixSrc }:

(final: prev:
  {
  haskell-nix-extras = with final.haskell-nix-extras; with final.haskell-nix; {
    inherit (final) haskell-nix;
    hackage-repo-tool = evalPackages: tool' evalPackages compiler-nix-name "hackage-repo-tool" "0.1.1.3";

    nix-tools' = evalPackages: [
      evalPackages.haskell-nix.nix-tools-unchecked.${compiler-nix-name}
      evalPackages.haskell-nix.cabal-install-unchecked.${compiler-nix-name}
    ];

    # Silly debug wrapper over runCommand
    runCommandVerbose = evalPackages: name: args: script: evalPackages.runCommand name args ''
      set -x
      ${script}
      set +x
    '';

    makeSdistFromRepo  = {
        name ? "sdist",
        subPackages ? ["all"],
        preSdist ? "",
        evalPackages,
        src
      }:
      let cleanedSource = src; in
      runCommandVerbose evalPackages name {
        nativeBuildInputs = (nix-tools' evalPackages) ++ [ evalPackages.haskell-nix.cabal-issue-8352-workaround ];
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

    snakeoil-hackage-keys = evalPackages: runCommandVerbose evalPackages "snakeoil-hackage-keys" {}
      ''
        mkdir $out
        cp -r ${./snakeoil-keys}/{mirrors,root,snapshot,timestamp,target} $out/
      '';

    mkExtraHackageRepo = {
        evalPackages,
        name ? "local-hackage-repo",
        sdists ? []
    }: runCommandVerbose evalPackages "local-hackage-repo" {  nativeBuildInputs = [ (hackage-repo-tool evalPackages)]; preferLocalBuild = true; }
      ''
        mkdir -p $out/{package,index}
        ${final.lib.concatStrings (map (name: ''
          ln -svf ${name}/sdist/* $out/package/
        '') sdists)}
        ${hackage-repo-tool evalPackages}/bin/hackage-repo-tool --expire-root 1000 --expire-mirrors 1000 bootstrap --keys ${snakeoil-hackage-keys evalPackages} --repo $out/
        rm -fr $out/*.json
      '';
    mkExtraHackageNix = {
        name ? "local-hackage-nix",
        evalPackages,
        repoContents
    }: let
      repoUrl = "magic://"; # non-working URL, sources are overwritten with direct links on tarballs later.
      in runCommandVerbose evalPackages "local-hackage-to-nix-${name}" {
          nativeBuildInputs = [ evalPackages.curl ] ++ (nix-tools' evalPackages);
          LOCALE_ARCHIVE = evalPackages.lib.optionalString (evalPackages.stdenv.buildPlatform.libc == "glibc") "${evalPackages.glibcLocales}/lib/locale/locale-archive";
          LANG = "en_US.UTF-8";
          preferLocalBuild = true;
      }
      ''
        mkdir -p $out
        hackage-to-nix $out ${repoContents}/01-index.tar ${repoUrl}

        # Workaround with discard context. FIXME: investigate and fix.
        #cp ${./magic.nix} $out/default.nix
        # Bookmark repoContents, $out require it anyway
        echo ${repoContents} >$out/magic
      '';

    mkExtras = { evalPackages, extraDependencies ? [], extraSdists ? [], extra-hackages ? [], extra-hackage-tarballs ? {}, modules ? [] }:
      let
        inherit (evalPackages.lib) mapAttrsToList flatten mkForce;
        sdists = extraSdists ++ (builtins.map (each: makeSdistFromRepo { inherit evalPackages; src = each; }) extraDependencies);
        haveSdists = (builtins.length sdists) > 0;
        localHackage =
          if haveSdists
            then mkExtraHackageRepo { inherit evalPackages; name = "sdists-hackage"; sdists = sdists; }
            else [];
        tarballs =
          if haveSdists
            then { extra-sdists = "${localHackage}/01-index.tar.gz"; }
            else {};
        localHackageNix =
          if haveSdists
            then (import (mkExtraHackageNix { inherit evalPackages; repoContents = localHackage; }))
            else {};
        localHackageModules' = flatten
          (mapAttrsToList
            (pname: hPkg: mapAttrsToList
              (ver: vPkg:
               { packages.${pname}.src = mkForce "${localHackage}/package/${pname}-${ver}.tar.gz"; }
               ) hPkg)
          localHackageNix);
        localHackageModules = if haveSdists then localHackageModules' else [];
      in {
          extra-hackages = extra-hackages ++ [ localHackageNix ];
          extra-hackage-tarballs = extra-hackage-tarballs // tarballs;
          modules = modules ++ localHackageModules;
      };

    dummyModule = _: { };
    evalProjectConfig = config: final.haskell-nix.haskellLib.evalProjectModule (dummyModule) (import "${haskellNixSrc}/modules/project-common.nix") 
      ({...}: config.project);

    cabalProjectWithExtras = { evalPackages, extraDependencies ? [], extraSdists ? [], extra-hackages ? [], extra-hackage-tarballs ? {}, modules ? [], ...}@args:
      let
        args' = removeAttrs args ["extraDependencies" "extraSdists"];
        extras = mkExtras { inherit extraDependencies extraSdists extra-hackages extra-hackage-tarballs evalPackages; };
      in final.haskell-nix.cabalProject' (args' // {
          inherit (extras) extra-hackages extra-hackage-tarballs modules;
      });
  };
})
