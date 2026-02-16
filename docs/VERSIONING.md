# Versioning Guide

Hyper Recovery uses **Semantic Versioning** (SemVer): `MAJOR.MINOR.PATCH`

## Version Number Meaning

```
0.1.0
│ │ │
│ │ └─── PATCH: Bug fixes, docs, minor tweaks
│ └───── MINOR: New features (backwards compatible)
└─────── MAJOR: Breaking changes
```

## When to Bump Versions

### Don't bump for:
- ❌ Every commit
- ❌ Work-in-progress changes
- ❌ Branch/experimental work
- ❌ Documentation typos

### DO bump for:

#### PATCH version (0.1.0 → 0.1.1)
- 🐛 Bug fixes
- 📚 Significant documentation improvements
- 🔧 Minor configuration tweaks
- ⚡ Performance improvements (no API changes)

#### MINOR version (0.1.0 → 0.2.0)
- ✨ New features
- 🔄 Significant refactors (e.g., cockpit → incus)
- 📦 New packages added
- 🎨 Major UI/branding changes

#### MAJOR version (0.1.0 → 1.0.0)
- 💥 Breaking changes
- 🔥 Removed features
- 🏗️ Complete architecture changes
- 📛 Incompatible with previous versions

## Release Workflow

### 1. Development Phase
Work on features/fixes without changing version:
```bash
git checkout -b feature/my-new-feature
# ... make changes ...
git commit -m "feat: add new feature"
```

### 2. Prepare Release
When ready to release, update the version:

```bash
# Edit nix/version.nix and update the version line:
# version = "0.2.0";

git add nix/version.nix
git commit -m "chore: bump version to 0.2.0"
```

### 3. Tag the Release
```bash
git tag -a v0.2.0 -m "Release 0.2.0

- Added incus/lxconsole support
- Removed cockpit/libvirt
- Added Proxmox deployment workflow
"
```

### 4. Push
```bash
git push origin main
git push --tags
```

### 5. GitHub Release (Optional)
Go to GitHub and create a release from the tag with:
- Release notes
- Changelog
- Attach compressed ISO artifacts

## Version in Filenames

The version automatically appears in:
- **ISO files**: `snosu-hyper-recovery-0.2.0-x86_64-linux.iso`
- **Compressed archives**: `snosu-hyper-recovery-0.2.0.iso.7z`
- **Boot menu**: "START HYPER RECOVERY v0.2.0"
- **MOTD**: Shows version when you log in

## Checking Current Version

```bash
# View the version
cat nix/version.nix | grep 'version ='

# See version in built ISO filename
nix build .#usb
ls -lh result/iso/

# Check latest git tag
git describe --tags --abbrev=0
```

## Example: Bumping to 0.2.0

```bash
# 1. Update version
sed -i '' 's/version = "0.1.0"/version = "0.2.0"/' nix/version.nix

# 2. Commit
git add nix/version.nix
git commit -m "chore: bump version to 0.2.0"

# 3. Tag
git tag -a v0.2.0 -m "Release 0.2.0"

# 4. Push
git push && git push --tags

# 5. Build release
nix build .#image-all-compressed
```

## Version History

- **v0.1.0** (2026-02-16) - Initial release with incus/lxconsole
  - Migrated from cockpit/libvirt to incus/lxconsole
  - Added semantic versioning
  - Added Proxmox deployment workflow

---

## Quick Reference

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Bug fix | PATCH | 0.1.0 → 0.1.1 |
| New feature | MINOR | 0.1.0 → 0.2.0 |
| Breaking change | MAJOR | 0.1.0 → 1.0.0 |

**Rule of thumb**: If you're not sure, bump MINOR. Users expect frequent minor releases.
