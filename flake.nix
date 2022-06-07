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
      in {
        lib = rec {

          default = thing: default: if builtins.isNull thing then default else thing;
  
          empty-package = pkgs.runCommand "empty" { } "mkdir $out";
  
          source-package = { src, name ? null}: pkgs.stdenv.mkDerivation {
            inherit src;
            # TODO: `name` should be builtins.dirOf src
            name = default name (builtins.baseNameOf src);
            installPhase =''
              mkdir $out
              cp --recursive $src/* $out
            '';
            phases = ["unpackPhase" "installPhase"];
          };
  
          merge-derivations = { derivations, name ? null }:
            let
            name = default name (builtins.concatStringSep "-" (builtins.map (builtins.getAttr "name") derivations));
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
            pkgs.runCommand name {} ''
              mkdir $out
              ${builtins.concatStringSep "\n" (builtins.map copy-command derivations)}          
            '';
  
          file2dir = {deriv, suffix, name ? null}: pkgs.runCommand (default name "${deriv.name}-dir") { } ''
            mkdir $out
            if [ -f ${deriv} ]; then
              echo "Error! Derivation ${deriv.name} should be a file"
            fi
            mkdir $out
            cp ${deriv} $out/${deriv.name}.${suffix}
          '';
  
          citation-style-language-styles = source-package {
            src = pkgs.fetchFromGitHub {
              owner = "citation-style-language";
              repo = "styles";
              rev = "3602c18c16d51ff5e4996c2c7da24ea2cc5e546c";
              hash = "sha256-X+iRAt2Yzp1ePtmHT5UJ4MjwFVMu2gixmw9+zoqPq20=";
            };
          };

          graphviz-document =
            {src, name ? null, main ? "index.graphviz", output-format ? "svg" }:
            pkgs.stdenv.mkDerivation {
              name = default name (builtins.baseNameOf src);
              inherit src;
              installPhase = ''
                ${pkgs.graphviz}/bin/dot $src/${main} -T${output-format} -o$out
              '';
            };
  
          markdown-document =
            { src
            , name ? null
            , main ? "index.md"
            , inputs ? empty-package
            , output-format ? "pdf" # passed to Pandoc
            , csl-style ? "acm-sig-proceedings" # from CSL styles repo
            # Pandoc Markdown extensions:
            , yaml-metadata-block ? true
            , citeproc ? true
            , tex-math-dollars ? true
            , raw-tex ? true
            , multiline-tables ? true
            # pandoc-lua-filters to apply:
            , abstract-to-meta ? true
            , pagebreak ? true
            , pandoc-crossref ? true
            , cito ? true
            }:
            let
              pandoc-markdown-with-extensions = 
                "markdown"
                + (if yaml-metadata-block then "+yaml_metadata_block" else "")
                + (if citeproc then "+citations" else "")
                + (if tex-math-dollars then "+tex_math_dollars" else "")
                + (if raw-tex then "+raw_tex" else "")
                + (if multiline-tables then "+multiline_tables" else "")
              ;
              pandoc-lua-filters-path = "${pkgs.pandoc-lua-filters}/share/pandoc/filters";
              pandoc-filters = 
                ""
                + (if abstract-to-meta then " --lua-filter=${pandoc-lua-filters-path}/abstract-to-meta.lua" else "")
                + (if pagebreak then " --lua-filter=${pandoc-lua-filters-path}/pagebreak.lua" else "")
                + (if cito then " --lua-filter=${pandoc-lua-filters-path}/cito.lua" else "")
                + (if pandoc-crossref then " --filter=${pkgs.haskellPackages.pandoc-crossref}/bin/pandoc-crossref" else "")
                + (if citeproc then " --citeproc" else "")
              ;
            in
            pkgs.stdenv.mkDerivation {
              name = default name (builtins.baseNameOf src);
              # TODO: merge src with inputs here.
              inherit src;
              buildInputs = [
                pkgs.librsvg # requried to including svg images
                (pkgs.texlive.combine { inherit (pkgs.texlive) scheme-context; })
              ];
              FONTCONFIG_FILE = pkgs.makeFontsConf {fontDirectories = []; };
              installPhase = ''
                for input in $src/* ${inputs}/*; do
                  cp --recursive $input .
                done
                ${pkgs.pandoc}/bin/pandoc \
                  --from=${pandoc-markdown-with-extensions} \
                  ${pandoc-filters} \
                  --csl=${citation-style-language-styles}/${csl-style}.csl \
                  --pdf-engine=context \
                  --to=${output-format} \
                  --output=$out \
                  ${main}
              '';
            };
        };

        defaultPackage = lib.markdown-document {
          src = ./markdown-document-example;
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    );
}

# nix-channel --update; nix-env -iA nixpkgs.nix nixpkgs.cacert; systemctl daemon-reload; systemctl restart nix-daemon
