#!/bin/sh
# xc3sprog-xpc2.sh - Firmware loader for Xilinx Platform Cable USB II (Waveshare clone)
#
# This script loads firmware to the Waveshare Platform Cable USB (VID:PID 03fd:0013)
# The cable uses a Cypress FX2LP microcontroller that boots without firmware and
# requires firmware to be loaded into RAM before it can be used for JTAG operations.
#
# Usage:
#   xc3sprog-xpc2.sh --xpc-firmware=/path/to/xusb_xp2.hex
#   xc3sprog-xpc2.sh --xpc-firmware=/path/to/xusb_xp2.hex --verbose
#
# Exit codes:
#   0 - Firmware loaded successfully (or already loaded)
#   1 - Cable not found
#   2 - Firmware file not found or not readable
#   3 - fxload not found
#   4 - Firmware loading failed

set -e

# Default values
FIRMWARE=""
VERBOSE=0
FORCE_RELOAD=0

# USB Vendor/Product IDs for Xilinx Platform Cable USB II
USB_VID="03fd"
USB_PID="0013"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --xpc-firmware=*)
            FIRMWARE="${1#*=}"
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --force)
            FORCE_RELOAD=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --xpc-firmware=<path> [--verbose] [--force]"
            echo ""
            echo "Load firmware to Xilinx Platform Cable USB II (Waveshare clone)"
            echo ""
            echo "Options:"
            echo "  --xpc-firmware=PATH   Path to xusb_xp2.hex firmware file (required)"
            echo "  --verbose, -v         Enable verbose output"
            echo "  --force               Force firmware reload even if already loaded"
            echo "  --help, -h            Show this help message"
            echo ""
            echo "Exit codes:"
            echo "  0 - Success (firmware loaded or already loaded)"
            echo "  1 - Cable not found"
            echo "  2 - Firmware file not found or not readable"
            echo "  3 - fxload utility not found"
            echo "  4 - Firmware loading failed"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Run '$0 --help' for usage information" >&2
            exit 1
            ;;
    esac
done

# Check if firmware path was provided
if [ -z "$FIRMWARE" ]; then
    echo "ERROR: --xpc-firmware parameter is required" >&2
    echo "Usage: $0 --xpc-firmware=/path/to/xusb_xp2.hex" >&2
    exit 2
fi

# Check if firmware file exists and is readable
if [ ! -f "$FIRMWARE" ]; then
    echo "ERROR: Firmware file not found: $FIRMWARE" >&2
    exit 2
fi

if [ ! -r "$FIRMWARE" ]; then
    echo "ERROR: Firmware file not readable: $FIRMWARE" >&2
    exit 2
fi

# Check if fxload is available
if ! command -v fxload >/dev/null 2>&1; then
    echo "ERROR: fxload utility not found" >&2
    echo "Please install fxload: sudo apt-get install fxload" >&2
    exit 3
fi

# Find the Xilinx Platform Cable USB II device
DEVICE_LINE=$(lsusb | grep "${USB_VID}:${USB_PID}" | head -n 1)

if [ -z "$DEVICE_LINE" ]; then
    echo "ERROR: Xilinx Platform Cable USB II not found (VID:PID ${USB_VID}:${USB_PID})" >&2
    echo "Please connect the Waveshare cable" >&2
    exit 1
fi

# Extract bus and device numbers
BUS=$(echo "$DEVICE_LINE" | sed -E 's/Bus ([0-9]+) Device ([0-9]+).*/\1/')
DEV=$(echo "$DEVICE_LINE" | sed -E 's/Bus ([0-9]+) Device ([0-9]+).*/\2/')
DEVICE_PATH="/dev/bus/usb/${BUS}/${DEV}"

if [ $VERBOSE -eq 1 ]; then
    echo "Found device: Bus $BUS Device $DEV"
    echo "Device path: $DEVICE_PATH"
fi

# Check if firmware is already loaded by examining USB descriptors
# If iManufacturer is 0, firmware is not loaded
NEED_FIRMWARE=0

if [ $FORCE_RELOAD -eq 0 ]; then
    # Check if manufacturer string is empty (indicates no firmware)
    # Look for "iManufacturer 0" (with optional whitespace)
    MFR_VALUE=$(lsusb -v -d ${USB_VID}:${USB_PID} 2>/dev/null | grep "iManufacturer" | awk '{print $2}' || true)

    if [ "$MFR_VALUE" = "0" ]; then
        NEED_FIRMWARE=1
        if [ $VERBOSE -eq 1 ]; then
            echo "Firmware not loaded (iManufacturer=0)"
        fi
    else
        if [ $VERBOSE -eq 1 ]; then
            echo "Firmware appears to be already loaded (iManufacturer=$MFR_VALUE)"
            echo "Use --force to reload anyway"
        fi
    fi
else
    NEED_FIRMWARE=1
    if [ $VERBOSE -eq 1 ]; then
        echo "Force reload requested"
    fi
fi

# Load firmware if needed
if [ $NEED_FIRMWARE -eq 1 ]; then
    if [ $VERBOSE -eq 1 ]; then
        echo "Loading firmware: $FIRMWARE"
        echo "Target device: $DEVICE_PATH"
    fi

    # Load firmware using fxload
    if [ $VERBOSE -eq 1 ]; then
        # Run with verbose output
        if ! fxload -v -t fx2lp -I "$FIRMWARE" -D "$DEVICE_PATH"; then
            echo "ERROR: Firmware loading failed" >&2
            exit 4
        fi
    else
        # Run quietly
        if ! fxload -t fx2lp -I "$FIRMWARE" -D "$DEVICE_PATH" 2>/dev/null; then
            echo "ERROR: Firmware loading failed" >&2
            exit 4
        fi
    fi

    # Wait for device to stabilize after firmware load
    if [ $VERBOSE -eq 1 ]; then
        echo "Waiting for device to stabilize..."
    fi
    sleep 2

    if [ $VERBOSE -eq 1 ]; then
        echo "Firmware loaded successfully"
    fi
else
    if [ $VERBOSE -eq 1 ]; then
        echo "Firmware already loaded, skipping"
    fi
fi

# Success
exit 0
