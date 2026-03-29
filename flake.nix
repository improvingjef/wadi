{
  description = "oasis: a Dune-free OCaml workspace toolbox";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem = f:
        nixpkgs.lib.genAttrs systems (system: f system (import nixpkgs { inherit system; }));
    in
    {
      packages = forEachSystem (system: pkgs:
        let
          version =
            if self ? rev then self.rev else "dirty";
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "oasis";
            inherit version;
            src = self;
            dontConfigure = true;
            nativeBuildInputs = [
              pkgs.bash
              pkgs.gnumake
              pkgs.ocamlPackages.findlib
              pkgs.ocamlPackages.ocaml
            ];
            buildPhase = ''
              runHook preBuild
              make release-artifacts
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              bash scripts/install_release_tree.sh \
                --package-root package \
                --binary _bootstrap/bin/oasis \
                --prefix "$out"
              runHook postInstall
            '';
          };
        });

      apps = forEachSystem (system: pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/oasis";
        };
      });

      devShells = forEachSystem (_system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.bash
            pkgs.gnumake
            pkgs.ocamlPackages.findlib
            pkgs.ocamlPackages.ocaml
          ];
        };
      });
    };
}
