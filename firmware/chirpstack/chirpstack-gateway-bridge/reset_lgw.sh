#!/bin/sh

# Elecrow LR1302 HAT Reset Script for Raspberry Pi 5
# Uses 'pinctrl' to handle GPIOs (sysfs is dead on Pi 5)

# ----------------------------------------------------------------
# ELECROW SPECIFIC PINOUT
# ----------------------------------------------------------------
SX1302_RESET_PIN=17     # Elecrow uses GPIO 17 for SX1302 Reset
SX1302_POWER_EN_PIN=18  # Not strictly used by Elecrow (Power is always ON), but we keep it safe
SX1261_RESET_PIN=5      # Used if you have the LBT version

# ----------------------------------------------------------------

WAIT_GPIO() {
    sleep 0.1
}

init() {
    # No export needed for pinctrl
    echo "Initializing Elecrow HAT..."
}

reset() {
    echo "Resetting SX1302 on GPIO $SX1302_RESET_PIN..."

    # 1. Reset Sequence: High -> Low (Pulse)
    # Most SX1302 chips reset on a High pulse, then run on Low.
    
    # Drive Reset HIGH (Active - Resetting)
    pinctrl set $SX1302_RESET_PIN op dh
    WAIT_GPIO
    
    # Drive Reset LOW (Inactive - Running)
    pinctrl set $SX1302_RESET_PIN op dl
    WAIT_GPIO
    
    echo "Reset Complete."
}

term() {
    # Cleanup (Optional)
    echo "Termination (No action needed)"
}

case "$1" in
    start)
    reset
    ;;
    stop)
    term
    ;;
    *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac

exit 0