{
  description = "Shared CI and app packaging for slopsmith projects";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0bb2eedc20e4739f29e8045034f2828ad7054f8f";

  outputs =
    { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = self.packages.${system}.slop-app;
        slop-app = pkgs.stdenvNoCC.mkDerivation {
          name = "slop-app";
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            mkdir -p $out/bin $out/share
            cp bin/slop-app $out/bin/
            cp -R share/slop-app $out/share/
            wrapProgram $out/bin/slop-app --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.cargo-about ]}
          '';
        };
      };

      checks.${system}.shellcheck = pkgs.runCommand "shellcheck" { } ''
        ${pkgs.lib.getExe pkgs.shellcheck} ${./bin/slop-app}
        touch $out
      '';
    };
}
