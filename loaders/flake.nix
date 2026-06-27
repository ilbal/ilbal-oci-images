{
  description = "OCI image with data-loading tools for ilbal PostgreSQL images";

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

        dbcrossbar = pkgs.stdenv.mkDerivation {
          pname = "dbcrossbar";
          version = "1.1.0-pre.1";
          src = pkgs.fetchzip {
            url = "https://github.com/dbcrossbar/dbcrossbar/releases/download/v1.1.0-pre.1/dbcrossbar_1.1.0-pre.1_x86_64-unknown-linux-musl.zip";
            hash = "sha256-jG5MXlGbwhcijgghOErdgT0HJh7jabom1FIJvJoWOkU=";
          };
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/bin
            for f in $src/*; do
              cp "$f" $out/bin/
            done
            chmod 755 $out/bin/*
          '';
        };

        geocode-csv = pkgs.stdenv.mkDerivation {
          pname = "geocode-csv";
          version = "1.4.0";
          src = pkgs.fetchzip {
            url = "https://github.com/faradayio/geocode-csv/releases/download/v1.4.0/geocode-csv_1.4.0_x86_64-unknown-linux-musl.zip";
            hash = "sha256-OzIOOJbzdgafqHbfRh31hw6+KQTHyaeAohBLHqkTwSs=";
          };
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/bin
            for f in $src/*; do
              cp "$f" $out/bin/
            done
            chmod 755 $out/bin/*
          '';
        };

        pgferry = pkgs.stdenv.mkDerivation {
          pname = "pgferry";
          version = "6.0.0";
          src = pkgs.fetchurl {
            url = "https://github.com/Limetric/pgferry/releases/download/v6.0.0/pgferry-linux-amd64";
            hash = "sha256-4Hkwty51D31WxE7w97+dK2YXGHLo9ShEPxDAdZdZ5GQ=";
          };
          dontUnpack = true;
          installPhase = ''
            install -Dm755 $src $out/bin/pgferry
          '';
        };

        makeCsvTool =
          {
            name,
            version,
            hash,
          }:
          pkgs.stdenv.mkDerivation {
            pname = name;
            inherit version;
            src = pkgs.fetchzip {
              url = "https://github.com/faradayio/csv-tools/releases/download/${name}_v${version}/${name}_${version}_x86_64-unknown-linux-musl.zip";
              inherit hash;
            };
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/bin
              for f in $src/*; do
                cp "$f" $out/bin/
              done
              chmod 755 $out/bin/*
            '';
          };

        scrubcsv = makeCsvTool {
          name = "scrubcsv";
          version = "1.1.1";
          hash = "sha256-1pD+UtYqt5vhmMTVPoGGckXHa7/y9QhraidT4Y16ZVk=";
        };
        catcsv = makeCsvTool {
          name = "catcsv";
          version = "1.0.1";
          hash = "sha256-kr/mTZj3g4x9lu9BnIV/vicphB3GAKQorOXNDZ/UL7w=";
        };
        fixed2csv = makeCsvTool {
          name = "fixed2csv";
          version = "1.0.1";
          hash = "sha256-vW0EMalUUrGGrMlgXdmqQHWZCc4ieJUpxhAPpL6Pda8=";
        };
        geochunk = makeCsvTool {
          name = "geochunk";
          version = "1.0.1";
          hash = "sha256-oGVa88JoJ46ajgQXuCpirq+NAiTT4Tu36gpj2piQijE=";
        };
        hashcsv = makeCsvTool {
          name = "hashcsv";
          version = "1.0.3";
          hash = "sha256-RCyi9Qf8T+/j+SEU3MFM26rzHb8BkKuZhaqwfIoEqJc=";
        };

        allPkgs = with pkgs; [
          bash
          busybox
          coreutils
          curl
          gdal
          gnugrep
          gnused
          proj
          gzip
          jq
          less
          xz.bin
          zstd.bin
          dbcrossbar
          geocode-csv
          pgferry
          scrubcsv
          catcsv
          fixed2csv
          geochunk
          hashcsv
        ];

        mkFlattenLoop = builtins.concatStringsSep " \\\n  " (map (p: "${p}") allPkgs);

        runtime =
          pkgs.runCommand "runtime"
            {
              buildInputs = [
                pkgs.patchelf
                pkgs.binutils
              ];
            }
            ''
              set -euo pipefail

              mkdir -p "$out"

              for pkg in \
                ${mkFlattenLoop}; do
                cp -rL --no-preserve=mode,ownership,timestamps "$pkg"/* "$out/"
              done

              mkdir -p "$out/bin"
              cp -L "${pkgs.busybox}/bin/busybox" "$out/bin/"
              ln -sf busybox "$out/bin/vi"

              rm -rf "$out/include"
              rm -rf "$out/nix"
              rm -rf "$out/share/doc"
              rm -rf "$out/share/man"
              rm -rf "$out/share/info"
              rm -rf "$out/man"
              find "$out" -name "*.a" -delete
              find "$out" -name "*.la" -delete
              find "$out" -name "*.pc" -delete

              cd "$out"

              find . -type f -exec file {} + | grep ELF | cut -d: -f1 > /tmp/elfs

              echo -n > /tmp/rpath_dirs
              echo -n > /tmp/done_elfs

              collect_libs() {
                while read -r elf; do
                  grep -qxF "$elf" /tmp/done_elfs 2>/dev/null && continue
                  echo "$elf" >> /tmp/done_elfs
                  rpath=$(patchelf --print-rpath "$elf" 2>/dev/null) || continue
                  for dir in $(
                    echo "$rpath" | tr ':' '\n' | while read -r d; do
                      realpath "$d" 2>/dev/null || true
                    done
                  ); do
                    grep -qxF "$dir" /tmp/rpath_dirs 2>/dev/null && continue
                    echo "$dir" >> /tmp/rpath_dirs
                    mkdir -p lib
                    for libfile in "$dir"/lib*.so* "$dir"/ld*.so*; do
                      [ -f "$libfile" ] && cp -L "$libfile" lib/
                    done 2>/dev/null || true
                  done
                done
              }

              collect_libs < /tmp/elfs

              while true; do
                echo -n > /tmp/new_elfs
                find lib -maxdepth 1 -name "*.so*" -type f | while read -r f; do
                  abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
                  if ! grep -qxF "$abs" /tmp/done_elfs 2>/dev/null && file "$f" 2>/dev/null | grep -q ELF; then
                    echo "$abs"
                  fi
                done >> /tmp/new_elfs 2>/dev/null || true
                [ -s /tmp/new_elfs ] || break
                sort -u /tmp/new_elfs | collect_libs
              done

              find . -type d -exec chmod 755 {} \;
              find . -type f -exec chmod 644 {} \;
              find lib -type f -exec chmod 755 {} \;
              find bin -type f -exec chmod 755 {} \;

              find . -type f -exec file {} + | grep ELF | cut -d: -f1 > /tmp/elfs2
              while read -r f; do
                case "$(basename "$f")" in *ld-linux*) continue;; esac
                file "$f" | grep -q "dynamically linked" || continue
                patchelf --set-rpath '$ORIGIN/../lib' "$f" 2>/dev/null || true
              done < /tmp/elfs2

              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                file "$f" | grep -q "dynamically linked" || continue
                patchelf --print-needed "$f" 2>/dev/null | while read -r needed; do
                  case "$needed" in /nix/store/*)
                    soname=$(basename "$needed")
                    [ -f "lib/$soname" ] && patchelf --replace-needed "$needed" "$soname" "$f"
                  esac
                done
              done

              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                interp=$(patchelf --print-interpreter "$f" 2>/dev/null) || continue
                [ -z "$interp" ] && continue
                ldname=$(basename "$interp")
                if [ -f "lib/$ldname" ]; then
                  patchelf --set-interpreter "/lib/$ldname" "$f"
                fi
              done

              find . -name ".*-wrapped" -type f | while read -r wrapped; do
                dir="$(dirname "$wrapped")"
                base="$(basename "$wrapped")"
                name="''${base#.}"
                name="''${name%-wrapped}"
                [ -f "$dir/$name" ] && cp -f "$wrapped" "$dir/$name"
              done

              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | xargs -r strip --strip-unneeded 2>/dev/null || true
            '';

        image-root = pkgs.runCommand "image-root" { } ''
          mkdir -p $out/etc
          echo "root:x:0:0:root:/root:/bin/sh"  > $out/etc/passwd
          echo "root:x:0:"                       > $out/etc/group
          echo " "                               > $out/etc/nsswitch.conf
          install -D -m 0555 ${./entrypoint.sh} $out/entrypoint.sh
        '';

        version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./.version);

        image = pkgs.dockerTools.streamLayeredImage {
          name = "ilbal-postgresql-loaders-${version}";
          tag = "latest";
          created = "now";

          contents = [ ];
          includeStorePaths = false;

          extraCommands = ''
            cp -rL --no-preserve=mode,ownership,timestamps ${runtime}/. ./
            cp -rL --no-preserve=mode,ownership,timestamps ${image-root}/. ./
          '';

          fakeRootCommands = ''
            find . -type d -exec chmod 755 {} \;
            find . -type f -exec chmod 644 {} \;
            if [ -d bin ]; then find bin -type f -exec chmod 755 {} \; ; fi
            if [ -d lib ]; then find lib -type f -exec chmod 755 {} \; ; fi
            if [ -f entrypoint.sh ]; then chmod 555 entrypoint.sh; fi
          '';

          config = {
            Entrypoint = [ "/entrypoint.sh" ];
            Cmd = [ "--help" ];
              Env = [
                "PAGER=less"
                "GDAL_DATA=/share/gdal"
                "PROJ_LIB=/share/proj"
              ];
            User = "0";
          };
        };

      in
      {
        packages.default = image;
      }
    );
}
