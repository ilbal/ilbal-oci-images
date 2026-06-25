{ pgxsExtension, fetchFromGitHub, lib, postgresql }:

pgxsExtension {
  pname = "pg_currency";
  version = "0.0.5";
  src = fetchFromGitHub {
    owner = "adjust";
    repo = "pg-currency";
    rev = "1ecf649ab78d81971fa72d7c554ecccdc5b0f205";
    hash = "sha256-2lHSz/e2IoK3+H8XfHs319BztyRmsy8UxhRlsWTUFgI=";
  };
  meta = {
    description = "1-byte ISO 4217 currency code data type for PostgreSQL";
    homepage = "https://github.com/adjust/pg-currency";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
