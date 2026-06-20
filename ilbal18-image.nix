{
  pkgs ? import <nixpkgs> { },
}:

let
  pg = pkgs.postgresql_18;

  pgWithExtensions = pg.withPackages (ps: [
    ps.postgis
  ]);

  runtime = pkgs.buildEnv {
    name = "pg-runtime";

    paths = [
      pgWithExtensions
    ];

    extraOutputsToInstall = [ "out" ];
    ignoreCollisions = true;
  };

  debianBase = pkgs.dockerTools.pullImage {
    imageName = "debian";

    # IMPORTANT:
    # NO imageTag in your nixpkgs version
    imageDigest = "sha256:35ae959f6e83ffb465e7614d27b4fddd28288caa551fbca2798367567cce80d3";

    sha256 = "sha256-oVkl2P+vq+B63zpS0BkQ6Nt73/loF3yiTwTzi9kRrvo=";
  };

in
pkgs.dockerTools.streamLayeredImage {
  name = "ilbal-postgres18-debian-postgis";
  tag = "latest";

  fromImage = debianBase;

  contents = [
    runtime
  ];

  config = {
    Env = [
      "PGDATA=/var/lib/postgresql/data"
      "PATH=/bin:/usr/bin"
      "LD_LIBRARY_PATH=/lib:/usr/lib"
    ];

    ExposedPorts = {
      "5432/tcp" = { };
    };

    Cmd = [
      "${pg}/bin/postgres"
      "-D"
      "/var/lib/postgresql/data"
    ];

    WorkingDir = "/var/lib/postgresql";
  };
}
