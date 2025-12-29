# Why We Need to Patch the OpenBSD ISO

## The Problem: Manual Installation vs. Automation

The stock OpenBSD installation ISO (`install78.iso`) is designed for **interactive, manual installation**. When you boot from it, the installer:

1. **Asks questions** - hostname, network config, root password, disk layout, timezone, etc.
2. **Waits for user input** - you must type answers for each prompt
3. **Requires physical/VNC access** - someone needs to be at the console

This works fine when installing OpenBSD on a physical machine or in VirtualBox with a GUI, but it's **completely impractical** for:

- **Cloud deployments** where you can't easily interact with the console
- **Automated builds** that need to run without human intervention
- **CI/CD pipelines** that need reproducible, hands-off installations
- **Multiple deployments** where you'd have to repeat the same answers every time

## The Solution: Automated Installation (autoinstall)

OpenBSD supports **unattended/automated installation** through a feature called `autoinstall`. The way it works:

1. Boot the installer with special configuration files present
2. The installer reads these files instead of asking questions
3. Installation proceeds automatically without any human input
4. System is configured exactly as specified in the configuration

## What We Patch Into the ISO

We create a **patched ISO** by extracting the original ISO, adding our custom configuration files, and rebuilding it. Here's what gets added:

### 1. **auto_install.conf** - Installation Answers
```
System hostname = openbsd
Which network interface = vio0
IPv4 address for vio0 = dhcp
Password for root account = openbsd
Allow root ssh login = yes
Which disk is the root disk = sd0
...
```

This file contains all the answers the installer would normally ask for interactively. The installer reads this file and uses these answers automatically.

### 2. **disklabel.template** - Disk Partitioning
```
/       1G
swap    2G
/tmp    1G
/var    4G
/usr    10G
/usr/local 8G
/home   *
```

Defines exactly how to partition the disk. Without this, you'd have to manually partition during installation.

### 3. **boot.conf** - Serial Console Configuration
```
set tty com0
```

**Critical for GCE**: Google Compute Engine uses serial console for access (not a graphical display). This tells OpenBSD's bootloader to use the serial port (`com0`) for console I/O instead of a video display.

Without this, you wouldn't be able to see boot messages or interact with the system through GCE's serial console.

### 4. **site78.tgz** - Custom Configuration Package
This is a tarball containing system configuration files that get installed during setup:

- `/etc/hostname.vio0` - Network config (DHCP on virtio interface)
- `/etc/installurl` - Package repository URL
- `/etc/rc.local` - Custom startup script
- `/etc/sysctl.conf` - Kernel parameters

These files customize the system for the GCE environment.

### 5. **random.seed** - Entropy for Security
```
head -c 512 /dev/urandom > random.seed
```

Provides initial entropy for the random number generator during installation. Important for cryptographic operations during first boot.

### 6. **install.site** - Post-Installation Script
```bash
#!/bin/sh
sed -i 's/^console.*off/console...on/' /etc/ttys
pkg_add -I bash curl git vim
```

Runs after base installation completes. It:
- Enables getty on the serial console (so you can login via serial)
- Installs additional packages
- Performs any other custom configuration

## Why Can't We Just Boot and Script It?

**Q:** Why not boot the regular ISO and send keystrokes programmatically?

**A:** Several reasons:

1. **Fragile** - Timing issues, prompt variations, hard to debug
2. **Not reproducible** - Network delays, package download times vary
3. **Console limitations** - QEMU serial console can be tricky with automated input
4. **Error handling** - If something goes wrong, the script can't adapt
5. **Not the OpenBSD way** - autoinstall is the official, supported method

## The Build Process

Here's what happens when we build the image:

```
1. Download install78.iso (stock installer)
   ↓
2. Extract ISO contents
   ↓
3. Add our configuration files:
   - auto_install.conf
   - disklabel.template  
   - boot.conf
   - site78.tgz
   - random.seed
   - install.site
   ↓
4. Rebuild ISO as install78-patched.iso
   ↓
5. Boot QEMU with patched ISO
   ↓
6. OpenBSD installer finds auto_install.conf
   ↓
7. Installation proceeds automatically
   ↓
8. System is configured for GCE
   ↓
9. Extract disk.raw and compress
```

## Benefits of This Approach

✅ **Fully Automated** - No human interaction needed
✅ **Reproducible** - Same config every time
✅ **Fast** - No waiting for manual input
✅ **Scalable** - Can build multiple images in parallel
✅ **Documented** - All configuration in version-controlled files
✅ **Official** - Uses OpenBSD's supported autoinstall feature
✅ **GCE-Ready** - Serial console and virtio drivers configured correctly

## Alternative: Why Not Use Pre-Built Images?

**Q:** Why not just download a pre-built OpenBSD GCE image?

**A:** 
1. **Doesn't exist** - OpenBSD doesn't provide official GCE images
2. **Security** - Building yourself means you know exactly what's in it
3. **Customization** - You can configure it exactly how you want
4. **Updates** - You control when and how to update
5. **Learning** - Understand the full build process

## References

- [OpenBSD autoinstall(8)](https://man.openbsd.org/autoinstall)
- [Eric Radman's autoinstall guide](https://eradman.com/posts/autoinstall-openbsd.html)
- [Go Team's OpenBSD builders](https://github.com/golang/build/tree/master/env/openbsd-amd64)

## Summary

**Why we patch the ISO**: To transform an interactive installer into an automated, unattended installation system that can build GCE-compatible OpenBSD images without human intervention. The patched ISO contains all the configuration needed to automatically install and configure OpenBSD for the Google Cloud environment.
