{ haskell-nix
, lib
, excludedFiles
, src
, name ? "base-project"
}:
let
  filterPath = includedFiles: path: type:
    lib.any (f:
        let p = toString (src + ("/" + f));
          in p == path || (lib.strings.hasPrefix (p + "/") path)
        ) includedFiles;

  cleanedSrc = haskell-nix.haskellLib.cleanSourceWith {
    filter = path: type: !(filterPath excludedFiles path type);
    inherit src name;
   };
in cleanedSrc
