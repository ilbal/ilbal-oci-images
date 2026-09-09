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

        python3 = pkgs.python3;
        gdal = pkgs.gdal;
        proj = pkgs.proj;
        numpy = pkgs.python3Packages.numpy;

        # Flatten + relocatability pipeline for the base runtime.
        base-runtime =
          pkgs.runCommand "base-runtime"
            {
              buildInputs = [
                pkgs.patchelf
                pkgs.binutils
              ];
            }
            ''
              set -euo pipefail

              # Log sizes for debugging.
              log_sizes() {
                echo "=== size report ($1) ==="
                du -sh "$out"/*/ 2>/dev/null | sort -rh || true
                du -sh "$out"/lib/*/ 2>/dev/null | sort -rh || true
              }

              trap 'log_sizes "at exit"' EXIT

              mkdir -p "$out"

              # Flatten python3, gdalMinimal, numpy, proj into $out.
              for pkg in \
                ${python3} \
                ${gdal} \
                ${numpy} \
                ${proj}; do
                cp -rL --no-preserve=mode,ownership,timestamps "$pkg"/* "$out/"
              done

              # Strip build artifacts before library discovery.
              rm -rf "$out/include"
              rm -rf "$out/nix"
              rm -rf "$out/nix-support"
              rm -f "$out/results.txt"
              rm -rf "$out/share/doc"
              rm -rf "$out/share/man"
              rm -rf "$out/share/info"
              rm -rf "$out/man"
              # Remove everything from share/ except what GDAL/PROJ need at runtime.
              find "$out/share" -mindepth 1 -maxdepth 1 ! -name gdal ! -name proj -exec rm -rf {} + 2>/dev/null || true
              find "$out" -name "*.a" -delete
              find "$out" -name "*.la" -delete
              find "$out" -name "*.pc" -delete
              # Prune Python stdlib bloat.
              rm -rf "$out/lib/python3.*/test"
              rm -rf "$out/lib/python3.*/ensurepip"
              rm -rf "$out/lib/python3.*/idlelib"
              rm -rf "$out/lib/python3.*/turtledemo"
              rm -rf "$out/lib/python3.*/lib2to3"
              rm -rf "$out/lib/python3.*/venv"
              # Deduplicate .pyc files — remove __pycache__ (stdlib already byte-compiled at build time).
              find "$out/lib/python3.*" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

              cd "$out"

              # Find all ELF binaries.
              find . -type f -exec file {} + | grep ELF | cut -d: -f1 > /tmp/elfs || true

              # Collect libraries from RPATHs.
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

              # Transitive .so pass.
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

              # Fix permissions before patchelf.
              find . -type d -exec chmod 755 {} \;
              find . -type f -exec chmod 644 {} \;
              find lib -type f -exec chmod 755 {} \;
              find bin -type f -exec chmod 755 {} \;

              # Rewrite RPATH to $ORIGIN/../lib.
              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                case "$(basename "$f")" in *ld-linux*) continue;; esac
                patchelf --set-rpath '$ORIGIN/../lib' "$f" 2>/dev/null || true
              done || true

              # Replace absolute NEEDED entries with bare sonames.
              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                patchelf --print-needed "$f" 2>/dev/null | while read -r needed; do
                  case "$needed" in /nix/store/*)
                    soname=$(basename "$needed")
                    [ -f "lib/$soname" ] && patchelf --replace-needed "$needed" "$soname" "$f"
                  esac
                done
              done || true

              # Fix interpreter.
              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                interp=$(patchelf --print-interpreter "$f" 2>/dev/null) || continue
                [ -z "$interp" ] && continue
                ldname=$(basename "$interp")
                if [ -f "lib/$ldname" ]; then
                  patchelf --set-interpreter "/lib/$ldname" "$f"
                fi
              done || true

              # Replace Nix wrapper ELFs with real .wrapped binaries.
              find . -name ".*-wrapped" -type f | while read -r wrapped; do
                dir="$(dirname "$wrapped")"
                base="$(basename "$wrapped")"
                name="''${base#.}"
                name="''${name%-wrapped}"
                [ -f "$dir/$name" ] && cp -f "$wrapped" "$dir/$name"
              done

              # Strip debug symbols.
              find . -type f -exec file {} + | grep ELF | cut -d: -f1 | xargs -r strip --strip-unneeded 2>/dev/null || true

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
            '';

        image = pkgs.dockerTools.buildLayeredImage {
          name = "ilbal-base";
          tag = version;
          created = "2026-08-14T21:04:48Z";

          # base-runtime is already flattened and relocatable — no Nix store
          # paths to include.  Prevent buildLayeredImage from pulling in the
          # store closure of base-runtime's build dependencies.
          contents = [ ];
          includeStorePaths = false;

          extraCommands = ''
            cp -ra ${base-runtime}/. ./
          '';

          config = {
            Env = [
              "PYTHONHOME=/"
              "GDAL_DATA=/share/gdal"
              "PROJ_LIB=/share/proj"
            ];
          };
        };
      in
      {
        packages = {
          inherit image base-runtime;
          python-gdal-base = image;
          default = image;
        };
      }
    );
}
