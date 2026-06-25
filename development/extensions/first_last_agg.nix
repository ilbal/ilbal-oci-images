{ pgxsExtension, fetchFromGitHub, lib }:

pgxsExtension {
  pname = "first_last_agg";
  version = "0.1.4";
  src = fetchFromGitHub {
    owner = "wulczer";
    repo = "first_last_agg";
    rev = "v0.1.4";
    hash = "sha256-b+XFur31MxQxyJxGjg5PB9QdXAgn0FjIZEu/ESRlIog=";
  };
  meta = {
    description = "first() and last() aggregate functions for PostgreSQL";
    homepage = "https://github.com/wulczer/first_last_agg";
    license = lib.licenses.postgresql;
    maintainers = [ ];
  };
}
