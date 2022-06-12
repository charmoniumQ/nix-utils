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

          srcDerivation = { src, name ? builtins.baseNameOf src }:
            pkgs.stdenv.mkDerivation {
              inherit src;
              inherit name;
              installPhase = ''
                mkdir $out
                for path in $src/*; do
                  cp --recursive "$path" $out
                done
              '';
              phases = [ "unpackPhase" "installPhase" ];
            };

          mergeDerivations =
            { derivations
            , name ? builtins.concatStringsSep
                "-"
                (builtins.map (builtins.getAttr "name") derivations)
            }:
            let
              copyCommand = deriv: ''
                if [ ! -d ${deriv} ]; then
                  echo "Error! Derivation ${deriv} should be a directory"
                  exit 1
                fi
                for path in ${deriv}/*; do
                  if [ -e $out/$path ]; then
                    echo "Error! $path from ${deriv.name} conflicts with a previous path"
                    exit 1
                  fi
                  cp --recursive "$path" $out
                done
              '';
            in
            pkgs.runCommand name { } ''
              mkdir $out
              ${builtins.concatStringsSep
                "\n"
                (builtins.map copyCommand derivations)}
            '';

          existsInDerivation = { deriv, paths, name ? null }:
            let
              checkPath = path: ''
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
                ((builtins.map checkPath paths) ++ [ "touch $out" ]));

          fileDerivation = { deriv, path, name ? null }:
            pkgs.runCommand
              (default name "${builtins.baseNameOf path}")
              { }
              ''
                cat ${deriv}/"${path}" > $out
              '';

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
              '';

          # [derivations] -> {derivation0.name = derivation0; ...}
          packageSet = derivations:
            builtins.listToAttrs
              (builtins.map (deriv: { name = deriv.name; value = deriv; }) derivations);

          renameDerivation = name: deriv: deriv // { inherit name; };

        };

        packages = {
          empty = pkgs.runCommand "empty" { } "mkdir $out";
        };

        formatter = pkgs.nixpkgs-fmt;

        checks =
          let
            test0 = lib.srcDerivation { src = ./tests/test0; };
            test1 = lib.srcDerivation { src = ./tests/test1; };
            test1-file = lib.fileDerivation {
              deriv = test1;
              path = "file with space";
            };
          in
          {
            test-empty = pkgs.runCommand "test-empty" { } ''
              [ -d ${packages.empty} ]
              [ -z $(ls ${packages.empty} ) ]
              mkdir $out
            '';
            test-raw-derivation = lib.existsInDerivation {
              deriv = test0;
              paths = [ "test_file" ];
            };

            test-merge-derivations = lib.existsInDerivation {
              deriv = lib.mergeDerivations {
                derivations = [ test0 test1 ];
              };
              paths = [ "test_file" "file with space" ];
            };

            test-file-derivation = test1-file;

            test-file2dir = lib.existsInDerivation {
              deriv = lib.file2dir {
                deriv = test1-file;
                suffix = ".txt";
              };
              paths = [ "file with space.txt" ];
            };

            test-packageSet =
              assert (lib.packageSet [ test0 test1 ]) == { test0 = test0; test1 = test1; };
              packages.empty;

            test-renameDerivation =
              assert (lib.renameDerivation "test123" test0).name == "test123";
              packages.empty;

          } // packages;
      }
    );
}
