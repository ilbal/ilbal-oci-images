{
  prebuiltPgrxExtension,
  pgVersion,
  version ? "0.3.0",
}:
prebuiltPgrxExtension {
  pname = "pg_tzf";
  inherit version;

  url =
    "https://github.com/ringsaturn/pg-tzf/releases/download/v${version}/pg-tzf-v${version}-pg${pgVersion}-linux-x86_64.tar.gz";

  hash = {
    "14" = "sha256-a620c19abb8ceb4b832b304279a434d3a29fd712d289d492775407fabecce56c";
    "15" = "sha256-cfc150b5650eac5ed48a01d224a825a125768a28137a3b330a959ac1245e7f13";
    "16" = "sha256-b2c90404573af7fb5a68c42706edfd606ab86596c7409b266e7adaaf5553cdd5";
    "17" = "sha256-7d9ec7037a7a197504df776ae129f273706e4df80600c0c8027697fba9deb67e";
    "18" = "sha256-51b5bca61cf68cf94dfff7b0dc900690533fc1f1e19f614ce67e3afd258db606";
  }.${pgVersion};

  meta = {
    description = "Fast PostgreSQL extension to lookup timezone name by GPS coordinates";
    homepage = "https://github.com/ringsaturn/pg-tzf";
    license = "MIT";
  };
}
