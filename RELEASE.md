# RollDev 0.6.2 Release Notes

## Bug Fixes

### Fixed Source Code Restoration Failing on macOS

The `restore` and `restore-full` commands were reporting "SUCCESS: Source code restored" but no files were actually extracted on macOS. The commands worked correctly on Linux.

**Root Cause:**

BSD tar (macOS) doesn't reliably handle piped stdin combined with the `-C` (change directory) flag, while GNU tar (Linux) handles this correctly:

```bash
# Before - works on Linux, fails silently on macOS
gzip -dc "$src_file" | tar -xf - -C "$target_dir" 2>/dev/null

# After - works on both macOS and Linux
tar -xf "$src_file" -C "$target_dir"
```

The `2>/dev/null` was also suppressing all error output, hiding the failure.

**Fix:**
- Changed to direct file reading (`tar -xf file`) instead of piping
- Both BSD and GNU tar auto-detect compression format
- Removed silent error suppression so failures are visible
- For encrypted backups: decrypt to temp file first, then extract directly

---

## Files Changed

| File | Change |
|------|--------|
| `commands/restore-full.cmd` | Fixed `restoreSourceCode()` to use direct tar extraction |
| `commands/restore.cmd` | Fixed archive extraction to use direct tar extraction |

---

## Upgrade Instructions

1. **Update RollDev**:
   ```bash
   brew upgrade rolldev
   # or pull latest if installed from source
   ```

2. **Verify the fix** (macOS):
   ```bash
   roll restore-full --force backup.tar.gz ~/Sites/myproject --verbose
   ls ~/Sites/myproject  # Should show restored files
   ```

---

**Full Changelog**: https://github.com/dockergiant/rolldev/compare/0.6.1...0.6.2

---

v0.6.2 - macOS Restore Fixed
