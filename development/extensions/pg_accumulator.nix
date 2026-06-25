{ pgxsExtension, fetchFromGitHub, lib, postgresql }:

pgxsExtension {
  pname = "pg_accumulator";
  version = "1.2.0";
  src = fetchFromGitHub {
    owner = "Treedo";
    repo = "pg_accumulator";
    rev = "v1.2.0";
    hash = "sha256-9BcNu16tSWuVlrcrJTi1fB9qs6csIw2KR++tq70KYAg=";
  };
  meta = {
    description = "Accumulation registers for balance and turnover tracking in PostgreSQL";
    homepage = "https://github.com/Treedo/pg_accumulator";
    license = lib.licenses.postgresql;
    maintainers = [ ];
  };
}
