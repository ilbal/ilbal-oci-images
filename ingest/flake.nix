{
  description = "OCI image with data-loading tools for ilbal PostgreSQL images";

  inputs = {
    base.url = "path:../base";
    nixpkgs.follows = "base/nixpkgs";
    flake-utils.follows = "base/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      base,
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
                pkgs.rdfind
              ];
              baseRuntime = base.packages.${system}.base-runtime;
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
              for applet in \
                sh vi ls cat cp mv rm mkdir rmdir touch ln chmod chown chgrp \
                head tail more less grep wc sort cut tr uniq tee diff cmp strings fold expand fmt paste od hexdump \
                find xargs pwd env which echo printf sleep true false seq yes test basename dirname readlink id \
                ps kill pgrep pkill pidof df du date dmesg uname hostname \
                md5sum sha1sum sha256sum crc32 \
                wget ping ping6 nc nslookup tar gunzip zcat \
                ; do
                ln -sf busybox "$out/bin/$applet"
              done

              rm -rf "$out/include"
              rm -rf "$out/nix"
              rm -rf "$out/share/doc"
              rm -rf "$out/share/man"
              rm -rf "$out/share/info"
              rm -rf "$out/man"
              rm -rf "$out/lib/jni"
              rm -rf "$out/lib/cmake"
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

              # Fix gdal-config shebang to point to /bin/sh instead of nix store.
              if [ -f bin/gdal-config ]; then
                sed -i '1s|^#!.*|#!/bin/sh|' bin/gdal-config
              fi

              # Consolidate duplicate .so files into symlinks.
              # For each family like libfoo.so, libfoo.so.1, libfoo.so.1.0.0,
              # keep the most-versioned real file and symlink the rest.
              find lib -maxdepth 1 -type f -name "*.so*" | while read -r f; do
                base=$(basename "$f")
                stem=''${base%%.so*}
                # Find the most-versioned member of this family
                latest=$(ls -1 lib/"$stem".so* 2>/dev/null | sort -t. -k3,3n -k4,4n -k5,5n | tail -1)
                [ -z "$latest" ] && continue
                # latest is already the real file, skip it
                [ "$f" = "$latest" ] && continue
                # If file is identical (by checksum), replace with symlink
                if cmp -s "$f" "$latest"; then
                  rm -f "$f"
                  ln -sf "$(basename "$latest")" "$f"
                fi
              done

              # Second pass: find any remaining duplicate .so files across
              # different stem families and deduplicate with hard links.
              ${pkgs.rdfind}/bin/rdfind -makehardlinks true lib/ 2>/dev/null || true

              # Dedup summary.
              echo "=== dedup summary ==="
              total=$(find lib -name "*.so*" -type f | wc -l)
              unique=$(find lib -name "*.so*" -type f -exec md5sum {} + | awk '{print $1}' | sort -u | wc -l)
              echo "lib/*.so* files: $total total, $unique unique content"

              # Remove files that duplicate the base layer.
              echo "=== removing base duplicates from bin/ ==="
              if [ -d "$baseRuntime/bin" ]; then
                n=0
                for f in "$out"/bin/*; do
                  [ -f "$f" ] || continue
                  name=$(basename "$f")
                  [ -f "$baseRuntime/bin/$name" ] || continue
                  echo "  removing (base duplicate): $name"
                  rm -f "$f"
                  n=$((n + 1))
                done
                echo "  removed $n files"
              fi
              rm -rf "$out/share/gdal" "$out/share/proj" "$out/share/locale"
              rm -rf "$out/lib"/python3.*
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
          name = "ilbal-ingest";
          tag = version;
          created = "2026-08-14T21:14:10Z";

          fromImage = base.packages.${system}.python-gdal-base;

          contents = [ ];
          includeStorePaths = false;

          extraCommands = ''
            cp -r --preserve=links --no-preserve=mode,ownership,timestamps ${runtime}/. ./
            cp -r --preserve=links --no-preserve=mode,ownership,timestamps ${image-root}/. ./
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
