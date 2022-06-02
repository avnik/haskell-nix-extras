# Standard default.nix from hackage.nix, but with unsafeDiscardStringContext added.
# FIXME: investigate, why we need unsafeDiscardStringContext here and how to avoid it
with builtins; mapAttrs (_: mapAttrs (_: data: rec {
 inherit (data) sha256;
 revisions = (mapAttrs (rev: rdata: {
  inherit (rdata) revNum sha256;
  outPath = ./. + "/hackage/${rdata.outPath}";
 }) data.revisions) // {
  default = revisions."${data.revisions.default}";
 };
})) (fromJSON (unsafeDiscardStringContext (readFile ./hackage.json)))
