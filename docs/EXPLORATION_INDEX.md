# Hyper Recovery Codebase Exploration - Documentation Index

## Quick Navigation

### 📋 Start Here
- **[EXPLORATION_SUMMARY.md](EXPLORATION_SUMMARY.md)** - Executive summary (5 min read)
  - Overview of findings
  - Key integration points
  - Next steps

### 🏗️ Architecture & Design
- **[ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)** - System architecture diagrams
  - Boot sequence
  - Service startup order
  - Module dependency graph
  - Build process flow

### 🔧 Implementation Guide
- **[WIFI_SETUP_INTEGRATION_GUIDE.md](WIFI_SETUP_INTEGRATION_GUIDE.md)** - Quick reference
  - Service definition template
  - Script packaging template
  - Python script template
  - Integration checklist
  - Debugging commands

### 📚 Comprehensive Reference
- **[CODEBASE_EXPLORATION.md](CODEBASE_EXPLORATION.md)** - Full technical analysis
  - NetworkManager configuration
  - Service definition patterns
  - Rust package integration
  - Theming & branding details
  - Custom scripts structure
  - Project organization
  - Build & deployment

---

## Document Purposes

| Document | Purpose | Audience | Length |
|----------|---------|----------|--------|
| EXPLORATION_SUMMARY.md | Quick overview of findings | Everyone | 5 min |
| ARCHITECTURE_OVERVIEW.md | Visual system design | Architects, Developers | 10 min |
| WIFI_SETUP_INTEGRATION_GUIDE.md | Implementation reference | Developers | 5 min |
| CODEBASE_EXPLORATION.md | Complete technical details | Developers, Maintainers | 30 min |

---

## Key Findings Summary

### ✓ NetworkManager Configuration
- **Status**: Already enabled
- **Tools**: nmcli, wpa_supplicant, iw
- **Integration**: Direct use via nmcli

### ✓ Service Patterns
- **Type**: systemd services
- **Pattern**: oneshot or simple
- **Dependencies**: after, wants, wantedBy
- **Output**: journalctl logging

### ✓ Script Packaging
- **Language**: Python 3
- **Helper**: makePythonScript function
- **Pattern**: Established and consistent
- **Runtime**: Injected via PATH

### ✓ Theming
- **Colors**: SNOSU brand palette (6 colors)
- **Fonts**: Undefined Medium (GRUB/Plymouth), PatternFly (Cockpit)
- **Files**: assets/branding/, themes/

### ✓ Module Structure
- **Organization**: system/, iso/, flake/
- **Import Order**: base → hardware → branding → services → [debug] → iso
- **Composition**: Clean separation of concerns

---

## Integration Checklist

### Phase 1: Create Script
- [ ] Create `scripts/hyper-connect.py`
- [ ] Test script locally
- [ ] Add docstring and error handling

### Phase 2: Package Script
- [ ] Add to `nix/packages/scripts/default.nix`
- [ ] Use makePythonScript helper
- [ ] Include runtime dependencies

### Phase 3: Create Service
- [ ] Create `nix/modules/system/network.nix`
- [ ] Define systemd service
- [ ] Set proper dependencies

### Phase 4: Integrate Module
- [ ] Update `nix/flake/images.nix`
- [ ] Add module to both usb-live and usb-live-debug
- [ ] Export module in flake.nixosModules

### Phase 5: Build & Test
- [ ] Build: `nix build .#usb`
- [ ] Boot system
- [ ] Verify service: `systemctl status hyper-connect`
- [ ] Check logs: `journalctl -u hyper-connect`
- [ ] Test WiFi: `nmcli device wifi list`

---

## File Locations

### Documentation
```
/Users/hassan/projects/hyper-recovery/
├── EXPLORATION_SUMMARY.md          ← Start here
├── ARCHITECTURE_OVERVIEW.md        ← System design
├── WIFI_SETUP_INTEGRATION_GUIDE.md ← Implementation
├── CODEBASE_EXPLORATION.md         ← Full reference
└── EXPLORATION_INDEX.md            ← This file
```

### Source Code
```
/Users/hassan/projects/hyper-recovery/
├── nix/
│   ├── modules/
│   │   ├── system/
│   │   │   ├── base.nix
│   │   │   ├── hardware.nix
│   │   │   ├── branding.nix
│   │   │   ├── services.nix
│   │   │   └── debug.nix
│   │   ├── iso/
│   │   │   ├── base.nix
│   │   │   └── grub-bootloader.nix
│   │   └── flake/
│   │       ├── packages.nix
│   │       ├── images.nix
│   │       ├── apps.nix
│   │       └── devshells.nix
│   ├── packages/
│   │   ├── scripts/default.nix
│   │   ├── themes/
│   │   │   ├── plymouth.nix
│   │   │   └── grub.nix
│   │   └── firmware.nix
│   └── flake.nix
├── scripts/
│   ├── hyper-debug.py
│   ├── hyper-hw.py
│   ├── hyper-debug-serial.py
│   ├── save-boot-logs.py
│   └── shell/
│       └── snosu-motd.sh
├── assets/
│   ├── branding/
│   │   ├── branding.css
│   │   ├── branding.ini
│   │   └── logo-source.png
│   ├── fonts/
│   ├── grub/
│   ├── plymouth/
│   └── motd-logo.ansi
└── themes/
    ├── grub/
    └── plymouth/
```

---

## Color Palette Reference

```css
/* SNOSU Brand Colors */
--snosu-blue: #0ea1fb;      /* Primary - Links, buttons */
--snosu-cyan: #48d7fb;      /* Accent - Highlights */
--snosu-coral: #e94a57;     /* Error - Warnings */
--snosu-gold: #efbe1d;      /* Warning - Caution */
--snosu-ink: #070c19;       /* Background - Dark navy */
--snosu-text: #15223b;      /* Text - Dark text */
--snosu-violet: #150562;    /* Accent - Gradients */
```

---

## Common Commands

### Building
```bash
nix build .#usb              # Regular image
nix build .#usb-debug        # Debug image
nix build .#image-all        # All images
nix build .#image-compressed # Compressed
```

### Testing
```bash
systemctl status hyper-connect
journalctl -u hyper-connect -n 50
nmcli device wifi list
nmcli general status
```

### Deployment
```bash
# Direct write
sudo dd if=result/iso/snosu-hyper-recovery-x86_64-linux.iso \
         of=/dev/sdX bs=4M status=progress

# Ventoy
cp result/iso/snosu-hyper-recovery-x86_64-linux.iso /path/to/ventoy/
```

---

## Recommended Reading Order

1. **First Time?** → EXPLORATION_SUMMARY.md (5 min)
2. **Want Details?** → ARCHITECTURE_OVERVIEW.md (10 min)
3. **Ready to Code?** → WIFI_SETUP_INTEGRATION_GUIDE.md (5 min)
4. **Need Reference?** → CODEBASE_EXPLORATION.md (30 min)

---

## Key Takeaways

### ✓ What's Already There
- NetworkManager enabled and configured
- nmcli, wpa_supplicant, iw available
- Python 3 with subprocess support
- Systemd service infrastructure
- Script packaging pattern
- Branding/theming system

### ✓ What You Need to Add
1. Python script for WiFi setup
2. Package definition in Nix
3. Systemd service module
4. Module import in images.nix
5. Build and test

### ✓ Integration Points
- Script: `scripts/hyper-connect.py`
- Package: `nix/packages/scripts/default.nix`
- Service: `nix/modules/system/network.nix` (new)
- Module: `nix/flake/images.nix`

### ✓ Service Lifecycle
```
Boot → systemd-journald → network-online.target → 
hyper-connect (oneshot) → multi-user.target → Ready
```

---

## Questions & Answers

### Q: Do I need to use Rust?
**A**: No. The project uses Python 3 for all scripts. Use Python for consistency.

### Q: Where does the service run?
**A**: After `network-online.target`, before `multi-user.target`. Doesn't block boot.

### Q: How do I debug the service?
**A**: Use `journalctl -u hyper-connect` to view logs.

### Q: Can I use the existing color palette?
**A**: Yes! Use `--snosu-blue: #0ea1fb` for primary, `--snosu-cyan: #48d7fb` for accents.

### Q: What if WiFi setup fails?
**A**: Service is optional (wants, not requires). System boots normally.

---

## Support Resources

### In This Repository
- `README.md` - Project overview
- `UPGRADE_NOTES.md` - Version history
- `AGENTS.md` - Agent guidelines

### External Resources
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [NetworkManager Documentation](https://networkmanager.dev/)
- [Systemd Documentation](https://www.freedesktop.org/software/systemd/man/)
- [Nix Language Reference](https://nixos.org/manual/nix/stable/language/)

---

## Document Metadata

| Property | Value |
|----------|-------|
| Created | 2026-02-10 |
| Last Updated | 2026-02-10 |
| NixOS Version | 25.05 |
| Status | Complete |
| Audience | Developers, Architects |

---

## Quick Links

- [EXPLORATION_SUMMARY.md](EXPLORATION_SUMMARY.md) - Start here
- [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) - System design
- [WIFI_SETUP_INTEGRATION_GUIDE.md](WIFI_SETUP_INTEGRATION_GUIDE.md) - Implementation
- [CODEBASE_EXPLORATION.md](CODEBASE_EXPLORATION.md) - Full reference

---

**Ready to implement?** → See [WIFI_SETUP_INTEGRATION_GUIDE.md](WIFI_SETUP_INTEGRATION_GUIDE.md)
