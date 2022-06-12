{
  inputs = {
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = self.lib.${system};
        nix-lib = pkgs.lib;
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

          trace = val: builtins.trace val val;

          mergeDerivations =
            { packageSet
            , name ? builtins.concatStringsSep
                "-"
                (nix-lib.attrsets.mapAttrsToList (path: deriv: deriv.name) packageSet)
            }: pkgs.stdenv.mkDerivation {
              inherit name;
              src = ./mergeDerivations;
              installPhase = ''
                mkdir $out
                ${pkgs.python310}/bin/python $src/deep_merge.py $out ${nix-lib.strings.escapeShellArgs (
                  builtins.concatLists (
                    nix-lib.attrsets.mapAttrsToList
                      (path: deriv: [deriv.name deriv path])
                      packageSet))}
              '';
              phases = [ "unpackPhase" "installPhase" ];
            };

          existsInDerivation = { deriv, paths, name ? null }:
            let
              checkPath = path: ''
                if [ ! -e "${deriv}/${path}" ]; then
                  echo '${path} does not exist in ${deriv}'
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
                cp ${deriv}/"${path}" $out
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
            test2 = lib.srcDerivation { src = ./tests/test2; };
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
                packageSet = {
                  "testA" = test0;
                  "testB/" = test1; # Trailing slash shouldn't matter
                  "testC/thing" = test2; # Subdirectories should work
                  "testD" = test1-file; # File should work
                  "test E" = test0; # File with space should work
                  "." = test0; # Dot should work
                };
              };
              paths = [
                "testA/test_file"
                "testB/file with space"
                "testC/thing/test_file2"
                "testD"
                "test_file"
                "test E/test_file"
              ];
            };

            test-file-derivation = test1-file;

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
