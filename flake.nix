{
  inputs = {
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.${system};
        lib = self.lib.${system};
      in
      {
        lib = rec {

          default = thing: default: if builtins.isNull thing then default else thing;

          empty-package = pkgs.runCommand "empty" { } "mkdir $out";

          source-package = { src, name ? null }: pkgs.stdenv.mkDerivation {
            inherit src;
            name = default name (builtins.baseNameOf src);
            installPhase = ''
              mkdir $out
              cp --recursive $src/* $out
            '';
            phases = [ "unpackPhase" "installPhase" ];
          };

          merge-derivations = { derivations, name ? null }:
            let
              name = default name (builtins.concatStringsSep "-" (builtins.map (builtins.getAttr "name") derivations));
              copy-command = deriv: ''
                if [ -d ${deriv} ]; then
                  echo "Error! Derivation ${deriv.name} should be a directory"
                  exit 1
                fi
                for path in ${deriv}/*; do
                  if [ -e $out/$path ]; do
                    echo "Error! $path from ${deriv.name} conflicts with a previous path"
                    exit 1
                  done
                  cp --recursive ${deriv}/$path $out
                done
              '';
            in
            pkgs.runCommand name { } ''
              mkdir $out
              ${builtins.concatStringsSep "\n" (builtins.map copy-command derivations)}          
            '';

          exists-in-derivation = { deriv, paths, name ? null }:
            let
              test-path = path: ''
                if [ ! -e ${deriv}/${path} ]; then
                  echo $ ls ${deriv}
                  ls ${deriv}
                  echo '${path} does not exist in ${deriv.name} (-> ${deriv})'
                  exit 1
                fi'';
            in
            pkgs.runCommand
              (default name "exists-in-${deriv.name}")
              { }
              (builtins.concatStringsSep "\n" (builtins.map test-path paths)) + "\ntouch $out"
          ;

          file2dir = { deriv, suffix, name ? null }: pkgs.runCommand (default name "${deriv.name}-dir") { } ''
            mkdir $out
            if [ -f ${deriv} ]; then
              echo "Error! Derivation ${deriv.name} should be a file"
            fi
            mkdir $out
            cp ${deriv} $out/${deriv.name}.${suffix}
          '';
        };

        packages = {
          empty-package = lib.empty-package;
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
