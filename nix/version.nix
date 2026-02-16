# Central version information for Hyper Recovery
# This file is the single source of truth for all version strings
#
# Versioning Strategy (Semantic Versioning):
#   MAJOR.MINOR.PATCH
#
#   - MAJOR: Breaking changes (incompatible changes)
#   - MINOR: New features (backwards compatible)
#   - PATCH: Bug fixes (backwards compatible)
#
# When to bump versions:
#   - PATCH: Bug fixes, documentation updates, minor tweaks
#   - MINOR: New features, significant changes (e.g., cockpit → incus migration)
#   - MAJOR: Breaking changes, complete rewrites
#
# For development:
#   - Don't bump version for every commit
#   - Bump version when preparing a release
#   - Use git tags to mark releases: `git tag -a v0.1.0 -m "Release 0.1.0"`
#
# Example workflow:
#   1. Work on features/fixes on a branch
#   2. When ready for release, update version here
#   3. Commit: `git commit -m "chore: bump version to 0.2.0"`
#   4. Tag: `git tag -a v0.2.0 -m "Release 0.2.0"`
#   5. Push: `git push && git push --tags`

{
  # Semantic version - UPDATE THIS MANUALLY FOR RELEASES
  version = "0.1.0";

  # Project naming
  name = "hyper-recovery";
  fullName = "snosu-hyper-recovery";

  # Volume IDs (max 32 chars for ISO9660)
  volumeId = "HYPER-RECOVERY";
  volumeIdDebug = "HYPER-RECOVERY-DEBUG";

  # Image base names (used in filenames)
  # Format: ${fullName}-${version}-${system}[-debug]
  # Example: snosu-hyper-recovery-0.1.0-x86_64-linux.iso
  mkBaseName = { version, system, debug ? false }:
    "${fullName}-${version}-${system}${if debug then "-debug" else ""}";

  # ISO filename format
  mkIsoName = { version, system, debug ? false }:
    "${mkBaseName { inherit version system debug; }}.iso";
}
