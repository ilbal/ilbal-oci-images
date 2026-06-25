{
  pgxsExtension,
  fetchFromGitHub,
  lib,
}:

pgxsExtension {
  pname = "extra_window_functions";
  version = "1.0";
  src = fetchFromGitHub {
    owner = "xocolatl";
    repo = "extra_window_functions";
    rev = "v1.0";
    hash = "sha256-Io0jdQmkuzegGQutRBsY9UCjCT1jJs+wPrwicyW/vNg=";
  };
  meta = {
    description = "Extra window functions for PostgreSQL (lead/lag/nth_value ignore nulls, flip_flop)";
    homepage = "https://github.com/xocolatl/extra_window_functions";
    license = lib.licenses.postgresql;
    maintainers = [ ];
  };
}
