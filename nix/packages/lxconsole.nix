# Nix package for lxconsole
{ lib
, python3
, fetchFromGitHub
}:

python3.pkgs.buildPythonApplication rec {
  pname = "lxconsole";
  version = "unstable-2025-02-16";
  format = "other";  # No setup.py, we'll install manually

  src = fetchFromGitHub {
    owner = "PenningLabs";
    repo = "lxconsole";
    rev = "9aa95a1625ee03664edc177a6d369495b258d3fc";
    hash = "sha256-dGfUf/ehus4d61DgR8G8m/Wy2Q4jFaYljBJPEUcq2+c=";
  };

  propagatedBuildInputs = with python3.pkgs; [
    flask
    flask-sqlalchemy
    flask-bcrypt
    flask-login
    flask-wtf
    flask-sock
    pyopenssl
    pyotp
    qrcode
    requests
    wtforms
    email-validator
    gunicorn
    werkzeug
    websocket-client
  ];

  dontBuild = true;

  # Don't run tests (requires incus server)
  doCheck = false;

  # Custom install phase to copy application files and create wrapper script
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/lxconsole
    mkdir -p $out/bin

    # Copy the entire lxconsole package directory (contains static/, templates/, etc.)
    cp -r $src/lxconsole $out/share/lxconsole/

    # Copy the run script
    cp $src/run.py $out/share/lxconsole/

    # Create wrapper script that runs the Flask app
    cat > $out/bin/lxconsole <<EOF
#!${python3}/bin/python3
import os
import sys

# Set instance path BEFORE any imports
instance_path = os.environ.get('FLASK_INSTANCE_PATH', '/var/lib/lxconsole')
os.makedirs(instance_path, exist_ok=True)

# Monkey-patch Flask to use our instance_path
import flask
_original_flask_init = flask.Flask.__init__

def _patched_flask_init(self, *args, **kwargs):
    if 'instance_path' not in kwargs:
        kwargs['instance_path'] = instance_path
    _original_flask_init(self, *args, **kwargs)

flask.Flask.__init__ = _patched_flask_init

# Add share directory to Python path so 'lxconsole' package can be imported
sys.path.insert(0, '$out/share/lxconsole')

# Change to the application directory
os.chdir('$out/share/lxconsole')

# Import and run the Flask application
from run import app
app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
EOF

    chmod +x $out/bin/lxconsole

    runHook postInstall
  '';

  meta = with lib; {
    description = "Web-based user interface for managing Incus and LXD servers";
    homepage = "https://github.com/PenningLabs/lxconsole";
    license = licenses.gpl3;
    maintainers = [];
    platforms = platforms.linux;
  };
}
