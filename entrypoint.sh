#!/bin/bash
set -e

ASSETS_PATH="${ASSETS_PATH:-Assets.zip}"
AUTH_MODE="${AUTH_MODE:-authenticated}"
HYTALE_PORT="${HYTALE_PORT:-5520}"
BIND_ADDR="${BIND_ADDR:-0.0.0.0}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
DOWNLOADER_BIN="${DOWNLOADER_BIN:-hytale-downloader}"
HW_ID_STATUS="Unknown"
if [ -f /etc/machine-id ]; then
    HW_ID_STATUS=$(cat /etc/machine-id)
fi
HAS_HARDWARE_ID=true
IS_AUTHENTICATED=false
AUTH_REQUEST_TIME=0
AUTH_PENDING=false
STAGE="initializing"

PIPE=/tmp/hytale_stdin
[ -p $PIPE ] || mkfifo $PIPE

touch /tmp/server.log
mkdir -p /www

gen_row() {
    local label=$1
    local value=$2
    if [[ -n "$value" ]]; then
        echo "<div class='stat'><span class='label'>$label:</span><span>$value</span></div>"
    else
        echo ""
    fi
}

gen_html() {
    local header="$1"
    local hwid_status="$2"
    local expires="$3"
    local auth="$4"
    local reload_seconds="${5:-10}"

    local status_row=$(gen_row "Hardware Status" "$hwid_status")
    local expires_row=$(gen_row "Expires" "$expires")
    local auth_row=$(gen_row "Auth" "$auth")

    sed -e "s|{{HEADER}}|$header|g" \
    -e "s|{{STATUS_ROW}}|$status_row|g" \
    -e "s|{{HWID_ROW}}||g" \
    -e "s|{{EXPIRES_ROW}}|$expires_row|g" \
    -e "s|{{AUTH_ROW}}|$auth_row|g" \
    -e "s|{{RELOAD_SECONDS}}|$reload_seconds|g" \
    /template.html > /www/index.html
}

process_logs() {
    while read -r line; do
        echo "$line"

        if [[ "$line" == *"downloading latest"* ]]; then
            gen_html "Status: Downloading Latest" "$HW_ID_STATUS" "" "" "" 10
        fi
        
        if [[ "$line" == *"Failed to get Hardware UUID"* ]]; then
            HW_ID_STATUS="Failed (Non-persistent mode)"; HAS_HARDWARE_ID=false
        fi

        if [[ "$line" == *"Successfully created game session"* ]] || [[ "$line" == *"Session Token: Present"* ]] || [[ "$line" == *"Authentication successful"* ]]; then
            IS_AUTHENTICATED=true; AUTH_PENDING=false
            if [ "$STAGE" = "starting" ]; then
                [ "$HAS_HARDWARE_ID" = "true" ] && echo "/auth persistence Encrypted" > $PIPE &
            fi
            gen_html "Status: Authenticated" "$HW_ID_STATUS" "" "" 10
        fi

        if [[ "$line" == *"Session Token: Missing"* ]]; then
            [ "$STAGE" = "starting" ] && echo "/auth login device" > $PIPE &
            AUTH_REQUEST_TIME=$(date +%s); AUTH_PENDING=true
        fi

        if [[ "$line" == *"user_code="* ]]; then
            AUTH_URL=$(echo "$line" | grep -oE 'https://oauth\.accounts\.hytale\.com/oauth2/device/verify\?user_code=[0-9a-zA-Z]{8}')
            if [ -n "$AUTH_URL" ]; then
                AUTH_REQUEST_TIME=$(date +%s)
                if [ "$STAGE" = "initializing" ]; then
                    gen_html "Hytale Auth Required for Download" "$HW_ID_STATUS" "" "<a href='$AUTH_URL' target='_blank'>$AUTH_URL</a>" 5
                else
                    gen_html "Hytale Auth Required for Server Start" "$HW_ID_STATUS" "Expires in: ~10 minutes" "<a href='$AUTH_URL' target='_blank'>$AUTH_URL</a>" 10
                fi
            fi
        fi

        if [[ "$line" == *"Hytale Server Booted!"* ]]; then
            [ "$STAGE" = "starting" ] && echo "/auth status" > $PIPE &
        fi
    done
}

gen_html "Status: Initializing" "$HW_ID_STATUS" "" "" 10

python3 -m http.server 8080 --directory /www --bind 0.0.0.0 &
WEB_PID=$!

if [ -f "HytaleServer.jar" ] && [ "$AUTO_UPDATE" = "true" ]; then
    echo "Checking for downloader updates..."
    process_logs < <($DOWNLOADER_BIN -check-update 2>&1)

    gen_html "Status: Checking for Updates" "$HW_ID_STATUS" "" "" 10

    AVAILABLE_VERSION_RAW="$($DOWNLOADER_BIN -print-version 2>&1 || true)"
    gen_html "Status: Parsing Available Version..." "$HW_ID_STATUS" "" "" 10
    AVAILABLE_VERSION="$(echo "$AVAILABLE_VERSION_RAW" | tr -d '\r' | tail -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    gen_html "Status: Checking for Updates (Available Version) - $AVAILABLE_VERSION" "$HW_ID_STATUS" "" "" 10

    if [ -z "$AVAILABLE_VERSION" ]; then
        echo "ERROR: Could not determine available version from downloader (-print-version). Output was:"
        echo "$AVAILABLE_VERSION_RAW"
        exit 1
    fi
    
    echo "Available HytaleServer.jar version: $AVAILABLE_VERSION"
    
    # Get installed version if jar exists
    INSTALLED_VERSION=""
    if [ -f "HytaleServer.jar" ]; then
        INSTALLED_VERSION_RAW="$(java -jar "HytaleServer.jar" --version 2>&1 || true)"
        INSTALLED_VERSION="$(echo "$INSTALLED_VERSION_RAW" | tr -d '\r' | sed -n 's/.*v\([^ ]*\).*/\1/p' | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        
        if [ -z "$INSTALLED_VERSION" ]; then
            echo "WARNING: Could not extract version from installed jar. Output was:"
            echo "$INSTALLED_VERSION_RAW"
            echo "Treating as outdated and will download..."
        else
            echo "Installed HytaleServer.jar version: $INSTALLED_VERSION"
        fi
    else
        echo "HytaleServer.jar not found. Will download..."
        echo "Starting initial download..."
        process_logs < <($DOWNLOADER_BIN 2>&1)
    fi

    if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" = "$AVAILABLE_VERSION" ]; then
        echo "HytaleServer.jar is up to date."
    else
        echo "Downloading latest HytaleServer.jar version: $AVAILABLE_VERSION ..."
        process_logs < <($DOWNLOADER_BIN 2>&1)

        ZIP_FILE=$(ls [0-9]*.zip 2>/dev/null | head -n 1)

        if [ -n "$ZIP_FILE" ]; then
            echo "Extracting server package: $ZIP_FILE..."
            unzip -o "$ZIP_FILE"
            
            JAR_PATH=$(find . -name "HytaleServer.jar" | head -n 1)
            if [ -n "$JAR_PATH" ] && [ "$JAR_PATH" != "./HytaleServer.jar" ]; then
                mv "$JAR_PATH" ./HytaleServer.jar
            fi
            
            rm "$ZIP_FILE"
        fi
    fi
else
    if [ ! -f "HytaleServer.jar" ]; then
        echo "HytaleServer.jar not found and auto-update is disabled. Exiting."
        exit 1
    else
        echo "Auto-update disabled. Using existing HytaleServer.jar."
    fi
fi

JAVA_CMD="java"

JAVA_XMS="${JAVA_XMS:-4G}"
JAVA_XMX="${JAVA_XMX:-4G}"

[ -n "$JAVA_XMS" ] && JAVA_CMD+=" -Xms$JAVA_XMS"
[ -n "$JAVA_XMX" ] && JAVA_CMD+=" -Xmx$JAVA_XMX"

[ -n "$JAVA_CMD_ADDITIONAL_OPTS" ] && JAVA_CMD+=" $JAVA_CMD_ADDITIONAL_OPTS"

if [ "$USE_AOT_CACHE" = "true" ] && [ -f "HytaleServer.aot" ]; then
    JAVA_CMD+=" -XX:AOTCache=HytaleServer.aot"
fi

ARGS="--assets $ASSETS_PATH --auth-mode $AUTH_MODE"

[ -n "$SESSION_TOKEN" ] && ARGS="$ARGS --session-token \"$SESSION_TOKEN\""
[ -n "$IDENTITY_TOKEN" ] && ARGS="$ARGS --identity-token \"$IDENTITY_TOKEN\""
[ -n "$OWNER_UUID" ] && ARGS="$ARGS --owner-uuid \"$OWNER_UUID\""

[ "$ACCEPT_EARLY_PLUGINS" = "true" ] && ARGS="$ARGS --accept-early-plugins"
[ "$ALLOW_OP" = "true" ] && ARGS="$ARGS --allow-op"
[ "$DISABLE_SENTRY" = "true" ] && ARGS="$ARGS --disable-sentry"

if [ "$BACKUP_ENABLED" = "true" ]; then
    ARGS="$ARGS --backup --backup-dir $BACKUP_DIR --backup-frequency $BACKUP_FREQUENCY"
fi

ARGS="$ARGS --bind $BIND_ADDR:$HYTALE_PORT"

HYTALE_ADDITIONAL_OPTS="${HYTALE_ADDITIONAL_OPTS:-}"
[ -n "$HYTALE_ADDITIONAL_OPTS" ] && ARGS="$ARGS $HYTALE_ADDITIONAL_OPTS"

gen_html "Status: Waiting for Auth" "$HW_ID_STATUS" "" "" 5

cleanup() {
    echo "Caught shutdown signal!"
    if [ -p "$PIPE" ]; then
        echo "Sending /stop to Hytale server..."
        echo "/stop" > "$PIPE"
    fi
    sleep 5
    exit 0
}

trap cleanup SIGTERM SIGINT

echo "Starting Hytale server:"
STAGE="starting"

(
    while true; do
        if [ "$AUTH_PENDING" = "true" ] && [ "$IS_AUTHENTICATED" = "false" ]; then
            ELAPSED=$(( $(date +%s) - AUTH_REQUEST_TIME ))
            if [ $ELAPSED -ge 590 ]; then
                echo "Auth code expired. Re-requesting..." > $PIPE &
            fi
        fi
        sleep 30
    done
) &

gen_html "Status: Starting" "$HW_ID_STATUS" "" "" 10

process_logs < <(tail -f $PIPE | $JAVA_CMD -jar HytaleServer.jar $ARGS 2>&1 | tee /tmp/server.log)
