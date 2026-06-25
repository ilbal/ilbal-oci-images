{ stdenv
, lib
, clang
, fetchFromGitHub
, postgresql
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pg_accumulator";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "Treedo";
    repo = "pg_accumulator";
    rev = "v${finalAttrs.version}";
    hash = "sha256-9BcNu16tSWuVlrcrJTi1fB9qs6csIw2KR++tq70KYAg=";
  };

  nativeBuildInputs = [
    clang
    postgresql.pg_config
  ];
  buildInputs = [ postgresql ];

  installFlags = [ "DESTDIR=${placeholder "out"}" ];

  # PGXS installs into $out/nix/store/<pg-hash>/... — move files to $out.
  # Handles both directories and stray files (see ogr_fdw for the install-exe bug).
  postInstall = ''
    if [[ -d "$out${postgresql}" ]]; then
      for entry in "$out${postgresql}"/*; do
        base=$(basename "$entry")
        if [[ -d "$entry" ]]; then
          mv "$entry" "$out/"
        elif [[ -f "$entry" ]]; then
          mkdir -p "$out/$base"
          mv "$entry" "$out/$base/"
        fi
      done
      rm -r "$out${postgresql}"
    fi
  '';

  meta = {
    description = "Accumulation registers for balance and turnover tracking in PostgreSQL";
    homepage = "https://github.com/Treedo/pg_accumulator";
    license = lib.licenses.postgresql;
    platforms = postgresql.meta.platforms;
    maintainers = [ ];
  };
})
