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
            pkgs.stdenvNoCC.mkDerivation {
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
            , name ? "merge"
            }:
            let
              getName = deriv:
                if nix-lib.attrsets.isDerivation deriv
                then deriv.name
                else
                  if (builtins.isPath deriv) || (builtins.isString deriv)
                  then builtins.baseNameOf deriv
                  else builtins.throw "Unknown type ${builtins.typeOf deriv}";
            in
            pkgs.stdenvNoCC.mkDerivation {
              inherit name;
              src = ./mergeDerivations;
              installPhase = ''
                mkdir $out
                ${pkgs.python310}/bin/python $src/deep_merge.py $out ${nix-lib.strings.escapeShellArgs (
                  builtins.concatLists (
                    nix-lib.attrsets.mapAttrsToList
                      (path: derivs:
                        if builtins.isList derivs
                        then builtins.concatLists (
                          builtins.map (deriv: [(getName deriv) "${deriv}" path]) derivs)
                        else [(getName derivs) "${derivs}" path])
                      packageSet))}
              '';
              phases = [ "unpackPhase" "installPhase" ];
            };

          existsInDerivation = { deriv, paths, name ? "exists-in-${deriv.name}" }:
            let
              checkPath = path: ''
                if [ ! -e "${deriv}/${path}" ]; then
                  echo '${path} does not exist in ${deriv}'
                  exit 1
                fi'';
            in
            pkgs.runCommand
              name
              { }
              (builtins.concatStringsSep
                "\n"
                ((builtins.map checkPath paths) ++ [ "touch $out" ]));

          selectInDerivation = { deriv, path, name ? null }:
            pkgs.runCommand
              (default name "${builtins.baseNameOf path}")
              { }
              ''
                cp --recursive ${deriv}/"${path}" $out
              '';

          # [derivations] -> {derivation0.name = derivation0; ...}
          packageSet = derivations: packageSetRec (self: derivations);

          packageSetRec = derivations:
            nix-lib.fix
              (self:
                builtins.listToAttrs
                  (builtins.map
                    (deriv: { name = deriv.name; value = deriv; })
                    (derivations self)));

          renameDerivation = name: deriv: deriv // { inherit name; };

          listOfListOfArgs = lines:
            builtins.concatStringsSep
              "\n"
              (builtins.map
                (line:
                  builtins.concatStringsSep
                    " "
                    (
                      builtins.map
                        (arg:
                          if builtins.isString arg
                          then if arg == ""
                          then builtins.throw "Arg cannot be empty string"
                          else nix-lib.strings.escapeShellArg arg
                          else
                            if builtins.isAttrs arg
                            then getAttrOr arg "literal" (builtins.throw "Attrset shoudl have a literal attr")
                            else builtins.throw "Unknown type ${builtins.typeOf arg}"
                        )
                        (nix-lib.lists.flatten line)
                    )
                )
                (lines ++ [{ literal = ""; }])
              );
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
            test1-file = lib.selectInDerivation {
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
                  "testF" = [ test0 test1 ]; # list should work
                  "testG" = ./tests/test3; # path outside of Nix store should work
                };
              };
              paths = [
                "testA/test_file"
                "testB/file with space"
                "testC/thing/test_file2"
                "testD"
                "test_file"
                "test E/test_file"
                "testF/test_file"
                "testF/file with space"
                "testG/test_file3"
              ];
            };

            test-file-derivation = test1-file;

            test-packageSet =
              assert (lib.packageSet [ test0 test1 ]) == {
                test0 = test0;
                test1 = test1;
              };
              packages.empty;

            test-packageSetRec =
              assert nix-lib.attrsets.mapAttrsToList (key: val: key)
                (lib.packageSetRec (self: [
                  test0
                  test1
                  (lib.existsInDerivation {
                    deriv = self.test0;
                    paths = [ "test_file" ];
                    name = "test2";
                  })
                ])) == [ "test0" "test1" "test2" ];
              packages.empty;

            test-renameDerivation =
              assert (lib.renameDerivation "test123" test0).name == "test123";
              packages.empty;

            test-listOfListOfArgs =
              assert (lib.listOfListOfArgs [
                [ "a" "b" "c" ]
                [ "d" "e" "f" ]
                [ "g" "h" { literal = "i"; } ]
              ]) == "'a' 'b' 'c'\n'd' 'e' 'f'\n'g' 'h' i\n";
              packages.empty;

          } // packages;
      }
    );
}
