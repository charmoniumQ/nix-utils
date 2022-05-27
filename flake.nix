{
  description = "Flake utils demo";

  inputs = {
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
      # TODO: expose CSL-styles in the flake
      citation-style-language-styles = pkgs.stdenv.mkDerivation {
        name = "citation-style-language-styles";
        src = builtins.fetchGit {
          url = "https://github.com/citation-style-language/styles.git";
          ref = "master";
          rev = "3f6c407b2350b4ffdca96e2663bf4126b1ec5f4d";
        };
        installPhase = ''
          mkdir $out
          cp -r $src/* $out
        '';
      };
      markdown-document = { src, document }:
        # TODO: infer document if not provided
        # TODO: user-specify pdf-engine
        # TODO: eachDefaultSystem
        pkgs.stdenv.mkDerivation {
          name = "markdown-document-${document}";
          inherit src;
          buildInputs = [
            # TODO: allow overlay of pandoc and texlive
            pkgs.pandoc
            (
              pkgs.texlive.combine {
                inherit (pkgs.texlive)
                  scheme-basic
                  xcolor
                  savetrees
                  xkeyval
                  microtype
                  etoolbox
                  # scheme-context
                # TODO: add user-input texlive packages here.
                ;
              }
            )
          ];
          # TODO: lua filters
          # TODO: user specify output type
          installPhase = ''
          mkdir $out
          env --chdir=$src -- \
                pandoc \
                  --from=markdown+yaml_metadata_block+citations+tex_math_dollars+raw_tex \
                  --citeproc \
                  --pdf-engine=pdflatex \
                  --output=$out/${document}.pdf \
                  ${document}.md
              '';
        };
      main = markdown-document {
        src = ./markdown-document-example;
        document = "main";
      };
    in {
      defaultPackage."x86_64-linux" = pkgs.stdenv.mkDerivation {
        name = "markdown-document-test";
        src = ./.;
        buildInputs = [main];
        installPhase = ''
            mkdir $out
            ls ${main} > $out
          '';
      };
    };
}
