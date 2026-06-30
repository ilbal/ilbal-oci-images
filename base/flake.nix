{
  description = "Shared Python+GDAL base image for ilbal OCI images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./.version);

        python3 = pkgs.python3.withPackages (ps: [ ps.numpy ]);
        gdal = pkgs.gdalMinimal;
        proj = pkgs.proj;

        # Full runtime closure of everything we need at nix store paths.
        closureInfo = pkgs.closureInfo {
          rootPaths = [
            python3
            gdal
            proj
          ];
        };

        image = pkgs.dockerTools.buildImage {
          name = "ilbal-python-gdal-base-${version}";
          tag = "latest";
          created = "now";

          extraCommands = ''
            # Copy every store path in the closure at its exact location.
            # This makes the nix store paths resolvable inside the image,
            # which is needed by Python shebangs and site.addsitedir calls
            # in the GDAL wrapper scripts.
            for p in $(cat ${closureInfo}/store-paths); do
              basename=$(basename "$p")
              mkdir -p "nix/store/$basename"
              cp -r --preserve=links --no-preserve=mode,ownership,timestamps \
                "$p/" "nix/store/$basename/"
            done

            # Fix permissions.
            find . -type d -exec chmod 755 {} \;
            find . -type f -exec chmod 644 {} \;
            find nix -type f -perm -0100 -exec chmod 755 {} \; 2>/dev/null || true
          '';

          config = {
            Env = [
              "GDAL_DATA=${gdal}/share/gdal"
              "PROJ_LIB=${proj}/share/proj"
            ];
          };
        };
      in
      {
        packages = {
          inherit image;
          python-gdal-base = image;
          default = image;
        };
      }
    );
}
