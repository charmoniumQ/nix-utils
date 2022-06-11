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
      rec {
        lib = rec {

          default = thing: defaultVal:
            if builtins.isNull thing
            then defaultVal
            else thing;

          getAttrOr = set: attr: defaultVal:
            if builtins.hasAttr attr set
            then builtins.getAttr attr set
            else defaultVal;

          # TODO: spaces in filename
          raw-derivation = { src, name ? null }: pkgs.stdenv.mkDerivation {
            inherit src;
            name = default name (builtins.baseNameOf src);
            installPhase = ''
              mkdir $out
              for path in $src/*; do
                cp --recursive $path $out
              done
            '';
            phases = [ "unpackPhase" "installPhase" ];
          };

          merge-derivations = { derivations, name ? null }:
            let
              name2 = default
                name
                (builtins.concatStringsSep
                  "-"
                  (builtins.map (builtins.getAttr "name") derivations));
              copy-command = deriv: ''
                if [ ! -d ${deriv} ]; then
                  echo "Error! Derivation ${deriv} should be a directory"
                  exit 1
                fi
                for path in ${deriv}/*; do
                  if [ -e $out/$path ]; then
                    echo "Error! $path from ${deriv.name} conflicts with a previous path"
                    exit 1
                  fi
                  cp --recursive $path $out
                done
              '';
            in
            pkgs.runCommand name2 { } ''
              mkdir $out
              ${builtins.concatStringsSep
                "\n"
                (builtins.map copy-command derivations)}
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
              (builtins.concatStringsSep
                "\n"
                ((builtins.map test-path paths) ++ [ "touch $out" ]))
          ;

          file-derivation = { deriv, path, name ? null }:
            pkgs.runCommand
              (default name "${builtins.baseNameOf path}")
              { }
              ''
                cat ${deriv}/${path} > $out
              ''
          ;

          file2dir = { deriv, suffix, name ? null }:
            pkgs.runCommand
              (default name "${deriv.name}-dir")
              { }
              ''
                mkdir $out
                if [ ! -f ${deriv} ]; then
                  echo "Error! Derivation ${deriv} should be a file"
                  exit 1
                fi
                cp ${deriv} $out/${deriv.name}${suffix}
              ''
          ;
        };

        packages = {
          empty = pkgs.runCommand "empty" { } "mkdir $out";
        };

        formatter = pkgs.nixpkgs-fmt;

        checks =
          let
            test0 = lib.raw-derivation { src = ./tests/test0; };
            test1 = lib.raw-derivation { src = ./tests/test1; };
            test1-file = lib.file-derivation {
              deriv = test1;
              path = "index";
            };
          in
          {
            test-empty = pkgs.runCommand "test-empty" { } ''
              [ -d ${packages.empty} ]
              [ -z $(ls ${packages.empty} ) ]
              mkdir $out
            '';
            test-raw-derivation = lib.exists-in-derivation {
              deriv = test0;
              paths = [ "test_file" ];
            };

            test-merge-derivations = lib.exists-in-derivation {
              deriv = lib.merge-derivations {
                derivations = [ test0 test1 ];
              };
              paths = [ "test_file" "index" ];
            };

            test-file-derivation = test1-file;

            test-file2dir = lib.exists-in-derivation {
              deriv = lib.file2dir {
                deriv = test1-file;
                suffix = ".txt";
              };
              paths = [ "index.txt" ];
            };
          };
      }
    );
}
