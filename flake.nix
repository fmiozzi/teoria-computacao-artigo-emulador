{
  description = "Emulador — Monitor LTL/TLTL (Peça 1: propriedade A1) em Haskell";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            haskell.compiler.ghc94
            cabal-install
            haskellPackages.haskell-language-server
          ];

          shellHook = ''
            echo ""
            echo "Emulador — Monitor LTL/TLTL"
            echo "  GHC   : $(ghc --version)"
            echo "  Cabal : $(cabal --version | head -n1)"
            echo ""
            echo "Comandos disponíveis:"
            echo "  cabal build                       # compila o monitor"
            echo "  ./Exec/monitor.sh <traço.txt>     # roda um traço"
            echo "  ./Exec/batch.sh                   # roda todos os traços"
            echo ""
          '';
        };
      });
}
