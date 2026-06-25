{
  prebuiltPgrxExtension,
  pgVersion,
  version ? "0.3.0",
}:
prebuiltPgrxExtension {
  pname = "pg_tzf";
  inherit version;

  url = "https://github.com/ringsaturn/pg-tzf/releases/download/v${version}/pg-tzf-v${version}-pg${pgVersion}-linux-x86_64.tar.gz";

  hash =
    {
      "14" = "sha256-piDBmruM60uDKzBCeaQ006Kf1xLSidSSd1QH+r7M5Ww=";
      "15" = "sha256-z8FQtWUOrF7UigHSJKgloSV2iigTejszCpWawSRefxM=";
      "16" = "sha256-sskEBFc69/taaMQnBu39YGq4ZZbHQJsmbnrar1VTzdU=";
      "17" = "sha256-fZ7HA3p6GXUE33dq4Snyc3BuTfgGAMDIAnaX+6netn4=";
      "18" = "sha256-UbW8phz2jPlN//ew3JAGkFM/wfHhn2FM5n46/SWNtgY=";
    }
    .${pgVersion};

  meta = {
    description = "Fast PostgreSQL extension to lookup timezone name by GPS coordinates";
    homepage = "https://github.com/ringsaturn/pg-tzf";
    license = "MIT";
  };
}
