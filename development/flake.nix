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

        # ---------------------------------------------------------------
        #  Read extension configuration from config.toml
        # ---------------------------------------------------------------
        cfg = builtins.fromTOML (builtins.readFile ./config.toml);

        # Extension configuration is under [extensions]:
        #   nixpkgs = [ ]  — simple extensions taken straight from nixpkgs
        #   [extensions.xxx]  — sub-tables for extensions needing extra config
        #                      (runtime_deps, dependencies, override)
        extCfg = cfg.extensions;
        nixpkgsExtNames = extCfg.nixpkgs or [ ];
        complexExtNames = builtins.attrNames (builtins.removeAttrs extCfg [ "nixpkgs" ]);
        extNames = pkgs.lib.unique (nixpkgsExtNames ++ complexExtNames);

        # Resolve a dotted or plain package name to a Nix package.
        # e.g. "xz.bin" -> pkgs.xz.bin, "bash" -> pkgs.bash
        getPkg =
          name:
          let
            parts = pkgs.lib.splitString "." name;
          in
          builtins.foldl' (acc: part: acc.${part}) pkgs parts;

        # Create a postgresql-with-extensions derivation for a given PG version.
        # Reads the extension list and any overrides from config.toml.
        # Custom extensions from ./extensions/*.nix are built against this PG version.
        mkPg =
          pg:
          let
            # PGXS extension builder — handles boilerplate for all custom
            # extensions that use PostgreSQL's PGXS build system.
            pgxsExtension =
              {
                pname,
                version,
                src,
                nativeBuildInputs ? [ ],
                buildInputs ? [ ],
                postInstall ? null,
                meta ? { },
                ...
              }:
              pkgs.stdenv.mkDerivation {
                inherit pname version src;

                nativeBuildInputs = [
                  pkgs.clang
                  pg.pg_config
                ]
                ++ nativeBuildInputs;
                buildInputs = [ pg ] ++ buildInputs;

                installFlags = [ "DESTDIR=${placeholder "out"}" ];

                postInstall =
                  if postInstall != null then
                    postInstall
                  else
                    ''
                      if [[ -d "$out${pg}" ]]; then
                        for entry in "$out${pg}"/*; do
                          base=$(basename "$entry")
                          if [[ -d "$entry" ]]; then
                            mv "$entry" "$out/"
                          elif [[ -f "$entry" ]]; then
                            mkdir -p "$out/$base"
                            mv "$entry" "$out/$base/"
                          fi
                        done
                        rm -r "$out${pg}"
                      fi
                    '';

                meta = meta // {
                  platforms = pg.meta.platforms;
                };
              };

            # Build each custom extension against this specific PG version.
            customExtFiles = builtins.readDir ./extensions;
            customExtNames = map (f: pkgs.lib.removeSuffix ".nix" f) (
              pkgs.lib.filter (f: customExtFiles.${f} == "regular" && pkgs.lib.hasSuffix ".nix" f) (
                builtins.attrNames customExtFiles
              )
            );
            buildCustomExt =
              name:
              let
                extFn = import (./extensions + "/${name}.nix");
                extFnArgs = builtins.functionArgs extFn;
                extCfg = cfg.extensions.${name} or { };
                depAttrs = builtins.mapAttrs (_name: pkg: getPkg pkg) (extCfg.dependencies or { });
              in
              # callPackage already filters autoArgs through functionArgs
              # (intersectAttrs), but it does NOT filter explicit args — those
              # are passed through '// args' unconditionally.  We apply the
              # same intersectAttrs treatment to our own explicit args so that
              # extensions don't have to declare bindings they don't use.
              pkgs.callPackage extFn (
                builtins.intersectAttrs extFnArgs (
                  {
                    inherit pgxsExtension;
                    postgresql = pg; # only kept if the extension declares it
                  }
                  // depAttrs
                )
              );
            customExtList = map (n: {
              name = n;
              value = buildCustomExt n;
            }) customExtNames;
            pgCustomExtensions = builtins.listToAttrs customExtList;
          in
          pg.withPackages (
            extensions:
            let
              allExtensions = extensions // pgCustomExtensions;
            in
            map (
              name:
              let
                extCfg = cfg.extensions.${name} or { };
                baseExt = allExtensions.${name};
              in
              if extCfg ? override then baseExt.override extCfg.override else baseExt
            ) extNames
          );

        # Collect all runtime dependency package names from every extension.
        allRuntimeDepNames = pkgs.lib.unique (
          pkgs.lib.flatten (map (name: cfg.extensions.${name}.runtime_deps or [ ]) extNames)
        );

        # Base packages that are always included in the image.
        basePkgNames = cfg.runtime_base.packages;

        # Every runtime package needed in the image (excluding busybox,
        # which is handled separately to avoid hard-link bloat).
        extraPkgNames = builtins.filter (n: n != "busybox") (allRuntimeDepNames ++ basePkgNames);

        # Build the shell loop string for flattening all package trees.
        mkFlattenLoop =
          pg:
          let
            extraPkgs = map getPkg extraPkgNames;
            allPkgs = [ pg ] ++ extraPkgs;
          in
          builtins.concatStringsSep " \\\n  " (map (p: "${p}") allPkgs);

        # -----------------------------------------------------------------
        #  Function: takes a postgresql-with-extensions package and
        #  produces a flattened, relocatable Docker/OCI image.
        # -----------------------------------------------------------------
        buildPgImage =
          pg:

          let
            pg-runtime =
              pkgs.runCommand "pg-runtime"
                {
                  buildInputs = [
                    pkgs.patchelf
                    pkgs.binutils
                  ];
                }
                ''
                  set -euo pipefail

                  mkdir -p "$out"

                  # Flatten PG + extensions + runtime deps into a single $out directory.
                  # This avoids each Nix store path becoming a separate Docker layer,
                  # reducing the final image's layer count and size.
                  for pkg in \
                    ${mkFlattenLoop pg}; do
                    cp -rL --no-preserve=mode,ownership,timestamps "$pkg"/* "$out/"
                  done

                  # Copy the busybox multi-call binary once (not the full package
                  # with ~400 hard-linked applets) and create a vi symlink.
                  # cp -rL above would break busybox's hard links into separate
                  # 1 MB copies, adding ~900 MB of bloat.
                  mkdir -p "$out/bin"
                  cp -L "${pkgs.busybox}/bin/busybox" "$out/bin/"
                  ln -sf busybox "$out/bin/vi"

                  # Strip build-time artifacts before library discovery.
                  # These are pulled into the closure via postgresql-*-dev
                  # (propagated by extensions) but are unneeded at runtime.
                  # Removing them significantly reduces the final Docker image size.
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

                  # Replace absolute Nix store NEEDED entries with bare sonames.
                  # e.g. libproj.so.25 has NEEDED /nix/store/.../libsqlite3.so
                  # instead of NEEDED libsqlite3.so.  The absolute path doesn't
                  # exist in the Docker image.  Since RPATH has already been
                  # rewritten to $ORIGIN/../lib, the dynamic linker resolves a
                  # bare soname against lib/ in the image.
                  find . -type f -exec file {} + | grep ELF | cut -d: -f1 | while read -r f; do
                    patchelf --print-needed "$f" 2>/dev/null | while read -r needed; do
                      case "$needed" in /nix/store/*)
                        soname=$(basename "$needed")
                        [ -f "lib/$soname" ] && patchelf --replace-needed "$needed" "$soname" "$f"
                      esac
                    done
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
                  # shell sees ''${base#.} / ''${name%-wrapped} at runtime.
                  find . -name ".*-wrapped" -type f | while read -r wrapped; do
                    dir="$(dirname "$wrapped")"
                    base="$(basename "$wrapped")"
                    name="''${base#.}"
                    name="''${name%-wrapped}"
                    [ -f "$dir/$name" ] && cp -f "$wrapped" "$dir/$name"
                  done

                  # Strip debug symbols from all ELF binaries.
                  # The originals remain untouched in the Nix store for debugging.
                  find . -type f -exec file {} + | grep ELF | cut -d: -f1 | xargs -r strip --strip-unneeded 2>/dev/null || true
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
          pkgs.dockerTools.streamLayeredImage {
            name = "ilbal-postgresql-${pg.version}";
            tag = "latest";
            created = "now";

            # Contents is empty — we copy real files via extraCommands below.
            # If we put store paths in `contents`, symlinkJoin creates symlinks
            # back to /nix/store, which would be broken when includeStorePaths=false.
            contents = [ ];

            # Do NOT include the Nix store closure in the image.
            # The flattened pg-runtime already has everything needed (bin, lib, etc.)
            # with relative RPATHs and a relocated interpreter — no Nix store required.
            includeStorePaths = false;

            # Copy real files into the layer (not symlinks).
            # pg-runtime and image-root outputs contain actual files because
            # their derivations use cp -rL (dereference).
            extraCommands = ''
              cp -rL --no-preserve=mode,ownership,timestamps ${pg-runtime}/. ./
              cp -rL --no-preserve=mode,ownership,timestamps ${image-root}/. ./
            '';

            # Reset permissions (the -L above strips the originals).
            fakeRootCommands = ''
              find . -type d -exec chmod 755 {} \;
              find . -type f -exec chmod 644 {} \;
              if [ -d bin ]; then find bin -type f -exec chmod 755 {} \; ; fi
              if [ -d lib ]; then find lib -type f -exec chmod 755 {} \; ; fi
              if [ -f entrypoint.sh ]; then chmod 555 entrypoint.sh; fi
            '';

            config = {
              Cmd = [ "postgres" ];
              Entrypoint = [ "/entrypoint.sh" ];
              Env = [
                "PGDATA=/var/lib/postgresql/data"
                "TERMINFO=/share/terminfo"
              ];
              User = "0";
              WorkingDir = "/var/lib/postgresql";
            };
          };

      in
      {
        packages =
          let
            pg16 = buildPgImage (mkPg pkgs.postgresql_16);
            pg17 = buildPgImage (mkPg pkgs.postgresql_17);
            pg18 = buildPgImage (mkPg pkgs.postgresql_18);
          in
          {
            inherit pg16 pg17 pg18;
            default = pg18;
          };
      }
    );
}
