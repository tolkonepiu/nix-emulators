{ defaultPackage }:
import ./lib/xenia.nix {
  inherit defaultPackage;
  name = "xenia-canary";
  executable = "xenia_canary";
}
