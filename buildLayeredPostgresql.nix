{
  description = "Minimal PostgreSQL OCI image with PostGIS and pgRouting";

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

        # Function: takes a postgresql-with-extensions package and produces a docker image
        buildPgImage =
          pg:

          let
            pg-runtime =
              pkgs.runCommand "pg-runtime"
                {
                  buildInputs = [ pkgs.patchelf ];
                }
                ''
                  set -euo pipefail

                  mkdir -p "$out"

                  # Flatten PG + extensions + utilities into a single $out directory.
                  # This avoids each Nix store path becoming a separate Docker layer,
                  # reducing the final image's layer count and size.
                  for pkg in ${pg} ${pkgs.bash} ${pkgs.coreutils} ${pkgs.su-exec} ${pkgs.findutils} ${pkgs.gzip} ${pkgs.xz.bin} ${pkgs.zstd.bin}; do
                    cp -rL --no-preserve=mode,ownership,timestamps "$pkg"/* "$out/"
                  done

                  # Strip build-time artifacts before library discovery.
                  # These are pulled into the closure via postgresql-*-dev
                  # (propagated by extensions) but are unneeded at runtime.
                  # Removing them significantly reduces the final Docker image size.
                  rm -rf "$out/include"
                  rm -rf "$out/nix-support"
                  rm -rf "$out/share/doc"
                  rm -rf "$out/share/man"
                  rm -rf "$out/share/info"
                  rm -rf "$out/man"
                  find "$out" -name "*.a" -delete
                  find "$out" -name "*.la" -delete
                  find "$out" -name "*.pc" -delete

                  cd "$out"

                  # Find all ELF binaries under $out and list them in /tmp/elfs for further processing
                  find . -type f -exec file {} + | grep ELF | cut -d: -f1 > /tmp/elfs

                  # Read every ELF's embedded RPATH, resolve the Nix store
                  # directories it references, and copy all .so files from
                  # those directories into lib/. Tracks seen ELFs and
                  # directories in /tmp files to avoid duplicate work.
                  echo -n > /tmp/rpath_dirs    # initialized empty; collect_libs fills with scanned directories
                  echo -n > /tmp/done_elfs    # initialized empty; collect_libs fills with processed ELFs

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

                  # Repeatedly discover transitive .so dependencies:
                  # .so files copied in the first pass may have their own RPATHs
                  # pointing to more .so files. Loop until no new .so appear.
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

                  # Fix permissions before patchelf runs:
                  # collect_libs copies with original store mode (0444),
                  # so .so files are read-only. patchelf needs write access.
                  find . -type d -exec chmod 755 {} \;
                  find . -type f -exec chmod 644 {} \;
                  find lib -type f -exec chmod 755 {} \;
                  find bin -type f -exec chmod 755 {} \;

                  # Rewrite RPATH from absolute Nix store paths to relative $ORIGIN/../lib
                  # $ORIGIN is expanded at runtime to the dir containing the ELF,
                  # so ./bin/postgres looks for .so files in ./lib/
                  # IMPORTANT: skip ld-linux* by filename — patchelf corrupts
                  # the dynamic linker, causing every loaded binary to segfault.
                  # Also: do NOT grep -v 'ld-linux' on the `file` output, because
                  # `file` emits "interpreter /lib/ld-linux-x86-64.so.2" for every
                  # dynamically linked ELF, which would skip ALL binaries.
                  find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                    case "$(basename "$f")" in *ld-linux*) continue;; esac
                    patchelf --set-rpath '$ORIGIN/../lib' "$f" 2>/dev/null || true
                  done

                  # Fix the dynamic linker (interpreter) path in every ELF binary.
                  # The original path points to /nix/store/.../ld-linux.so.2,
                  # which doesn't exist in the Docker image. Rewrite it to
                  # /lib/<ld-filename> so the kernel can find the loader at runtime.
                  find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                    interp=$(patchelf --print-interpreter "$f" 2>/dev/null) || continue
                    [ -z "$interp" ] && continue
                    ldname=$(basename "$interp")
                    if [ -f "lib/$ldname" ]; then
                      patchelf --set-interpreter "/lib/$ldname" "$f"
                    fi
                  done

                  # Replace Nix wrapper ELFs with their real .wrapped counterparts.
                  # Nix's makeWrapper creates tiny ELF binaries (postgres, initdb)
                  # that embed an absolute Nix store path to the real binary
                  # (e.g. /nix/store/.../bin/.postgres-wrapped).  Since the Nix
                  # store doesn't exist in the Docker image, these wrappers fail
                  # with exit 255.  The .*-wrapped files are the real binaries
                  # and are already in the right directory — just overwrite the
                  # wrapper with the real binary.
                  # NOTE: ''${...} escapes Nix string interpolation so the
                  # shell sees ${base#.} / ${name%-wrapped} at runtime.
                  find . -name ".*-wrapped" -type f | while read -r wrapped; do
                    dir="$(dirname "$wrapped")"
                    base="$(basename "$wrapped")"
                    name="''${base#.}"
                    name="''${name%-wrapped}"
                    [ -f "$dir/$name" ] && cp -f "$wrapped" "$dir/$name"
                  done

                '';

            # Creates the filesystem skeleton for the Docker image:
            # user/group database, nsswitch, and the entrypoint script.
            image-root = pkgs.runCommand "image-root" { } ''
              mkdir -p $out/etc $out/var/lib/postgresql
              echo "root:x:0:0:root:/root:/bin/sh"     > $out/etc/passwd
              echo "postgres:x:999:999:postgres:/var/lib/postgresql:/bin/sh" >> $out/etc/passwd
              echo "root:x:0:"                          > $out/etc/group
              echo "postgres:x:999:"                   >> $out/etc/group
              echo " "                                  > $out/etc/nsswitch.conf
              install -D -m 0555 ${./entrypoint.sh} $out/entrypoint.sh
            '';

          in
          pkgs.dockerTools.buildLayeredImage {
            name = "ilbal-pg${pg.version}";
            tag = "layered";
            created = "now";

            fakeRootCommands = ''
              cp -r ${pg-runtime}/* /
              cp -r ${image-root}/* /
            '';

            config = {
              Cmd = [ "postgres" ];
              Entrypoint = [ "/entrypoint.sh" ];
              Env = [ "PGDATA=/var/lib/postgresql/data" ];
              User = "0";
              WorkingDir = "/var/lib/postgresql";
            };
          };

      in
      {
        packages =
          let
            # Any postgres extension in nixpkgs can be added inside withPackages
            pg16 = buildPgImage (
              pkgs.postgresql_16.withPackages (
                extensions: with extensions; [
                  postgis
                  pgrouting
                ]
              )
            );
            pg17 = buildPgImage (
              pkgs.postgresql_17.withPackages (
                extensions: with extensions; [
                  postgis
                  pgrouting
                ]
              )
            );
            pg18 = buildPgImage (
              pkgs.postgresql_18.withPackages (
                extensions: with extensions; [
                  postgis
                  pgrouting
                ]
              )
            );
          in
          {
            inherit pg16 pg17 pg18;
            default = pg18;
          };
      }
    );
}
