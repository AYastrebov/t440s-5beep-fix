#!/bin/bash
#
# prepare_bios.sh - Automate BIOS extraction for T440s 5-Beep Fix
#
# Usage:
#   ./prepare_bios.sh --download backup.bin output.bin
#   ./prepare_bios.sh lenovo_bios.iso backup.bin output.bin
#

set -e

# Configuration
LENOVO_BIOS_URL="https://download.lenovo.com/pccbbs/mobiles/gjuj40us.iso"
EXPECTED_OUTPUT_SIZE=16777216  # 16MB

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Temp directory
TEMP_DIR=""
KEEP_TEMP=false

# Cleanup function
cleanup() {
    if [ "$KEEP_TEMP" = false ] && [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        echo -e "${YELLOW}Cleaning up temporary files...${NC}"
        rm -rf "$TEMP_DIR"
    elif [ "$KEEP_TEMP" = true ] && [ -n "$TEMP_DIR" ]; then
        echo -e "${YELLOW}Keeping temp files at: $TEMP_DIR${NC}"
    fi
}

trap cleanup EXIT

# Print colored messages
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if a command exists
check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Check all required dependencies
check_dependencies() {
    local missing=()

    info "Checking dependencies..."

    # Required commands
    if ! check_cmd "7z"; then
        missing+=("7z (p7zip-full on Debian/Ubuntu, p7zip p7zip-plugins on Fedora)")
    fi

    if ! check_cmd "UEFIExtract"; then
        missing+=("UEFIExtract (from https://github.com/LongSoft/UEFITool/releases)")
    fi

    if ! check_cmd "ifdtool"; then
        missing+=("ifdtool (coreboot-utils on Fedora, build from coreboot source on Debian/Ubuntu)")
    fi

    if ! check_cmd "wget"; then
        missing+=("wget")
    fi

    if ! check_cmd "perl"; then
        missing+=("perl (for geteltorito)")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing dependencies:\n$(printf '  - %s\n' "${missing[@]}")\n\nInstall instructions:\n  Fedora: sudo dnf install flashrom p7zip p7zip-plugins coreboot-utils wget perl\n  Debian/Ubuntu: sudo apt install flashrom p7zip-full ifdtool wget perl\n  UEFIExtract: Download from https://github.com/LongSoft/UEFITool/releases"
    fi

    info "All dependencies found."
}

# Download BIOS ISO from Lenovo
download_bios() {
    local output_iso="$1"

    info "Downloading BIOS from Lenovo..."
    wget -q --show-progress -O "$output_iso" "$LENOVO_BIOS_URL" || \
        error "Failed to download BIOS from $LENOVO_BIOS_URL"

    info "Downloaded: $output_iso"
}

# Download and run geteltorito to extract boot image
extract_boot_image() {
    local iso_file="$1"
    local output_img="$2"
    local geteltorito="$TEMP_DIR/geteltorito.pl"

    info "Downloading geteltorito..."
    wget -q -O "$geteltorito" "https://raw.githubusercontent.com/rainer042/geteltorito/master/geteltorito.pl" || \
        error "Failed to download geteltorito"
    chmod +x "$geteltorito"

    info "Extracting El Torito boot image from ISO..."
    perl "$geteltorito" -o "$output_img" "$iso_file" > /dev/null || \
        error "Failed to extract boot image from ISO"

    info "Extracted boot image: $output_img"
}

# Extract .FL1 file from boot image
extract_fl1() {
    local boot_img="$1"
    local extract_dir="$2"

    info "Extracting contents from boot image..."
    7z x -y "$boot_img" -o"$extract_dir" > /dev/null || \
        error "Failed to extract boot image with 7z"

    # Find the .FL1 file
    local fl1_file
    fl1_file=$(find "$extract_dir" -iname "*.FL1" -type f | head -1)

    if [ -z "$fl1_file" ]; then
        error "No .FL1 file found in boot image"
    fi

    info "Found FL1 file: $fl1_file"
    echo "$fl1_file"
}

# Extract BIOS body using UEFIExtract
extract_bios_body() {
    local fl1_file="$1"
    local output_dir="$2"

    info "Extracting BIOS components with UEFIExtract..."

    # Run UEFIExtract to dump all components
    UEFIExtract "$fl1_file" all > /dev/null 2>&1 || \
        error "UEFIExtract failed to process FL1 file"

    local dump_dir="${fl1_file}.dump"

    if [ ! -d "$dump_dir" ]; then
        error "UEFIExtract did not create expected dump directory"
    fi

    # Find the BIOS body - look for body.bin in the BIOS region path
    # The structure is typically: Intel image/BIOS region/Padding/*/body.bin
    local bios_body
    bios_body=$(find "$dump_dir" -path "*BIOS region*" -name "body.bin" -type f | head -1)

    if [ -z "$bios_body" ]; then
        # Alternative: look for any body.bin that's reasonably large (>5MB)
        warn "Could not find body.bin in BIOS region path, searching for largest body.bin..."
        bios_body=$(find "$dump_dir" -name "body.bin" -type f -size +5M | head -1)
    fi

    if [ -z "$bios_body" ]; then
        error "Could not find BIOS body in UEFIExtract output.\nDump directory: $dump_dir\nTry manual extraction with UEFITool GUI."
    fi

    local bios_size
    bios_size=$(stat -c%s "$bios_body" 2>/dev/null || stat -f%z "$bios_body")
    info "Found BIOS body: $bios_body ($bios_size bytes)"

    # Copy to output location
    cp "$bios_body" "$output_dir/bios_good.bin"
    echo "$output_dir/bios_good.bin"
}

# Extract regions from backup using ifdtool
extract_backup_regions() {
    local backup_file="$1"
    local output_dir="$2"

    info "Extracting regions from backup with ifdtool..."

    # ifdtool creates files in current directory, so we need to cd
    local orig_dir
    orig_dir=$(pwd)
    cd "$output_dir"

    ifdtool -x "$backup_file" > /dev/null 2>&1 || \
        error "ifdtool failed to extract backup regions"

    cd "$orig_dir"

    # Find the BIOS region file
    local bios_region
    bios_region=$(find "$output_dir" -name "*bios*" -type f | head -1)

    if [ -z "$bios_region" ]; then
        error "Could not find BIOS region in ifdtool output"
    fi

    local region_size
    region_size=$(stat -c%s "$bios_region" 2>/dev/null || stat -f%z "$bios_region")
    info "Found BIOS region: $bios_region ($region_size bytes)"

    echo "$bios_region"
}

# Pad BIOS and inject into backup
pad_and_inject() {
    local bios_good="$1"
    local bios_region="$2"
    local backup_file="$3"
    local output_file="$4"

    # Get sizes
    local bios_size region_size offset
    bios_size=$(stat -c%s "$bios_good" 2>/dev/null || stat -f%z "$bios_good")
    region_size=$(stat -c%s "$bios_region" 2>/dev/null || stat -f%z "$bios_region")
    offset=$((region_size - bios_size))

    info "BIOS size: $bios_size bytes"
    info "Region size: $region_size bytes"
    info "Padding offset: $offset bytes"

    if [ "$offset" -lt 0 ]; then
        error "BIOS image ($bios_size) is larger than region ($region_size)!"
    fi

    local padded_bios="$TEMP_DIR/padded_bios.bin"

    info "Creating padded BIOS image..."

    # Create blank image filled with 0xFF
    dd if=/dev/zero bs=1 count="$region_size" 2>/dev/null | tr '\0' '\377' > "$padded_bios"

    # Write BIOS at the correct offset
    dd if="$bios_good" of="$padded_bios" bs=1 seek="$offset" conv=notrunc 2>/dev/null

    # Verify padded size
    local padded_size
    padded_size=$(stat -c%s "$padded_bios" 2>/dev/null || stat -f%z "$padded_bios")

    if [ "$padded_size" -ne "$region_size" ]; then
        error "Padded BIOS size ($padded_size) doesn't match region size ($region_size)"
    fi

    info "Padded BIOS created: $padded_size bytes"

    # Inject into backup
    info "Injecting padded BIOS into backup..."
    ifdtool -i bios:"$padded_bios" "$backup_file" -O "$output_file" > /dev/null 2>&1 || \
        error "ifdtool failed to inject BIOS region"

    info "Created output file: $output_file"
}

# Verify final output
verify_output() {
    local output_file="$1"

    info "Verifying output..."

    if [ ! -f "$output_file" ]; then
        error "Output file not created: $output_file"
    fi

    local output_size
    output_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file")

    if [ "$output_size" -ne "$EXPECTED_OUTPUT_SIZE" ]; then
        error "Output size ($output_size) doesn't match expected size ($EXPECTED_OUTPUT_SIZE bytes / 16MB)"
    fi

    info "Output verified: $output_file ($output_size bytes)"
    echo -e "${GREEN}SUCCESS!${NC} Fixed BIOS image ready: $output_file"
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <iso_file|--download> <backup.bin> <output.bin>

Automate BIOS extraction for ThinkPad T440s 5-Beep Fix.

Arguments:
  iso_file      Path to Lenovo BIOS ISO file (e.g., gjuj40us.iso)
  --download    Auto-download the latest BIOS ISO from Lenovo
  backup.bin    Your original BIOS backup (from flashrom)
  output.bin    Output file for the fixed BIOS image

Options:
  --keep-temp   Keep temporary files for debugging
  -h, --help    Show this help message

Examples:
  # Auto-download latest BIOS from Lenovo
  $0 --download backup.bin fixed_bios.bin

  # Use your own ISO file
  $0 gjuj40us.iso backup.bin fixed_bios.bin
EOF
    exit 0
}

# Main function
main() {
    local iso_file=""
    local backup_file=""
    local output_file=""
    local download_mode=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --download)
                download_mode=true
                shift
                ;;
            --keep-temp)
                KEEP_TEMP=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [ "$download_mode" = true ]; then
                    if [ -z "$backup_file" ]; then
                        backup_file="$1"
                    elif [ -z "$output_file" ]; then
                        output_file="$1"
                    else
                        error "Too many arguments"
                    fi
                else
                    if [ -z "$iso_file" ]; then
                        iso_file="$1"
                    elif [ -z "$backup_file" ]; then
                        backup_file="$1"
                    elif [ -z "$output_file" ]; then
                        output_file="$1"
                    else
                        error "Too many arguments"
                    fi
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    if [ -z "$backup_file" ] || [ -z "$output_file" ]; then
        usage
    fi

    if [ "$download_mode" = false ] && [ -z "$iso_file" ]; then
        usage
    fi

    # Check backup file exists
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi

    # Convert to absolute paths
    backup_file=$(realpath "$backup_file")
    output_file=$(realpath -m "$output_file")

    if [ "$download_mode" = false ]; then
        if [ ! -f "$iso_file" ]; then
            error "ISO file not found: $iso_file"
        fi
        iso_file=$(realpath "$iso_file")
    fi

    echo "========================================"
    echo "  T440s BIOS Preparation Script"
    echo "========================================"
    echo ""

    # Check dependencies
    check_dependencies

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    info "Using temp directory: $TEMP_DIR"

    # Download ISO if needed
    if [ "$download_mode" = true ]; then
        iso_file="$TEMP_DIR/lenovo_bios.iso"
        download_bios "$iso_file"
    fi

    # Extract boot image from ISO
    local boot_img="$TEMP_DIR/bios_boot.img"
    extract_boot_image "$iso_file" "$boot_img"

    # Extract FL1 from boot image
    local extract_dir="$TEMP_DIR/bios_extract"
    mkdir -p "$extract_dir"
    local fl1_file
    fl1_file=$(extract_fl1 "$boot_img" "$extract_dir")

    # Extract BIOS body using UEFIExtract
    local bios_good
    bios_good=$(extract_bios_body "$fl1_file" "$TEMP_DIR")

    # Extract regions from backup
    local regions_dir="$TEMP_DIR/regions"
    mkdir -p "$regions_dir"
    local bios_region
    bios_region=$(extract_backup_regions "$backup_file" "$regions_dir")

    # Pad and inject
    pad_and_inject "$bios_good" "$bios_region" "$backup_file" "$output_file"

    # Verify
    verify_output "$output_file"

    echo ""
    echo "========================================"
    echo "  Next Steps:"
    echo "========================================"
    echo "  1. Connect CH341A programmer to T440s BIOS chip"
    echo "  2. Flash the fixed BIOS:"
    echo "     sudo flashrom -p ch341a_spi -w $output_file"
    echo "========================================"
}

main "$@"
