#!/bin/bash
# Wazuh Maintenance Window Manager
# Exposes start/stop/status of alerts suppression

COMMAND=$1
DURATION=$2

MAINT_FILE="/var/ossec/etc/maintenance_until"

if [ -z "$COMMAND" ]; then
    echo "Usage: wazuh-maintenance [start|stop|status] [duration]"
    echo "Examples:"
    echo "  wazuh-maintenance start 30m   # Suppress alerts for 30 minutes"
    echo "  wazuh-maintenance start 2h    # Suppress alerts for 2 hours"
    echo "  wazuh-maintenance stop        # Clear maintenance immediately"
    echo "  wazuh-maintenance status      # Show maintenance state"
    exit 1
fi

case "$COMMAND" in
    start)
        if [ -z "$DURATION" ]; then
            echo "Error: Duration required (e.g. 30m, 1h, 2h)"
            exit 1
        fi
        
        # Parse duration unit
        UNIT="${DURATION: -1}"
        VAL="${DURATION%?}"
        
        case "$UNIT" in
            m) MULTIPLIER=60 ;;
            h) MULTIPLIER=3600 ;;
            s) MULTIPLIER=1 ;;
            *)
                echo "Error: Invalid duration unit. Use 'm' for minutes, 'h' for hours."
                exit 1
                ;;
        esac
        
        SECONDS=$((VAL * MULTIPLIER))
        TARGET=$(( $(date +%s) + SECONDS ))
        
        # Push target epoch directly to the Wazuh container CT 310
        pct exec 310 -- sh -c "echo '$TARGET' > $MAINT_FILE"
        echo "Wazuh alerts suppressed until: $(date -d @$TARGET)"
        ;;
    stop)
        pct exec 310 -- rm -f "$MAINT_FILE"
        echo "Wazuh alerts suppression cleared. Normal monitoring resumed."
        ;;
    status)
        UNTIL=$(pct exec 310 -- cat "$MAINT_FILE" 2>/dev/null)
        if [ -z "$UNTIL" ]; then
            echo "Wazuh alerts: ACTIVE (No maintenance window)"
        else
            NOW=$(date +%s)
            if [ "$NOW" -lt "$UNTIL" ]; then
                REMAINING=$((UNTIL - NOW))
                MINS=$((REMAINING / 60))
                echo "Wazuh alerts: SUPPRESSED (Deployment Mode active for next ${MINS} minutes, until $(date -d @$UNTIL))"
            else
                echo "Wazuh alerts: ACTIVE (Maintenance window expired at $(date -d @$UNTIL))"
                # Clean up expired file
                pct exec 310 -- rm -f "$MAINT_FILE"
            fi
        fi
        ;;
    *)
        echo "Error: Unknown command. Use start, stop, or status."
        exit 1
        ;;
esac
