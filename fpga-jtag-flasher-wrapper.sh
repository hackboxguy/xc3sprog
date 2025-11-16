#!/bin/sh

# fpga-jtag-flasher-wrapper.sh - FPGA Flash Operations Wrapper for xc3sprog
# Handles flash, backup (dump), and revert operations with USB priority
# Based on USB detection logic from fpga-jtag-flasher.sh

set -e  # Exit on any error

# Set MICROPANEL_HOME with default fallback
MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default paths (can be overridden by environment or arguments)
DEFAULT_FPGA_FLASHER="$MICROPANEL_HOME/fpga/bin/fpga-jtag-flasher.sh"
DEFAULT_LATTICE_FLASHER="$MICROPANEL_HOME/fpga/bin/fpga-jtag-flasher-lattice.sh"
DEFAULT_BITBIN_DIR="$MICROPANEL_HOME/fpga/bitbin"
DEFAULT_BACKUP_DIR="$MICROPANEL_HOME/usr/backups"

# USB stick configuration
USB_MOUNT_POINT="/tmp/micropanel-usb"
USB_MOUNTED_BY_SCRIPT=0

VERBOSE=0

# Conditional sudo for USB operations
SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    # Not root, use sudo if available
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    fi
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1" >&2
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Detect USB stick device
detect_usb_stick() {
    for block_dev in /sys/block/sd*; do
        if [ ! -e "$block_dev" ]; then
            continue
        fi

        dev_name=$(basename "$block_dev")
        removable=$(cat "$block_dev/removable" 2>/dev/null || echo "0")

        if [ "$removable" = "1" ]; then
            # Found removable device, check for partitions
            for part in "$block_dev"/"$dev_name"*; do
                if [ -e "$part" ]; then
                    part_name=$(basename "$part")
                    if [ "$part_name" != "$dev_name" ]; then
                        echo "/dev/$part_name"
                        return 0
                    fi
                fi
            done

            # No partitions, try device itself
            echo "/dev/$dev_name"
            return 0
        fi
    done

    return 1
}

# Detect filesystem type
detect_filesystem() {
    local device="$1"

    if command -v blkid >/dev/null 2>&1; then
        local fstype=$($SUDO_CMD blkid -s TYPE -o value "$device" 2>/dev/null | head -n1)
        if [ -n "$fstype" ]; then
            echo "$fstype"
            return 0
        fi
    fi

    # Default to vfat
    echo "vfat"
    return 0
}

# Mount USB stick
mount_usb_stick() {
    local device="$1"

    # Check if already mounted
    if mount | grep -q "$USB_MOUNT_POINT"; then
        echo "$USB_MOUNT_POINT"
        return 0
    fi

    # Create mount point
    if [ ! -d "$USB_MOUNT_POINT" ]; then
        if ! $SUDO_CMD mkdir -p "$USB_MOUNT_POINT" 2>/dev/null; then
            return 1
        fi
    fi

    # Detect and mount
    local fstype=$(detect_filesystem "$device")

    if $SUDO_CMD mount -t "$fstype" "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        USB_MOUNTED_BY_SCRIPT=1
        echo "$USB_MOUNT_POINT"
        return 0
    else
        # Try auto-detection
        if $SUDO_CMD mount "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
            USB_MOUNTED_BY_SCRIPT=1
            echo "$USB_MOUNT_POINT"
            return 0
        fi
    fi

    return 1
}

# Unmount USB stick
unmount_usb_stick() {
    if [ -d "$USB_MOUNT_POINT" ] && mount | grep -q "$USB_MOUNT_POINT"; then
        # Sync filesystem
        if [ $VERBOSE -eq 1 ]; then
            log_info "Syncing filesystem before unmount..."
        fi
        sync
        sleep 1

        if [ $VERBOSE -eq 1 ]; then
            log_info "Unmounting USB stick from: $USB_MOUNT_POINT"
        fi
        if $SUDO_CMD umount "$USB_MOUNT_POINT" 2>/dev/null; then
            if [ $VERBOSE -eq 1 ]; then
                log_success "USB stick unmounted successfully"
            fi
            USB_MOUNTED_BY_SCRIPT=0
            return 0
        else
            if [ $VERBOSE -eq 1 ]; then
                log_warning "Failed to unmount USB stick"
            fi
            return 1
        fi
    fi
    return 0
}

# Resolve input file with USB priority
resolve_input_file() {
    local usb_file="$1"
    local local_file="$2"

    # Try USB first
    local usb_device
    if usb_device=$(detect_usb_stick); then
        local mount_point
        if mount_point=$(mount_usb_stick "$usb_device"); then
            if [ -f "$mount_point/$usb_file" ]; then
                log_info "Using file from USB stick: $mount_point/$usb_file"
                echo "$mount_point/$usb_file"
                return 0
            fi
        fi
    fi

    # Fallback to local
    if [ -f "$local_file" ]; then
        log_info "Using local file: $local_file"
        echo "$local_file"
        return 0
    fi

    log_error "File not found: $usb_file (checked USB and $local_file)"
    return 1
}

# Show usage
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

FPGA Flash Operations Wrapper for xc3sprog tools

OPTIONS:
    --operation=OP         Operation: flash, dump, revert
    --file=NAME            Base filename (without extension)
    --fpga-type=TYPE       FPGA type: xilinx or lattice
    --size=BYTES           Flash size in bytes (required for dump)
    --bitbin-dir=DIR       Bitstream directory (default: $DEFAULT_BITBIN_DIR)
    --backup-dir=DIR       Backup directory (default: $DEFAULT_BACKUP_DIR)
    --verbose              Enable verbose output

OPERATIONS:
    flash    Flash bitstream to FPGA
    dump     Backup flash contents to USB/local
    revert   Restore from backup

EXAMPLES:
    # Flash Xilinx FPGA
    $(basename "$0") --operation=flash --file=12-3-inch --fpga-type=xilinx

    # Backup Xilinx FPGA flash
    $(basename "$0") --operation=dump --file=12-3-inch --fpga-type=xilinx --size=2192012

    # Flash Lattice FPGA
    $(basename "$0") --operation=flash --file=15-6-2k5 --fpga-type=lattice

    # Backup Lattice FPGA flash
    $(basename "$0") --operation=dump --file=15-6-2k5 --fpga-type=lattice --size=1078990

    # Revert from backup
    $(basename "$0") --operation=revert --file=12-3-inch --fpga-type=xilinx

EOF
}

# Main function
main() {
    local operation=""
    local filename=""
    local fpga_type="xilinx"  # Default to Xilinx
    local dump_size=""
    local bitbin_dir="$DEFAULT_BITBIN_DIR"
    local backup_dir="$DEFAULT_BACKUP_DIR"
    local fpga_flasher="$DEFAULT_FPGA_FLASHER"
    local lattice_flasher="$DEFAULT_LATTICE_FLASHER"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case $1 in
            --operation=*)
                operation="${1#*=}"
                shift
                ;;
            --file=*)
                filename="${1#*=}"
                shift
                ;;
            --fpga-type=*)
                fpga_type="${1#*=}"
                shift
                ;;
            --size=*)
                dump_size="${1#*=}"
                shift
                ;;
            --bitbin-dir=*)
                bitbin_dir="${1#*=}"
                shift
                ;;
            --backup-dir=*)
                backup_dir="${1#*=}"
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate inputs
    if [ -z "$operation" ]; then
        log_error "No operation specified"
        show_usage
        exit 1
    fi

    if [ -z "$filename" ]; then
        log_error "No filename specified"
        show_usage
        exit 1
    fi

    # Determine file extension based on FPGA type
    local file_ext
    if [ "$fpga_type" = "lattice" ]; then
        file_ext="bit"
        flasher_tool="$lattice_flasher"
    else
        file_ext="bin"
        flasher_tool="$fpga_flasher"
    fi

    # Execute operation
    case "$operation" in
        flash)
            log_info "Operation: Flash FPGA ($fpga_type)"

            # Resolve bitstream file (USB priority)
            local bitstream_file
            if ! bitstream_file=$(resolve_input_file "${filename}.${file_ext}" "${bitbin_dir}/${filename}.${file_ext}"); then
                unmount_usb_stick
                exit 1
            fi

            log_info "Flashing from: $bitstream_file"

            # Flash using appropriate tool
            if [ "$fpga_type" = "lattice" ]; then
                if ! $SUDO_CMD "$flasher_tool" --flash="$bitstream_file"; then
                    log_error "Flash operation failed"
                    unmount_usb_stick
                    exit 1
                fi
            else
                if ! "$flasher_tool" --flash="$bitstream_file"; then
                    log_error "Flash operation failed"
                    unmount_usb_stick
                    exit 1
                fi
            fi

            log_success "Flash operation completed successfully"
            unmount_usb_stick
            ;;

        dump)
            # Dump to temporary location first, then copy to USB or local backup
            log_info "Operation: Dump FPGA flash to backup ($fpga_type)"

            if [ -z "$dump_size" ]; then
                log_error "Dump size not specified (use --size=BYTES)"
                exit 1
            fi

            # Create temporary dump file
            local temp_dump="/tmp/fpga-dump-$$.bin"
            log_info "Dumping to temporary file: $temp_dump"

            # Dump using appropriate tool
            if [ "$fpga_type" = "lattice" ]; then
                if ! $SUDO_CMD "$flasher_tool" --dump="$temp_dump" --size="$dump_size"; then
                    log_error "Dump operation failed"
                    rm -f "$temp_dump"
                    unmount_usb_stick
                    exit 1
                fi
            else
                if ! "$flasher_tool" --dump="$temp_dump" --size="$dump_size"; then
                    log_error "Dump operation failed"
                    rm -f "$temp_dump"
                    unmount_usb_stick
                    exit 1
                fi
            fi

            # Verify temp file was created
            if [ ! -f "$temp_dump" ]; then
                log_error "Dump file was not created: $temp_dump"
                unmount_usb_stick
                exit 1
            fi

            local file_size=$(stat -c%s "$temp_dump" 2>/dev/null || echo "0")
            log_info "Dump completed successfully (size: $file_size bytes)"

            # Generate timestamp for archive copy
            local timestamp=$(date +%Y%m%d-%H%M%S)
            local base_filename="${filename}.bin.bkup"
            local archive_filename="${filename}-${timestamp}.bin.bkup"

            # Try to detect and mount USB stick for output
            local usb_device
            local final_destination="local backup"

            if usb_device=$(detect_usb_stick); then
                log_info "USB stick detected for backup storage"
                local mount_point
                if mount_point=$(mount_usb_stick "$usb_device"); then
                    log_info "Copying dump to USB stick..."

                    # Copy as base filename (for easy restore)
                    if $SUDO_CMD cp "$temp_dump" "$mount_point/$base_filename"; then
                        log_success "Created restore point: $mount_point/$base_filename"
                    else
                        log_error "Failed to copy base file to USB"
                    fi

                    # Copy as timestamped archive
                    if $SUDO_CMD cp "$temp_dump" "$mount_point/$archive_filename"; then
                        log_success "Created archive: $mount_point/$archive_filename"
                        final_destination="USB stick"
                    else
                        log_error "Failed to copy archive to USB"
                    fi

                    # Sync and unmount
                    sync
                    sleep 2  # Give more time for large file sync
                    unmount_usb_stick
                else
                    log_warning "Failed to mount USB stick, using local backup"
                fi
            else
                log_info "No USB stick detected, using local backup"
            fi

            # If USB failed or not available, save to local backup
            if [ "$final_destination" = "local backup" ]; then
                # Ensure backup directory exists
                mkdir -p "$backup_dir"

                log_info "Copying dump to local backup directory..."

                # Copy as base filename (for easy restore)
                if cp "$temp_dump" "${backup_dir}/$base_filename"; then
                    log_success "Created restore point: ${backup_dir}/$base_filename"
                else
                    log_error "Failed to copy base file to local backup"
                fi

                # Copy as timestamped archive
                if cp "$temp_dump" "${backup_dir}/$archive_filename"; then
                    log_success "Created archive: ${backup_dir}/$archive_filename"
                else
                    log_error "Failed to copy archive to local backup"
                fi
            fi

            # Clean up temporary file
            rm -f "$temp_dump"
            log_info "Temporary dump file cleaned up"

            log_success "Dump operation completed successfully"
            log_info "Backup location: $final_destination"
            ;;

        revert)
            # Flash from backup with USB priority
            log_info "Operation: Revert FPGA from backup ($fpga_type)"

            local input_file
            if ! input_file=$(resolve_input_file "${filename}.bin.bkup" "${backup_dir}/${filename}.bin.bkup"); then
                unmount_usb_stick
                exit 1
            fi

            log_info "Found backup file: $input_file"

            # Copy backup to temporary .bin file
            local temp_revert="/tmp/fpga-revert-$$.bin"
            log_info "Copying backup to temporary file: $temp_revert"

            if ! cp "$input_file" "$temp_revert"; then
                log_error "Failed to copy backup file to temporary location"
                unmount_usb_stick
                exit 1
            fi

            log_info "Reverting from: $temp_revert"

            # Flash using appropriate tool
            if [ "$fpga_type" = "lattice" ]; then
                if ! $SUDO_CMD "$flasher_tool" --flash="$temp_revert"; then
                    log_error "Revert operation failed"
                    rm -f "$temp_revert"
                    unmount_usb_stick
                    exit 1
                fi
            else
                if ! "$flasher_tool" --flash="$temp_revert"; then
                    log_error "Revert operation failed"
                    rm -f "$temp_revert"
                    unmount_usb_stick
                    exit 1
                fi
            fi

            # Clean up temporary file
            rm -f "$temp_revert"
            log_info "Temporary revert file cleaned up"

            log_success "Revert operation completed successfully"
            unmount_usb_stick
            ;;

        *)
            log_error "Unknown operation: $operation"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
