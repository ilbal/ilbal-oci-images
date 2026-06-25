{
  stdenv,
  clang,
  fetchFromGitHub,
  lib,
  postgresql,
  gdal,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ogr_fdw";
  version = "1.1.8";

  src = fetchFromGitHub {
    owner = "pramsey";
    repo = "pgsql-ogr-fdw";
    tag = "v${finalAttrs.version}";
    hash = "sha256-9U7pNOffUQUvPpxG2DsWDXKcq7Y0LRsvnJ0fShF5OrI=";
  };

  nativeBuildInputs = [
    clang
    postgresql.pg_config
    gdal
  ];
  buildInputs = [
    postgresql
    gdal
  ];

  installFlags = [ "DESTDIR=${placeholder "out"}" ];

  # PGXS installs into $out/nix/store/<pg-hash>/... — move files to $out.
  # The Makefile's install-exe target creates a FILE named "bin" (the ogr_fdw_info
  # binary) instead of a bin/ directory.  Handle both cases: directories are
  # moved as-is; files (the ogr_fdw_info binary stored as "bin") are renamed.
  postInstall = ''
    if [[ -d "$out${postgresql}" ]]; then
      for entry in "$out${postgresql}"/*; do
        base=$(basename "$entry")
        if [[ -d "$entry" ]]; then
          mv "$entry" "$out/"
        elif [[ -f "$entry" ]]; then
          mkdir -p "$out/$base"
          mv "$entry" "$out/$base/ogr_fdw_info"
        fi
      done
      rm -r "$out${postgresql}"
    fi
  '';

  meta = {
    description = "PostgreSQL foreign data wrapper for OGR/GDAL";
    homepage = "https://github.com/pramsey/pgsql-ogr-fdw";
    license = lib.licenses.mit;
    platforms = postgresql.meta.platforms;
    maintainers = [ ];
  };
})
