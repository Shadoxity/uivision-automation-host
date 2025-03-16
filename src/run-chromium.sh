#!/bin/bash

# This script runs Chromium with UI.Vision in the VNC environment

# Get the parameters
MACRO_NAME=$1
CALLBACK_URL=$2
IS_FOLDER=${3:-0}  # Default to 0 (macro mode)
URL_PARAMS=$4      # Additional URL parameters as JSON string
NEW_INSTANCE=${5:-0}  # Default to 0 (not used for Chromium)
TIMEOUT=${6:-300}  # Default to 300 seconds (5 minutes)

# Define log file path
LOG_DIR="/usr/src/uivision/macro-logs"
LOG_FILE="${LOG_DIR}/logRPA_$(date -u +"%Y-%m-%dT%H-%M-%S").txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Determine if we're running a macro or folder
if [ "$IS_FOLDER" = "1" ]; then
  TARGET_PARAM="folder"
else
  TARGET_PARAM="macro"
fi

# Build the base URL with parameters
URL="file:///usr/src/app/data/ui.vision.html?${TARGET_PARAM}=${MACRO_NAME}&storage=xfile&direct=1&savelog=${LOG_FILE}"

# Validate timeout parameter
if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "Invalid timeout value: $TIMEOUT, using default of 300 seconds"
  TIMEOUT=300
fi
MAX_WAIT=$TIMEOUT
echo "Using timeout of $MAX_WAIT seconds"

# Add additional URL parameters if provided
if [ ! -z "$URL_PARAMS" ]; then
  HAS_CLOSE_BROWSER=false
  HAS_CLOSE_RPA=false
  
  # Debug: Print the URL_PARAMS
  echo "URL_PARAMS received: $URL_PARAMS"
  
  if command -v jq &> /dev/null; then
    echo "Using jq for JSON parsing"
    # Process each key-value pair using jq
    for key in $(echo "$URL_PARAMS" | jq -r 'keys[]'); do
      value=$(echo "$URL_PARAMS" | jq -r --arg k "$key" '.[$k]')
      echo "Processing parameter: $key = $value"
      
      # URL encode special characters but preserve commas
      encoded_value=$(echo "$value" | sed 's/%/%25/g' | sed 's/#/%23/g' | sed 's/&/%26/g' | sed 's/+/%2B/g' | sed 's/ /%20/g')
      
      URL="${URL}&${key}=${encoded_value}"
      echo "URL after adding $key: $URL"
      
      # Track if closeBrowser or closeRPA are specified
      if [ "$key" = "closeBrowser" ]; then
        HAS_CLOSE_BROWSER=true
      elif [ "$key" = "closeRPA" ]; then
        HAS_CLOSE_RPA=true
      fi
    done
  else
    echo "jq not available, using fallback parsing method"
    # Fallback to simple parsing if jq is not available
    # This is a simplified approach that may not handle all edge cases
    # Remove the outer curly braces
    PARAMS=$(echo "$URL_PARAMS" | sed 's/^{//;s/}$//')
    echo "Stripped params: $PARAMS"
    
    # Process each key-value pair
    while [[ $PARAMS =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\"[[:space:]]*(,|$) ]]; do
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      echo "Found key: $key, value: $value"
      
      # URL encode special characters but preserve commas
      encoded_value=$(echo "$value" | sed 's/%/%25/g' | sed 's/#/%23/g' | sed 's/&/%26/g' | sed 's/+/%2B/g' | sed 's/ /%20/g')
      
      URL="${URL}&${key}=${encoded_value}"
      echo "URL after adding $key: $URL"
      
      # Track if closeBrowser or closeRPA are specified
      if [ "$key" = "closeBrowser" ]; then
        HAS_CLOSE_BROWSER=true
      elif [ "$key" = "closeRPA" ]; then
        HAS_CLOSE_RPA=true
      fi
      
      # Remove the processed pair and continue
      PARAMS="${PARAMS#*\"$key\":\"$value\"}"
      PARAMS="${PARAMS#,}"
      echo "Remaining params: $PARAMS"
    done
    
    # Also handle numeric values (like "key":0)
    while [[ $PARAMS =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*(,|$) ]]; do
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      echo "Found numeric key: $key, value: $value"
      
      URL="${URL}&${key}=${value}"
      echo "URL after adding numeric $key: $URL"
      
      # Track if closeBrowser or closeRPA are specified
      if [ "$key" = "closeBrowser" ]; then
        HAS_CLOSE_BROWSER=true
      elif [ "$key" = "closeRPA" ]; then
        HAS_CLOSE_RPA=true
      fi
      
      # Remove the processed pair and continue
      PARAMS="${PARAMS#*\"$key\":$value}"
      PARAMS="${PARAMS#,}"
      echo "Remaining params after numeric: $PARAMS"
    done
  fi
  
  # Add default values for closeBrowser and closeRPA if not specified
  if [ "$HAS_CLOSE_BROWSER" = false ]; then
    echo "Adding default closeBrowser=1"
    URL="${URL}&closeBrowser=1"
  fi
  if [ "$HAS_CLOSE_RPA" = false ]; then
    echo "Adding default closeRPA=1"
    URL="${URL}&closeRPA=1"
  fi
else
  URL="${URL}&closeBrowser=1&closeRPA=1"
fi

echo "Running Chromium with URL: ${URL}"
echo "Using default Chromium profile"

# Note: NEW_INSTANCE parameter is ignored for Chromium
if [ "$NEW_INSTANCE" = "1" ]; then
  echo "Force new instance requested, but Chromium will reuse running instance if available."
fi

# Set Chromium options
CHROMIUM_OPTIONS="--no-sandbox --window-size=1440,900 --no-default-browser-check --no-first-run --disable-popup-blocking --disable-session-crashed-bubble --disable-infobars --disable-notifications --disable-save-password-bubble --disable-translate --disable-sync-preferences"

# Check if chromium is already running and append --new-tab if so
if pgrep -f "chromium" > /dev/null; then
  echo "Chromium is already running, appending --new-tab option"
  CHROMIUM_OPTIONS="$CHROMIUM_OPTIONS --new-tab"
else
  echo "No Chromium instance running, starting normally"
fi

echo "Running Chromium with the URL..."
DISPLAY=:0 chromium $CHROMIUM_OPTIONS "${URL}" &
CHROMIUM_PID=$!
echo "Chromium started with PID: $CHROMIUM_PID"

WAIT_COUNT=0
MACRO_COMPLETED=false

echo "Waiting for log file: $LOG_FILE"
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  if [ -f "$LOG_FILE" ]; then
    if grep -q "Status=OK" "$LOG_FILE" || grep -q "Status=Error" "$LOG_FILE" || grep -q "\[status\] Macro completed" "$LOG_FILE"; then
      echo "Macro completion detected in log file"
      MACRO_COMPLETED=true
      break
    fi
  fi
  if ! ps -p $CHROMIUM_PID > /dev/null; then
    echo "Chromium process has exited"
    break
  fi
  sleep 5
  WAIT_COUNT=$((WAIT_COUNT + 1))
  echo "Waiting for macro completion... ($WAIT_COUNT/$((MAX_WAIT/5)))"
done

EXIT_CODE=0
if [ "$MACRO_COMPLETED" = true ]; then
  if grep -q "Status=Error" "$LOG_FILE"; then
    echo "Macro completed with error"
    EXIT_CODE=1
  else
    echo "Macro completed successfully"
    EXIT_CODE=0
  fi
  if ps -p $CHROMIUM_PID > /dev/null; then
    if [[ "$URL" == *"closeBrowser=1"* ]] && [[ "$URL" != *"closeBrowser=0"* ]] && [[ "$URL" != *"closeBrowser=false"* ]]; then
      echo "Closing Chromium process (PID: $CHROMIUM_PID)"
      kill $CHROMIUM_PID 2>/dev/null || true
    else
      echo "Leaving Chromium running as closeBrowser is not set to 1"
    fi
  fi
else
  echo "Timeout waiting for macro completion or Chromium exited unexpectedly"
  EXIT_CODE=2
  if ps -p $CHROMIUM_PID > /dev/null; then
    echo "Killing Chromium process after timeout (PID: $CHROMIUM_PID)"
    kill $CHROMIUM_PID 2>/dev/null || true
  fi
fi

if [ -f "$LOG_FILE" ]; then
  echo "Log file found: $LOG_FILE"
  LOG_CONTENT=$(cat "$LOG_FILE")
  STATUS_LINE=$(head -n 1 "$LOG_FILE")
  if [[ "$STATUS_LINE" != *"Status="* ]]; then
    STATUS_LINE=$(grep -m 1 "Status=" "$LOG_FILE" || echo "Status=Unknown")
  fi
  echo "Status line: $STATUS_LINE"
  if [[ "$STATUS_LINE" == *"Status=OK"* ]]; then
    EXIT_CODE=0
    echo "Setting exit code to 0 based on Status=OK in log file"
  elif [[ "$STATUS_LINE" == *"Status=Error"* ]]; then
    EXIT_CODE=1
    echo "Setting exit code to 1 based on Status=Error in log file"
  fi
  ECHO_DATA="{}"
  for i in {1..3}; do
    read -r line
  done < "$LOG_FILE"
  while IFS= read -r line; do
    if [[ $line =~ \[info\].*echo.*\$\{([^}]+)\}.* ]]; then
      VAR_NAME="${BASH_REMATCH[1]}"
      read -r next_line
      if [[ $next_line =~ \[echo\](.*) ]]; then
        ECHO_VALUE="${BASH_REMATCH[1]}"
        MULTILINE_VALUE=""
        while IFS= read -r echo_content_line; do
          if [[ $echo_content_line =~ ^\[info\].* ]]; then
            exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
            break
          fi
          if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
            continue
          fi
          if [ -z "$MULTILINE_VALUE" ]; then
            MULTILINE_VALUE="$echo_content_line"
          else
            MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
          fi
        done < "$LOG_FILE"
        if [ ! -z "$MULTILINE_VALUE" ]; then
          ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
        fi
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
        if [ "$ECHO_DATA" = "{}" ]; then
          ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
        else
          if command -v jq &> /dev/null; then
            ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
          else
            ECHO_DATA="${ECHO_DATA%\}},\"$VAR_NAME\":\"$ECHO_VALUE\"}"
          fi
        fi
      fi
    fi
  done < "$LOG_FILE"
  while IFS= read -r line; do
    if [[ $line =~ \[info\].*storeText.*\|[^|]+\|[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]]; then
      VAR_NAME="${BASH_REMATCH[1]}"
      if command -v jq &> /dev/null; then
        VAR_EXISTS=$(echo "$ECHO_DATA" | jq "has(\"$VAR_NAME\")")
        if [ "$VAR_EXISTS" = "true" ]; then
          continue
        fi
      elif [[ "$ECHO_DATA" == *"\"$VAR_NAME\":"* ]]; then
        continue
      fi
      VALUE_FOUND=false
      while IFS= read -r echo_line; do
        if [[ $echo_line =~ \[info\].*echo.*\$\{$VAR_NAME\}.* ]]; then
          read -r value_line
          if [[ $value_line =~ \[echo\](.*) ]]; then
            ECHO_VALUE="${BASH_REMATCH[1]}"
            MULTILINE_VALUE=""
            while IFS= read -r echo_content_line; do
              if [[ $echo_content_line =~ ^\[info\].* ]]; then
                exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
                break
              fi
              if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
                continue
              fi
              if [ -z "$MULTILINE_VALUE" ]; then
                MULTILINE_VALUE="$echo_content_line"
              else
                MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
              fi
            done < "$LOG_FILE"
            if [ ! -z "$MULTILINE_VALUE" ]; then
              ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
            fi
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
            if [ "$ECHO_DATA" = "{}" ]; then
              ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
            else
              if command -v jq &> /dev/null; then
                ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
              else
                ECHO_DATA="${ECHO_DATA%\}},\"$VAR_NAME\":\"$ECHO_VALUE\"}"
              fi
            fi
            VALUE_FOUND=true
            break
          fi
        fi
      done < "$LOG_FILE"
    fi
  done < "$LOG_FILE"
  while IFS= read -r line; do
    if [[ $line =~ \[info\].*echo.*\|[^|]+\|[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]]; then
      VAR_NAME="${BASH_REMATCH[1]}"
      if command -v jq &> /dev/null; then
        VAR_EXISTS=$(echo "$ECHO_DATA" | jq "has(\"$VAR_NAME\")")
        if [ "$VAR_EXISTS" = "true" ]; then
          continue
        fi
      elif [[ "$ECHO_DATA" == *"\"$VAR_NAME\":"* ]]; then
        continue
      fi
      read -r next_line
      if [[ $next_line =~ \[echo\](.*) ]]; then
        ECHO_VALUE="${BASH_REMATCH[1]}"
        MULTILINE_VALUE=""
        while IFS= read -r echo_content_line; do
          if [[ $echo_content_line =~ ^\[info\].* ]]; then
            exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
            break
          fi
          if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
            continue
          fi
          if [ -z "$MULTILINE_VALUE" ]; then
            MULTILINE_VALUE="$echo_content_line"
          else
            MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
          fi
        done < "$LOG_FILE"
        if [ ! -z "$MULTILINE_VALUE" ]; then
          ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
        fi
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
        if [ "$ECHO_DATA" = "{}" ]; then
          ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
        else
          if command -v jq &> /dev/null; then
            ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
          else
            ECHO_DATA="${ECHO_DATA%\}},\"$VAR_NAME\":\"$ECHO_VALUE\"}"
          fi
        fi
      fi
    fi
  done < "$LOG_FILE"
  echo "Extracted echo data: $ECHO_DATA"
  if [ ! -z "$CALLBACK_URL" ]; then
    echo "Sending results to callback URL: $CALLBACK_URL"
    TEMP_JSON_FILE=$(mktemp)
    cat > "$TEMP_JSON_FILE" <<EOF
{
  "status": "$(echo "$STATUS_LINE" | sed 's/"/\\"/g')",
  "name": "$(echo "$MACRO_NAME" | sed 's/"/\\"/g')",
  "isFolder": $IS_FOLDER,
  "newInstance": $NEW_INSTANCE,
  "executionTime": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "exitCode": $EXIT_CODE,
  "echoData": $ECHO_DATA
}
EOF
    if command -v jq &> /dev/null; then
      if jq . "$TEMP_JSON_FILE" > /dev/null 2>&1; then
        FULL_JSON_FILE=$(mktemp)
        LOG_CONTENT_ESCAPED=$(echo "$LOG_CONTENT" | jq -R -s .)
        cat > "$FULL_JSON_FILE" <<EOF
{
  "status": "$(echo "$STATUS_LINE" | sed 's/"/\\"/g')",
  "name": "$(echo "$MACRO_NAME" | sed 's/"/\\"/g')",
  "isFolder": $IS_FOLDER,
  "newInstance": $NEW_INSTANCE,
  "executionTime": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "exitCode": $EXIT_CODE,
  "echoData": $ECHO_DATA,
  "logContent": $LOG_CONTENT_ESCAPED
}
EOF
        if jq . "$FULL_JSON_FILE" > /dev/null 2>&1; then
          TEMP_JSON_FILE="$FULL_JSON_FILE"
          echo "Using full JSON payload with log content"
        else
          echo "Full JSON payload is invalid, using simplified payload"
          rm -f "$FULL_JSON_FILE"
        fi
      else
        echo "Warning: Even simplified JSON is invalid. Attempting to fix..."
        cat > "$TEMP_JSON_FILE" <<EOF
{
  "status": "Error creating valid JSON",
  "name": "$(echo "$MACRO_NAME" | sed 's/"/\\"/g')",
  "executionTime": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "exitCode": $EXIT_CODE
}
EOF
      fi
    fi
    echo "Sending JSON payload to callback URL"
    curl -X POST -H "Content-Type: application/json" --data-binary @"$TEMP_JSON_FILE" "$CALLBACK_URL"
    CURL_EXIT_CODE=$?
    echo "Callback request completed with exit code: $CURL_EXIT_CODE"
    rm -f "$TEMP_JSON_FILE"
  else
    echo "No callback URL provided, skipping callback"
  fi
else
  echo "Log file not found after waiting $MAX_WAIT seconds"
fi

exit $EXIT_CODE 