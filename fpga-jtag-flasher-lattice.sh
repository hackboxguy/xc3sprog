#!/bin/sh

# FPGA JTAG Flasher for Lattice devices using openFPGALoader
# Wrapper script for Pi4 GPIO bit-banging JTAG interface
# Author: Embedded developer with 25 years experience
# Compatible with both /bin/sh and /bin/bash

# Configuration
OPENFPGALOADER_PATH="/home/pi/micropanel/fpga/bin/openFPGALoader"
CABLE="libgpiod"
PINS="21:20:16:26"  # TDI:TDO:TCK:TMS
VERBOSE_LEVEL=""    # Default: quiet mode
VERBOSE_MODE=0      # Flag for verbose output

# USB stick configuration
USB_MOUNT_POINT="/tmp/micropanel-usb"
USB_MOUNTED_BY_SCRIPT=0

# Function to print colored messages (compatible with sh)
# All output goes to stderr to avoid mixing with function return values
print_success() {
    printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$1" >&2
}

print_error() {
    printf "\033[0;31m[ERROR]\033[0m %s\n" "$1" >&2
}

print_info() {
    printf "\033[1;33m[INFO]\033[0m %s\n" "$1" >&2
}

# USB stick detection and mounting functions
detect_usb_stick() {
    print_info "Checking for USB stick..."

    # Dynamically detect all block devices
    local usb_device=""

    # Check all /dev/sd* block devices
    for block_dev in /sys/block/sd*; do
        if [ ! -e "$block_dev" ]; then
            continue
        fi

        local dev_name=$(basename "$block_dev")
        local removable=$(cat "$block_dev/removable" 2>/dev/null || echo "0")

        # Check if it's removable (USB sticks have removable=1)
        if [ "$removable" = "1" ]; then
            # Found a removable device, now find its first partition
            if [ -e "/dev/${dev_name}1" ]; then
                usb_device="/dev/${dev_name}1"
            elif [ -e "/dev/${dev_name}" ]; then
                usb_device="/dev/${dev_name}"
            fi

            if [ -n "$usb_device" ]; then
                print_info "Found USB stick: $usb_device (removable)"
                if [ $VERBOSE_MODE -eq 1 ]; then
                    # Show additional device info
                    local size=$(cat "$block_dev/size" 2>/dev/null || echo "unknown")
                    local vendor=$(cat "$block_dev/device/vendor" 2>/dev/null | tr -d ' ' || echo "unknown")
                    local model=$(cat "$block_dev/device/model" 2>/dev/null | tr -d ' ' || echo "unknown")
                    print_info "Device: $vendor $model, Size: $size blocks"
                fi
                echo "$usb_device"
                return 0
            fi
        fi
    done

    if [ $VERBOSE_MODE -eq 1 ]; then
        print_info "No USB stick detected"
    fi
    return 1
}

detect_filesystem() {
    local device="$1"

    # Try to detect filesystem using blkid (most reliable)
    if command -v blkid >/dev/null 2>&1; then
        local fstype=$(sudo blkid -o value -s TYPE "$device" 2>/dev/null)
        if [ -n "$fstype" ]; then
            echo "$fstype"
            return 0
        fi
    fi

    # Fallback: try file command
    if command -v file >/dev/null 2>&1; then
        local file_output=$(sudo file -s "$device" 2>/dev/null)
        if echo "$file_output" | grep -qi "FAT"; then
            echo "vfat"
            return 0
        elif echo "$file_output" | grep -qi "NTFS"; then
            echo "ntfs-3g"
            return 0
        elif echo "$file_output" | grep -qi "exFAT"; then
            echo "exfat"
            return 0
        fi
    fi

    # Default: assume vfat (most common for USB sticks)
    echo "vfat"
    return 0
}

mount_usb_stick() {
    local device="$1"

    # Check if already mounted
    if mount | grep -q "$device"; then
        local existing_mount=$(mount | grep "$device" | awk '{print $3}' | head -1)
        print_info "USB stick already mounted at: $existing_mount"
        echo "$existing_mount"
        USB_MOUNTED_BY_SCRIPT=0
        return 0
    fi

    # Create mount point if it doesn't exist
    if [ ! -d "$USB_MOUNT_POINT" ]; then
        print_info "Creating mount point: $USB_MOUNT_POINT"
        if ! sudo mkdir -p "$USB_MOUNT_POINT"; then
            print_error "Failed to create mount point: $USB_MOUNT_POINT"
            return 1
        fi
    fi

    # Detect filesystem type
    local fstype=$(detect_filesystem "$device")
    print_info "Detected filesystem type: $fstype"

    # Mount the USB stick with appropriate filesystem type
    print_info "Mounting USB stick to: $USB_MOUNT_POINT"

    # Try mounting with detected filesystem type
    if sudo mount -t "$fstype" "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        print_success "USB stick mounted successfully (type: $fstype)"
        USB_MOUNTED_BY_SCRIPT=1
        echo "$USB_MOUNT_POINT"
        return 0
    else
        # If specific type fails, try auto-detection
        print_info "Trying auto-detection..."
        if sudo mount "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
            print_success "USB stick mounted successfully (auto-detected)"
            USB_MOUNTED_BY_SCRIPT=1
            echo "$USB_MOUNT_POINT"
            return 0
        else
            print_error "Failed to mount USB stick"
            if [ $VERBOSE_MODE -eq 1 ]; then
                print_error "Try installing required packages:"
                print_error "  For NTFS: sudo apt-get install ntfs-3g"
                print_error "  For exFAT: sudo apt-get install exfat-fuse exfat-utils"
            fi
            return 1
        fi
    fi
}

unmount_usb_stick() {
    # Always try to unmount if mount point exists and is mounted
    if [ -d "$USB_MOUNT_POINT" ] && mount | grep -q "$USB_MOUNT_POINT"; then
        print_info "Unmounting USB stick from: $USB_MOUNT_POINT"
        if sudo umount "$USB_MOUNT_POINT" 2>/dev/null; then
            print_success "USB stick unmounted successfully"
            USB_MOUNTED_BY_SCRIPT=0
            return 0
        else
            if [ $VERBOSE_MODE -eq 1 ]; then
                print_info "Failed to unmount USB stick (may still be in use)"
            fi
            return 1
        fi
    fi
    return 0
}

find_file_on_usb() {
    local filename="$1"
    local mount_point="$2"

    print_info "Searching for file '$filename' on USB stick..."

    # Use find to search recursively for the exact filename
    local found_file=$(find "$mount_point" -type f -name "$filename" 2>/dev/null | head -1)

    if [ -n "$found_file" ] && [ -f "$found_file" ]; then
        print_success "Found file on USB stick: $found_file"
        echo "$found_file"
        return 0
    else
        if [ $VERBOSE_MODE -eq 1 ]; then
            print_info "File '$filename' not found on USB stick"
        fi
        return 1
    fi
}

resolve_flash_file() {
    local default_path="$1"
    local final_file="$default_path"

    # Extract just the filename from the full path
    local filename=$(basename "$default_path")

    print_info "Resolving flash file: $filename"
    print_info "Default path: $default_path"

    # Try to detect and mount USB stick
    local usb_device
    if usb_device=$(detect_usb_stick); then
        print_info "USB stick detected: $usb_device"

        # Try to mount the USB stick
        local mount_point
        if mount_point=$(mount_usb_stick "$usb_device"); then
            print_info "USB stick mounted at: $mount_point"

            # Search for the file on USB stick
            local usb_file
            if usb_file=$(find_file_on_usb "$filename" "$mount_point"); then
                print_success "Using file from USB stick (PRIORITY): $usb_file"
                final_file="$usb_file"
            else
                print_info "File not found on USB stick, falling back to internal path"
                print_info "Using internal file: $default_path"
            fi
        else
            print_info "Failed to mount USB stick, using internal path"
            print_info "Using internal file: $default_path"
        fi
    else
        if [ $VERBOSE_MODE -eq 1 ]; then
            print_info "No USB stick detected, using internal path"
        fi
        print_info "Using internal file: $default_path"
    fi

    # Validate final file exists
    if [ ! -f "$final_file" ]; then
        print_error "Flash file not found: $final_file"
        return 1
    fi

    echo "$final_file"
    return 0
}

# Function to check if openFPGALoader exists
check_openfpgaloader() {
    if [ ! -f "$OPENFPGALOADER_PATH" ]; then
        print_error "openFPGALoader not found at: $OPENFPGALOADER_PATH"
        print_info "Please build openFPGALoader or update OPENFPGALOADER_PATH in script"
        exit 1
    fi
}

# Function to parse JTAG info and format output
get_jtag_info() {
    temp_file=$(mktemp)
    
    # Always use verbose mode for info detection to get all details
    sudo $OPENFPGALOADER_PATH -c $CABLE --pins=$PINS --detect -f -v > "$temp_file" 2>&1
    
    if [ $? -ne 0 ]; then
        print_error "Failed to detect FPGA via JTAG"
        if [ $VERBOSE_MODE -eq 1 ]; then
            cat "$temp_file"
        fi
        rm -f "$temp_file"
        exit 1
    fi
    
    # Parse the output using portable methods
    idcode=$(grep "idcode" "$temp_file" | awk '{print $2}' | head -1)
    manufacturer=$(grep "manufacturer" "$temp_file" | awk '{print $2}' | head -1)
    family=$(grep "family" "$temp_file" | awk '{print $2}' | head -1)
    model=$(grep "model" "$temp_file" | awk '{print $2}' | head -1)
    jedec_full=$(grep "JEDEC ID:" "$temp_file" | awk '{print $3}' | head -1)
    flash_name=$(grep "Detected:" "$temp_file" | sed 's/.*Detected: //' | awk '{print $1 " " $2}' | head -1)
    
    # Debug output in verbose mode
    if [ $VERBOSE_MODE -eq 1 ]; then
        print_info "Raw parsing results:"
        print_info "idcode=$idcode"
        print_info "manufacturer=$manufacturer"
        print_info "model=$model"
        print_info "jedec_full=$jedec_full"
        print_info "flash_name=$flash_name"
    fi
    
    # Extract JEDEC components (portable string manipulation)
    jedec_clean=$(echo "$jedec_full" | sed 's/0x//')
    jedec_byte1=$(echo "$jedec_clean" | cut -c1-2)
    jedec_byte2=$(echo "$jedec_clean" | cut -c3-4)
    jedec_byte3=$(echo "$jedec_clean" | cut -c5-6)
    
    # Create device name
    device_name="$model"
    if [ "$manufacturer" = "lattice" ]; then
        device_name=$(echo "$device_name" | tr '[:lower:]' '[:upper:]')
    fi
    
    # Format and print result
    print_success "IDCODE=$idcode : DEVICE=$device_name : FLASH=$flash_name : SPI-FLASH-JEDEC=$jedec_byte1$jedec_byte2 0x$jedec_byte3 0x$jedec_byte1"
    
    rm -f "$temp_file"
}

# Function to detect file type and program flash
program_flash() {
    file_path="$1"

    # Resolve flash file with USB stick priority
    local resolved_file
    if ! resolved_file=$(resolve_flash_file "$file_path"); then
        print_error "Failed to resolve flash file"
        unmount_usb_stick
        exit 1
    fi

    # Use the resolved file (either from USB or internal)
    file_path="$resolved_file"
    
    # Get file extension using portable method
    extension=$(echo "$file_path" | sed 's/.*\.//')
    flash_cmd=""
    
    case "$extension" in
        "bit")
            if [ $VERBOSE_MODE -eq 1 ]; then
                print_info "Detected bitstream file (.bit)"
            fi
            flash_cmd="sudo $OPENFPGALOADER_PATH -c $CABLE --pins=$PINS -f \"$file_path\" --verify $VERBOSE_LEVEL"
            ;;
        "bin")
            if [ $VERBOSE_MODE -eq 1 ]; then
                print_info "Detected binary file (.bin)"
            fi
            flash_cmd="sudo $OPENFPGALOADER_PATH -c $CABLE --pins=$PINS -f \"$file_path\" --file-type bin --verify $VERBOSE_LEVEL"
            ;;
        *)
            print_error "Unsupported file type: .$extension"
            print_info "Supported types: .bit (bitstream), .bin (binary)"
            unmount_usb_stick
            exit 1
            ;;
    esac
    
    if [ $VERBOSE_MODE -eq 1 ]; then
        print_info "Starting flash programming..."
        print_info "File: $file_path"
        if command -v du >/dev/null 2>&1; then
            file_size=$(du -h "$file_path" | cut -f1)
            print_info "Size: $file_size"
        fi
    fi
    
    # Create temp file for output
    temp_file=$(mktemp)
    
    # Execute programming command
    eval $flash_cmd > "$temp_file" 2>&1
    result=$?
    
    # Show progress (openFPGALoader shows progress bars)
    if [ $result -eq 0 ]; then
        # Check if all critical operations completed successfully
        # Look for key completion indicators
        has_refresh=$(grep -c "Refresh: DONE" "$temp_file")
        has_writing=$(grep -c "Writing:" "$temp_file")
        has_reading=$(grep -c "Reading:" "$temp_file")
        
        # For success, we need: Refresh DONE, Writing progress, and Reading (verification)
        if [ $has_refresh -gt 0 ] && [ $has_writing -gt 0 ] && [ $has_reading -gt 0 ]; then
            print_success "Flash programming completed successfully!"
            if [ $VERBOSE_MODE -eq 1 ]; then
                print_info "FPGA will configure from flash on next power cycle"
            fi
            rm -f "$temp_file"
            unmount_usb_stick
            return 0
        else
            print_error "Programming completed but verification may have failed"
            if [ $VERBOSE_MODE -eq 1 ]; then
                echo "Details: Missing completion indicators"
                echo "has_refresh=$has_refresh, has_writing=$has_writing, has_reading=$has_reading"
                cat "$temp_file"
            fi
            rm -f "$temp_file"
            unmount_usb_stick
            exit 1
        fi
    else
        print_error "Flash programming failed"
        if [ $VERBOSE_MODE -eq 1 ]; then
            echo "Details:"
            cat "$temp_file"
        fi
        rm -f "$temp_file"
        unmount_usb_stick
        exit 1
    fi
}

# Function to dump flash contents
dump_flash() {
    dump_path="$1"
    dump_size="$2"
    
    # Validate dump size (portable numeric check)
    case "$dump_size" in
        ''|*[!0-9]*) 
            print_error "Invalid dump size: $dump_size"
            print_info "Size must be a positive integer (bytes)"
            exit 1
            ;;
        *)
            if [ "$dump_size" -le 0 ]; then
                print_error "Invalid dump size: $dump_size"
                print_info "Size must be a positive integer (bytes)"
                exit 1
            fi
            ;;
    esac
    
    # Check if target directory exists
    dump_dir=$(dirname "$dump_path")
    if [ ! -d "$dump_dir" ]; then
        print_error "Directory does not exist: $dump_dir"
        exit 1
    fi
    
    # Convert size to human readable (portable arithmetic)
    size_mb=$((dump_size / 1024 / 1024))
    size_kb=$((dump_size / 1024))
    
    if [ $size_mb -gt 0 ]; then
        size_human="${size_mb}MB"
    elif [ $size_kb -gt 0 ]; then
        size_human="${size_kb}KB"
    else
        size_human="${dump_size}B"
    fi
    
    if [ $VERBOSE_MODE -eq 1 ]; then
        print_info "Starting flash dump..."
        print_info "Output file: $dump_path"
        print_info "Dump size: $size_human ($dump_size bytes)"
        
        # Check for large dumps and warn
        if [ $dump_size -gt 1048576 ]; then  # > 1MB
            print_info "Large dump detected - this may take several minutes over GPIO"
        fi
    fi
    
    # Create temp file for output
    temp_file=$(mktemp)
    
    # Execute dump command
    sudo $OPENFPGALOADER_PATH -c $CABLE --pins=$PINS --dump-flash "$dump_path" --file-size $dump_size $VERBOSE_LEVEL > "$temp_file" 2>&1
    result=$?
    
    if [ $result -eq 0 ]; then
        # Verify the dump file was created and has correct size
        if [ -f "$dump_path" ]; then
            # Get file size using portable method
            if command -v stat >/dev/null 2>&1; then
                actual_size=$(stat -c%s "$dump_path" 2>/dev/null || echo "0")
            else
                # Fallback method for systems without stat
                actual_size=$(ls -l "$dump_path" | awk '{print $5}')
            fi
            
            if [ "$actual_size" -eq "$dump_size" ]; then
                print_success "Flash dump completed successfully!"
                if [ $VERBOSE_MODE -eq 1 ]; then
                    print_info "Dumped $size_human to: $dump_path"
                fi
            else
                print_error "Dump file size mismatch. Expected: $dump_size, Got: $actual_size"
                if [ $VERBOSE_MODE -eq 1 ]; then
                    cat "$temp_file"
                fi
                exit 1
            fi
        else
            print_error "Dump file was not created: $dump_path"
            if [ $VERBOSE_MODE -eq 1 ]; then
                cat "$temp_file"
            fi
            exit 1
        fi
    else
        print_error "Flash dump failed"
        if [ $VERBOSE_MODE -eq 1 ]; then
            echo "Details:"
            cat "$temp_file"
        fi
        rm -f "$temp_file"
        exit 1
    fi
    
    rm -f "$temp_file"
}

# Function to show usage
show_usage() {
    echo "FPGA JTAG Flasher for Lattice devices"
    echo "Usage:"
    echo "  $0 --info                    : Show JTAG chain and flash information"
    echo "  $0 --flash=<file>           : Program bitstream (.bit) or binary (.bin) to flash"
    echo "  $0 --dump=<file> --size=<bytes> : Dump flash contents to file"
    echo "  $0 --verbose                : Enable verbose output for any operation"
    echo ""
    echo "Examples:"
    echo "  $0 --info"
    echo "  $0 --flash=/home/pi/tmp/fpga.bit"
    echo "  $0 --flash=/home/pi/backup.bin --verbose"
    echo "  $0 --dump=/home/pi/tmp/64kb-dump.bin --size=65536"
    echo "  $0 --dump=/home/pi/full-flash.bin --size=4194304 --verbose"
    echo ""
    echo "Common dump sizes:"
    echo "  4KB:    --size=4096"
    echo "  64KB:   --size=65536"
    echo "  1MB:    --size=1048576"
    echo "  4MB:    --size=4194304    (full IS25LP032D flash)"
    echo ""
    echo "Configuration:"
    echo "  Cable: $CABLE"
    echo "  Pins: $PINS (TDI:TDO:TCK:TMS)"
    echo "  Tool: $OPENFPGALOADER_PATH"
}

# Main script logic
main() {
    # Check if running as root or with sudo for GPIO access
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script requires root privileges for GPIO access"
        print_info "Please run with sudo: sudo $0 $*"
        exit 1
    fi
    
    # Check prerequisites
    check_openfpgaloader
    
    # Parse command line arguments
    dump_file=""
    dump_size=""
    flash_file=""
    
    # Parse all arguments
    for arg in "$@"; do
        case "$arg" in
            "--info")
                if [ $VERBOSE_MODE -eq 1 ]; then
                    print_info "Detecting FPGA and flash information..."
                fi
                get_jtag_info
                exit 0
                ;;
            --flash=*)
                flash_file=$(echo "$arg" | sed 's/--flash=//')
                ;;
            --dump=*)
                dump_file=$(echo "$arg" | sed 's/--dump=//')
                ;;
            --size=*)
                dump_size=$(echo "$arg" | sed 's/--size=//')
                ;;
            "--verbose")
                VERBOSE_MODE=1
                VERBOSE_LEVEL="-v"
                ;;
            "--help"|"-h")
                show_usage
                exit 0
                ;;
            "")
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $arg"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Handle dump operation
    if [ -n "$dump_file" ]; then
        if [ -z "$dump_size" ]; then
            print_error "Dump operation requires --size parameter"
            print_info "Example: $0 --dump=/home/pi/dump.bin --size=65536"
            exit 1
        fi
        dump_flash "$dump_file" "$dump_size"
        exit 0
    fi
    
    # Handle flash operation
    if [ -n "$flash_file" ]; then
        program_flash "$flash_file"
        exit 0
    fi
    
    # If no valid operation specified, show usage
    show_usage
}

# Execute main function with all arguments
main "$@"
