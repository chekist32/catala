{
  inputs = {
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.opam-repository.follows = "opam-repository";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.follows = "opam-nix/nixpkgs";
  };
  outputs =
    {
      flake-utils,
      opam-nix,
      nixpkgs,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        devPackagesQuery = {
          # You can add "development" packages here. They will get added to the devShell automatically.
          ocaml-lsp-server = "*";
          # ocaml-lsp-server 1.26.x does not build with stdune >= 3.25: https://github.com/ocaml/ocaml-lsp/issues/2236#issuecomment-6853503695
          stdune = "3.24.2";
          ocamlformat = "*";
          merlin = "*";
          ocp-indent = "*";
          utop = "*";
          odoc = "*";
        };
        query = {
          ## You can force versions of certain packages here, e.g:
          ## - force the ocaml compiler to be taken from opam-repository:
          ocaml-base-compiler = "*";
          ## - or force the compiler to be taken from nixpkgs and be a certain version:
          # ocaml-system = "4.14.0";
          ## - or force ocamlfind to be a certain version:
          # ocamlfind = "1.9.2";
        };

        overlay = final: prev: {
          conf-ninja = prev.conf-ninja.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.ninja ];
          });
          catala = prev.catala.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              pkgs.ninja
              pkgs.makeWrapper
            ];
            postInstall = (old.postInstall or "") + ''
              OCAML_VERSION=$(ocamlc -version)
              OCAML_ROOT=$(mktemp -d)
              mkdir -p $OCAML_ROOT/lib
              ln -s "$(ocamlc -where)" $OCAML_ROOT/lib/ocaml
              ln -s $out/lib/ocaml/$OCAML_VERSION/site-lib/catala $OCAML_ROOT/lib/catala
              ln -s ${final.zarith}/lib/ocaml/$OCAML_VERSION/site-lib/zarith $OCAML_ROOT/lib/zarith
              touch $OCAML_ROOT/lib/findlib.conf

              PROJECT_DIR=$(mktemp -d)
              (cd $PROJECT_DIR && env -u OPAM_SWITCH_PREFIX OCAMLLIB=$OCAML_ROOT/lib/ocaml $out/bin/clerk start)

              mkdir -p $out/share/catala
              cp -r $PROJECT_DIR/_build/libcatala $out/share/catala/stdlib

              wrapProgram $out/bin/catala --set-default CATALA_STDLIB $out/share/catala/stdlib
            '';
          });
          # You can add overrides here
        };

        buildScope = query: (opam-nix.lib.${system}.buildOpamProject' { } ./. query).overrideScope overlay;
        scope = buildScope query;
        devScope = buildScope (devPackagesQuery // query);
      in
      {
        legacyPackages = scope;

        packages = {
          default = scope.catala;
          inherit (scope) catala catala-js;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            devScope.catala
            devScope.catala-js
            devScope.catala-proof
          ];
          # Packages from devPackagesQuery
          buildInputs = lib.attrValues (lib.intersectAttrs devPackagesQuery devScope) ++ [
            # You can add packages from nixpkgs here
            pkgs.inotify-tools
            pkgs.groff
            pkgs.obelisk
            pkgs.ninja
            pkgs.colordiff
            pkgs.pandoc
            pkgs.python3.pkgs.pygments
            pkgs.nodejs
          ];
        };
      }
    );
}
