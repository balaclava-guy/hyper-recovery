# Nix package for lxconsole
{ lib
, python3
, fetchFromGitHub
}:

python3.pkgs.buildPythonApplication rec {
  pname = "lxconsole";
  version = "unstable-2025-02-16";

  src = fetchFromGitHub {
    owner = "PenningLabs";
    repo = "lxconsole";
    rev = "9aa95a1625ee03664edc177a6d369495b258d3fc";
    hash = "sha256-dGfUf/ehus4d61DgR8G8m/Wy2Q4jFaYljBJPEUcq2+c=";
  };

  propagatedBuildInputs = with python3.pkgs; [
    flask
    flask-wtf
    requests
    urllib3
  ];

  # Don't run tests (requires incus server)
  doCheck = false;

  # Create wrapper script
  postInstall = ''
    mkdir -p $out/share/lxconsole
    cp -r $src/static $out/share/lxconsole/
    cp -r $src/templates $out/share/lxconsole/

    # Create run script
    cat > $out/bin/lxconsole <<EOF
    #!${python3}/bin/python3
    import os
    import sys

    # Set working directory to share directory
    os.chdir('$out/share/lxconsole')

    # Import and run the app
    sys.path.insert(0, '$out/${python3.sitePackages}')
    from run import app

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=5000)
    EOF

    chmod +x $out/bin/lxconsole
  '';

  meta = with lib; {
    description = "Web-based user interface for managing Incus and LXD servers";
    homepage = "https://github.com/PenningLabs/lxconsole";
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
  };
}
