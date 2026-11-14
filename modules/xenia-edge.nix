{ defaultPackage }:
import ./lib/xenia.nix {
  inherit defaultPackage;
  name = "xenia-edge";
  executable = "xenia-edge";
}
