# Known Issues and Technical Debt

This file documents outdated, inaccurate, or inconsistent information in the repository that should be addressed.

---

## 🔴 Critical Issues (Will cause boot failures)

### 1. Kubernetes configs missing `overwrite: true` on `/etc/hostname`

**Severity:** Critical - VMs will boot into emergency mode

**Files Affected:**
- `examples/kubernetes/kubernetes-control-plane.bu` (line 18-21)
- `examples/kubernetes/kubernetes-worker.bu` (line 21-24)

**Issue:** Both Kubernetes configuration files are missing `overwrite: true` for the `/etc/hostname` file. According to TROUBLESHOOTING.md and CLAUDE.md, this directive is REQUIRED for system files that already exist in the CoreOS base image.

**Current Code (INCORRECT):**
```yaml
- path: /etc/hostname
  mode: 0644
  contents:
    inline: k3s-control-plane  # or k3s-worker
```

**Should Be:**
```yaml
- path: /etc/hostname
  mode: 0644
  overwrite: true  # ← MISSING
  contents:
    inline: k3s-control-plane
```

**Evidence:**
- TROUBLESHOOTING.md (lines 44-61): Shows correct format with `overwrite: true`
- CLAUDE.md (lines 110-112): Documents that `overwrite: true` is REQUIRED for `/etc/hostname`
- Both nginx and PostgreSQL examples correctly include this directive (nginx.bu:100, postgresql.bu:102)

**Priority:** Fix immediately before anyone attempts to deploy Kubernetes configs

---

### 2. Default ignition.bu missing `overwrite: true`

**Severity:** Critical - Default CoreOS deployments will fail

**File Affected:**
- `ignition/ignition.bu` (line 17-20)

**Issue:** The default Butane configuration also lacks the `overwrite: true` directive on `/etc/hostname`.

**Current Code (INCORRECT):**
```yaml
- path: /etc/hostname
  mode: 0644
  contents:
    inline: fcos-user
```

**Should Be:**
```yaml
- path: /etc/hostname
  mode: 0644
  overwrite: true  # ← MISSING
  contents:
    inline: fcos-user
```

**Priority:** Fix immediately - affects all default deployments

---

## 🟠 High-Severity Issues (Documentation misleading users)

### 3. README examples reference non-existent script options

**Severity:** High - Users following documentation will fail

**Files Affected:**
- `examples/nginx/README.md` (lines 39, 47-51)
- `examples/postgresql/README.md` (lines 52, 59-64)

**Issue:** Documentation shows script options that don't exist in `setup-coreos.sh`:

**Documented (INCORRECT):**
```bash
./setup-coreos.sh --ignition-file examples/nginx/nginx.ign --vmid 500
```

**Script Actually Uses:** Interactive menu system (lines 45-106 in setup-coreos.sh) - no `--ignition-file` or `--vmid` flags are implemented.

**Solution:** Update examples to show the interactive menu workflow:
```bash
./setup-coreos.sh
# Then select the desired configuration from the menu
```

---

### 4. Documentation shows outdated workflow

**Severity:** High - Creates confusion about deployment process

**Files Affected:**
- `examples/nginx/README.md` (lines 29-31, 39-40)
- `examples/postgresql/README.md` (lines 38-40, 42-43)
- `README.md` (lines 90-106)

**Issue:** Examples show generating `.ign` files manually:
```bash
butane examples/nginx/nginx.bu > examples/nginx/nginx.ign
```

However, the current `setup-coreos.sh` script (lines 492-495):
1. Converts `.bu` files directly during VM creation
2. Doesn't require pre-generated `.ign` files
3. Uses the interactive menu system instead

**Solution:** Update all example READMEs to reference the new menu-driven workflow instead of manual `.ign` generation. Focus on the interactive menu presented in `setup-coreos.sh` lines 45-106.

---

## 🟡 Medium Issues

### 5. TROUBLESHOOTING.md contains placeholder text

**Severity:** Medium - Incomplete documentation

**File Affected:**
- `TROUBLESHOOTING.md` (line 75)

**Issue:** A commit hash placeholder was left in the documentation:
```markdown
**Files Affected:**
- `examples/postgresql/postgresql.bu` (fixed in commit XXXXXXX)
```

**Solution:** Replace with actual commit hash:
```markdown
**Files Affected:**
- `examples/postgresql/postgresql.bu` (fixed in commit 907a523)
```

---

### 6. Butane version hard-coded without documentation

**Severity:** Low-Medium - Not documented but maintained

**File Affected:**
- `setup-coreos.sh` (line 265): Hard-codes Butane version `v0.21.0`

**Issue:** Script hard-codes Butane version but this isn't documented in CLAUDE.md or README.md. While not breaking, this could become outdated silently.

**Solution Options:**
1. Add version constraint documentation to CLAUDE.md
2. Make it a configurable variable with a default
3. Add a check to warn if a newer version is available

---

### 7. Kubernetes docs claim static IP not actually configured

**Severity:** Medium - Misleading documentation

**Files Affected:**
- `examples/kubernetes/README.md` (line 24)
- `examples/kubernetes/kubernetes-control-plane.bu` (lines 47-61)

**Issue:** Documentation references static IP `192.168.68.54` for control plane:
```
Control Plane (k3s server)
  Static IP: 192.168.68.54:6443
```

But the Butane config uses DHCP networking, not static IP.

**Solution:** Either:
1. Update docs to clarify DHCP is being used and show how to configure static IP
2. Or add static IP configuration to the Butane file and update docs accordingly

---

## Summary Table

| Category | Severity | Count | Status |
|----------|----------|-------|--------|
| Critical Config Errors | Critical | 2 files | Needs immediate fix |
| Documentation Placeholders | Medium | 1 file | Needs update |
| Non-existent Script Options | High | 2 files | Needs documentation update |
| Outdated Workflow Docs | High | 3 files | Needs comprehensive update |
| Missing Version Documentation | Low-Medium | 1 file | Needs documentation |
| Misleading IP Configuration | Medium | 2 files | Needs clarification |

---

## Recommended Fix Order

1. **Fix critical issues first** (Issues #1 and #2): Add `overwrite: true` to kubernetes and default configs
2. **Update documentation** (Issues #3 and #4): Align examples with current interactive menu workflow
3. **Fix placeholder** (Issue #5): Replace commit hash placeholder
4. **Clarify static IP** (Issue #7): Update Kubernetes docs or config
5. **Document Butane version** (Issue #6): Add to CLAUDE.md for maintenance
