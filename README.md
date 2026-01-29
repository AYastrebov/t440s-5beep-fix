# ThinkPad T440s 5-Beep Fix (BIOS Recovery)

This repository documents the procedure to revive a Lenovo ThinkPad T440s (and similar generations like T440, T440p, X240) suffering from the "5 Beeps of Death" error.

## Symptoms

- Laptop turns on, fan spins, but screen remains black
- Exactly 5 short beeps are heard
- The error often occurs "suddenly" or after a battery drain/update

## Diagnosis

On the T440s, this usually indicates a corrupted BIOS region or TPM handshake failure, not necessarily a physically dead motherboard.

## ⚠️ Disclaimer

**DANGER:** This procedure requires hardware flashing tools and modification of firmware.

- You can permanently brick your laptop if done incorrectly
- **Voltage Warning:** Many cheap CH341A programmers output 5V on the data pins. The T440s BIOS chip is **3.3V**. Ensure your programmer is modified or voltage-safe, or you risk frying the motherboard
- I am not responsible for any damage to your hardware

---

## Hardware Requirements

- **CH341A USB Programmer** (Black or Green edition)
- **SOIC8 Test Clip** (Pomona 5250 or generic cheap clip)
- **Another PC** (Linux for all methods, macOS/Windows can use Docker for preparation)
- **T440s Target:** Bottom cover removed, Internal Battery and CMOS Battery disconnected

---

## Choose Your Method

| Method | Difficulty | Requirements | Best For |
|--------|-----------|--------------|----------|
| **Docker** | Easiest | Docker only | Any OS, quick setup |
| **Automated Script** | Easy | Linux + dependencies | Linux users |
| **Manual** | Advanced | Linux + dependencies | Learning/debugging |

All methods share the same first two steps (locate chip, backup) and end with the same flashing command.

---

## Common Steps (All Methods)

### Step 1: Locate the Chip

On the ThinkPad T440s (Model 20AR), the BIOS chip is located near the RAM slot, often covered by a black plastic flap.

- **Chip Model:** Typically Winbond 25Q128FV (or similar 25xx128)
- **Size:** 16MB (16,777,216 bytes)
- **Orientation:** Look for the dot on the chip surface (Pin 1). Align the Red Wire of your clip to Pin 1.

### Step 2: Backup the Corrupted BIOS

**Crucial:** Do not skip this. If you lose your original dump, you lose your Ethernet MAC address, Windows License Key, and Serial Numbers.

1. Connect the clip to the T440s (Batteries disconnected!)
2. Run flashrom to read the chip twice and compare checksums

```bash
# Read 1
sudo flashrom -p ch341a_spi -r backup1.bin

# Read 2
sudo flashrom -p ch341a_spi -r backup2.bin

# Compare
sha256sum backup1.bin backup2.bin
```

> If hashes match, proceed. If not, re-seat the clip and try again.

---

## Method 1: Docker Container

All tools are pre-packaged in a Docker image - no manual installation needed.

### Prerequisites

- Docker installed on your system
- Your backup file (`backup1.bin` or `backup.bin`) from Step 2

### Get the Docker Image

**Option A: Use Pre-built Image (Recommended)**

```bash
# Replace OWNER/REPO with the actual repository path
docker pull ghcr.io/OWNER/REPO:latest
```

**Option B: Build Locally**

```bash
docker build -t t440s-bios-fix .
```

Or use the convenience script which auto-builds if needed:

```bash
./docker-run.sh
```

### Prepare the Fixed BIOS

```bash
# Auto-download BIOS from Lenovo
docker run --rm -v $(pwd):/work t440s-bios-fix \
    -c "prepare_bios.sh --download backup.bin fixed_bios.bin"

# Or use your own ISO
docker run --rm -v $(pwd):/work t440s-bios-fix \
    -c "prepare_bios.sh gjuj40us.iso backup.bin fixed_bios.bin"
```

**Using the Convenience Script:**

```bash
# Interactive shell with all tools available
./docker-run.sh

# Run BIOS preparation directly
./docker-run.sh prepare_bios.sh --download backup.bin fixed_bios.bin

# Use pre-built image from GitHub Container Registry
BIOS_FIX_IMAGE=ghcr.io/OWNER/REPO:latest ./docker-run.sh
```

### Flash the Fixed BIOS

**Option A: From Docker (Linux only)**

```bash
# Requires USB device access
docker run --rm -it --privileged -v $(pwd):/work t440s-bios-fix \
    -c "flashrom -p ch341a_spi -w fixed_bios.bin"
```

**Option B: Native flashrom (recommended for macOS/Windows)**

Flashing from Docker on macOS/Windows requires USB/IP setup which is complex. It's easier to install flashrom natively for the flashing step only:

```bash
# macOS (with Homebrew)
brew install flashrom

# Then flash
sudo flashrom -p ch341a_spi -w fixed_bios.bin
```

---

## Method 2: Automated Script (Linux)

Use the provided `prepare_bios.sh` script to automate BIOS extraction, padding, and injection.

### Prerequisites

**Fedora:**

```bash
sudo dnf install flashrom p7zip p7zip-plugins coreboot-utils wget
```

**Debian/Ubuntu:**

```bash
sudo apt install flashrom p7zip-full ifdtool wget
```

> **Note:** `ifdtool` might need to be built from coreboot source on some distros.

**UEFIExtract (Required):**

Download from: https://github.com/LongSoft/UEFITool/releases

The script uses UEFIExtract for command-line operation. Place it in your PATH or the same directory as the script.

### Prepare the Fixed BIOS

```bash
# Option 1: Auto-download latest BIOS from Lenovo
./prepare_bios.sh --download backup.bin fixed_bios.bin

# Option 2: Provide your own ISO
./prepare_bios.sh gjuj40us.iso backup.bin fixed_bios.bin
```

**Script Options:**

```
Usage: ./prepare_bios.sh [OPTIONS] <iso_file|--download> <backup.bin> <output.bin>

Options:
  --download    Auto-download the latest BIOS ISO from Lenovo
  --keep-temp   Keep temporary files for debugging
  -h, --help    Show help message
```

### Flash the Fixed BIOS

```bash
sudo flashrom -p ch341a_spi -w fixed_bios.bin
```

---

## Method 3: Manual Step-by-Step

Follow this method if you want full control or need to debug issues with the automated approaches.

### Prerequisites

**Fedora:**

```bash
sudo dnf install flashrom p7zip p7zip-plugins coreboot-utils wget
```

**Debian/Ubuntu:**

```bash
sudo apt install flashrom p7zip-full ifdtool wget
```

**UEFITool (GUI):**

Download from: https://github.com/LongSoft/UEFITool/releases

### Step 3A: Download the Official BIOS

Go to the [Lenovo Support site for T440s](https://pcsupport.lenovo.com/products/laptops-and-netbooks/thinkpad-t-series-laptops/thinkpad-t440s) and download the BIOS Update Bootable CD (ISO format).

Example file: `gjuj40us.iso`

### Step 3B: Extract the Boot Image and .FL1 File

```bash
# Download geteltorito if needed
wget https://raw.githubusercontent.com/rainer042/geteltorito/master/geteltorito.pl
chmod +x geteltorito.pl

# Extract El Torito boot image
./geteltorito.pl -o bios_boot.img gjuj40us.iso

# Extract contents using 7z
7z x bios_boot.img -o./bios_extract

# Find the .FL1 file (usually in FLASH/ directory)
find ./bios_extract -name "*.FL1"
```

### Step 3C: Extract BIOS from .FL1 using UEFITool

The .FL1 file is not directly usable. You must extract the actual BIOS image:

1. Open UEFITool
2. File → Open → select the `.FL1` file
3. Navigate the tree structure:
   - Intel image → BIOS region → Padding → **UEFI image**
4. Right-click on "**UEFI image**"
5. Select "**Extract body...**"
6. Save as `bios_good.bin`

### Step 3D: Unpack Your Original Backup with ifdtool

```bash
ifdtool -x backup1.bin
```

This creates several files including:
- `flashregion_0_flashdescriptor.bin`
- `flashregion_1_bios.bin` (your original BIOS region)
- `flashregion_2_intel_me.bin`
- `flashregion_3_gbe.bin`

### Step 3E: Pad the New BIOS to Match Region Size

The extracted `bios_good.bin` is smaller than `flashregion_1_bios.bin`. We need to pad it:

```bash
# Check the sizes
ls -la bios_good.bin flashregion_1_bios.bin
```

Example output:
```
-rw-r--r-- 1 user user  9437184 Jan 29 12:00 bios_good.bin
-rw-r--r-- 1 user user 11534336 Jan 29 12:00 flashregion_1_bios.bin
```

Now create a properly padded image:

```bash
# Get the exact sizes
REGION_SIZE=$(stat -c%s flashregion_1_bios.bin)
BIOS_SIZE=$(stat -c%s bios_good.bin)
OFFSET=$((REGION_SIZE - BIOS_SIZE))

echo "Region size: $REGION_SIZE"
echo "BIOS size: $BIOS_SIZE"
echo "Offset (padding): $OFFSET"

# Create a blank image filled with 0xFF
dd if=/dev/zero bs=1 count=$REGION_SIZE | tr '\0' '\377' > proper_new_bios.bin

# Write the BIOS at the correct offset (end of the region)
dd if=bios_good.bin of=proper_new_bios.bin bs=1 seek=$OFFSET conv=notrunc
```

### Step 3F: Verify the Padded Image

```bash
# Should match the original region size exactly
ls -la proper_new_bios.bin flashregion_1_bios.bin
```

### Step 3G: Repack with ifdtool

```bash
ifdtool -i bios:proper_new_bios.bin backup1.bin -O fixed_bios.bin
```

### Step 3H: Verify Final Image Size

```bash
# Must be exactly 16,777,216 bytes (16MB)
ls -la fixed_bios.bin
```

### Flash the Fixed BIOS

```bash
sudo flashrom -p ch341a_spi -w fixed_bios.bin
```

---

## Technical Reference

### Flash Chip Layout

The T440s uses a 16MB (16,777,216 bytes) flash chip with this structure:

| Region          | Address Range         | Approximate Size |
|-----------------|-----------------------|------------------|
| Flash Descriptor| 0x000000 - 0x000FFF   | 4 KB             |
| GbE (Ethernet)  | 0x001000 - 0x002FFF   | 8 KB             |
| Intel ME        | 0x003000 - 0x4FFFFF   | ~5 MB            |
| BIOS Region     | 0x500000 - 0xFFFFFF   | ~11 MB           |

**Important:** The Lenovo .FL1 file is only the BIOS portion (~9MB), not the full 16MB chip image. That's why we must extract and pad it correctly.

### What the Script Does

The `prepare_bios.sh` script automates these steps:

1. Downloads or uses provided Lenovo BIOS ISO
2. Extracts the El Torito boot image from the ISO
3. Extracts the .FL1 file from the boot image
4. Uses UEFIExtract to dump and find the BIOS body
5. Extracts your backup's BIOS region with ifdtool
6. Calculates correct padding (0xFF) offset
7. Creates padded BIOS image matching your region size
8. Injects the padded BIOS into your backup
9. Verifies output is exactly 16MB

---

## Troubleshooting

### Flashrom says "No EEPROM/flash device found"

- Check clip connection
- Ensure internal/CMOS batteries are unplugged
- **Trick:** Plug the laptop charger in (but do NOT turn the laptop on). This provides ground/reference voltage.

### Verification failed

- Your clip is likely loose. Re-seat and try again.
- Your cable length might be too long (use a short USB extension or plug directly into PC)

### UEFITool doesn't show "UEFI image" in the tree

- Make sure you're opening the `.FL1` file, not the ISO
- Try a different version of UEFITool (some older .FL1 files work better with older UEFITool versions)

### Wrong BIOS size after padding

- Double-check your arithmetic: `OFFSET = REGION_SIZE - BIOS_SIZE`
- The final `proper_new_bios.bin` must be exactly the same size as `flashregion_1_bios.bin`

---

## Credits

- **Original solution:** [Reddit r/thinkpad - HOWTO T440s 5 beep fix](https://www.reddit.com/r/thinkpad/comments/1o5g4i2/howto_t440s_5_beep_fix/) by u/xorgmc
- **ThinkPad-Forum.de:** [Thread 238003](https://thinkpad-forum.de/threads/238003/)
- **ThinkWiki:** [BIOS Extraktion aus ISO](https://thinkwiki.de/BIOS_Extraktion_aus_ISO)
