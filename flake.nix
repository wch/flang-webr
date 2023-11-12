{
  description = "flang patched for webR";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    # Use this commit to get Emscripten 3.1.45
    # See https://www.nixhub.io/packages/emscripten
    nixpkgs-emscripten.url =
      "github:NixOS/nixpkgs/75a52265bda7fd25e06e3a67dee3f0354e73243c";
  };

  outputs = { self, nixpkgs, nixpkgs-emscripten }:
    let
      allSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # Helper to provide system-specific attributes
      forAllSystems = f:
        nixpkgs.lib.genAttrs allSystems (system:
          f {
            pkgs = import nixpkgs { inherit system; };
            pkgs-emscripten = import nixpkgs-emscripten { inherit system; };
            inherit system;

            flang-source = nixpkgs.legacyPackages.${system}.fetchgit {
              url = "https://github.com/lionel-/f18-llvm-project";
              # This is the tip of the fix-webr branch.
              rev = "800f6764698d171beb00037aac6f570ab8c317d3";
              hash = "sha256-t5nLm58sBDSVxf4U+PFfwB8Caz7ra872QxiCaqqWaOw=";
            };
          });

    in {
      packages = forAllSystems ({ pkgs, pkgs-emscripten, flang-source, ... }: {
        default = pkgs.stdenv.mkDerivation {
          name = "flang-webr";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            git
            cacert # Needed for git clone to work on https repos
            cmake
            zlib
            libxml2
            python3
          ];

          propagatedNativeBuildInputs = [ pkgs-emscripten.emscripten ];

          # It would be faster to do an ln -s instead of cp -R, but I think the
          # cmake configure step tries to write to that directory, so it fails.
          postUnpack = ''
            # ln -s ${flang-source} $sourceRoot/f18-llvm-project
            cp -R ${flang-source} $sourceRoot/f18-llvm-project
            chmod -R u+w $sourceRoot/f18-llvm-project
          '';

          # The automatic configuration by stdenv.mkDerivation tries to do some
          # cmake configuration, which causes the build to fail.
          dontConfigure = true;

          buildPhase = ''
            if [ ! -d $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version} ]; then
              cp -R ${pkgs-emscripten.emscripten}/share/emscripten/cache/ $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
              chmod u+rwX -R $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
            fi
            export EM_CACHE=$(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
            echo emscripten cache dir: $EM_CACHE

            make WEBR_ROOT=webr NUM_CORES=$NIX_BUILD_CORES
          '';

          installPhase = ''
            make WEBR_ROOT=webr install
            mkdir -p $out
            cp -r webr $out
          '';
        };
      });

      # Development environment output
      devShells = forAllSystems ({ pkgs, pkgs-emscripten, system, ... }: {
        default = pkgs.mkShell {

          # Get the nativeBuildInputs from packages.default
          inputsFrom = [ self.packages.${system}.default ];

          # Any additional Nix packages provided in the environment
          packages = with pkgs; [ ];

          # This is a workaround for nix emscripten cache directory not being
          # writable. Borrowed from:
          # https://discourse.nixos.org/t/improving-an-emscripten-yarn-dev-shell-flake/33045
          # Issue at https://github.com/NixOS/nixpkgs/issues/139943
          #
          # Also note that `nix develop` must be run in the top-level directory
          # of the project; otherwise this script will create the cache dir
          # inside of the current working dir. Currently there isn't a way to
          # the top-level dir from within this file, but there is an open issue
          # for it. After that issue is fixed and the fixed version of nix is in
          # widespread use, we'll be able to use
          # https://github.com/NixOS/nix/issues/8034
          shellHook = ''
            if [ ! -d $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version} ]; then
              cp -R ${pkgs-emscripten.emscripten}/share/emscripten/cache/ $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
              chmod u+rwX -R $(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
            fi
            export EM_CACHE=$(pwd)/.emscripten_cache-${pkgs-emscripten.emscripten.version}
            echo emscripten cache dir: $EM_CACHE
          '';
        };
      });
    };
}
