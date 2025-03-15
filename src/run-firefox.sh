#!/bin/bash

# This script runs Firefox with UI.Vision in the VNC environment

# Get the parameters
MACRO_NAME=$1
CALLBACK_URL=$2
IS_FOLDER=${3:-0}  # Default to 0 (macro mode)
URL_PARAMS=$4      # Additional URL parameters as JSON string
NEW_INSTANCE=${5:-0}  # Default to 0 (force new instance)
TIMEOUT=${6:-300}  # Default to 5 minutes (300 seconds)

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
  # Parse the JSON string and add each parameter to the URL
  # Expected format: {"closeBrowser":"1","closeRPA":"0","nodisplay":"1","cmd_var1":"value1,value2"}
  # Also handles numeric values like {"closeBrowser":1,"closeRPA":0}
  
  # Initialize flags to track if closeBrowser and closeRPA are specified
  HAS_CLOSE_BROWSER=false
  HAS_CLOSE_RPA=false
  
  # Check if jq is available
  if command -v jq &> /dev/null; then
    # Use jq to parse the JSON and format as key=value pairs
    # We need to preserve commas in values, so we'll process each key-value pair individually
    for key in $(echo "$URL_PARAMS" | jq -r 'keys[]'); do
      value=$(echo "$URL_PARAMS" | jq -r --arg k "$key" '.[$k]')
      
      # URL encode special characters but preserve commas
      # Replace % with %25 first to avoid double-encoding
      encoded_value=$(echo "$value" | sed 's/%/%25/g' | sed 's/#/%23/g' | sed 's/&/%26/g' | sed 's/+/%2B/g' | sed 's/ /%20/g')
      
      URL="${URL}&${key}=${encoded_value}"
      
      # Track if closeBrowser or closeRPA are specified
      if [ "$key" = "closeBrowser" ]; then
        HAS_CLOSE_BROWSER=true
      elif [ "$key" = "closeRPA" ]; then
        HAS_CLOSE_RPA=true
      fi
    done
  else
    # Fallback to simple parsing if jq is not available
    # This is a simplified approach that may not handle all edge cases
    # Remove the outer curly braces
    PARAMS=$(echo "$URL_PARAMS" | sed 's/^{//;s/}$//')
    # Process each key-value pair
    # Handle both string values ("key":"value") and numeric values ("key":value)
    while [[ $PARAMS =~ \"([^\"]+)\":(\"([^\"]+)\"|([0-9]+))(,|$) ]]; do
      key="${BASH_REMATCH[1]}"
      if [[ -n "${BASH_REMATCH[3]}" ]]; then
        # String value
        value="${BASH_REMATCH[3]}"
      else
        # Numeric value
        value="${BASH_REMATCH[4]}"
      fi
      
      # URL encode special characters but preserve commas
      # Replace % with %25 first to avoid double-encoding
      encoded_value=$(echo "$value" | sed 's/%/%25/g' | sed 's/#/%23/g' | sed 's/&/%26/g' | sed 's/+/%2B/g' | sed 's/ /%20/g')
      
      URL="${URL}&${key}=${encoded_value}"
      
      # Track if closeBrowser or closeRPA are specified
      if [ "$key" = "closeBrowser" ]; then
        HAS_CLOSE_BROWSER=true
      elif [ "$key" = "closeRPA" ]; then
        HAS_CLOSE_RPA=true
      fi
      
      # Remove the processed pair
      if [[ -n "${BASH_REMATCH[3]}" ]]; then
        # String value
        PARAMS="${PARAMS#*\"${key}\":\"${value}\"}"
      else
        # Numeric value
        PARAMS="${PARAMS#*\"${key}\":${value}}"
      fi
      # Remove leading comma if present
      PARAMS="${PARAMS#,}"
    done
  fi
  
  # Add default values for closeBrowser and closeRPA if not specified
  if [ "$HAS_CLOSE_BROWSER" = false ]; then
    URL="${URL}&closeBrowser=1"
  fi
  if [ "$HAS_CLOSE_RPA" = false ]; then
    URL="${URL}&closeRPA=1"
  fi
else
  # Add default parameters
  URL="${URL}&closeBrowser=1&closeRPA=1"
fi

# Log the command
echo "Running Firefox with URL: ${URL}"

# Use the default Firefox profile
echo "Using default Firefox profile"

# Set Firefox options based on NEW_INSTANCE parameter
FIREFOX_OPTIONS=""
if [ "$NEW_INSTANCE" = "1" ]; then
  FIREFOX_OPTIONS="--no-remote --new-instance"
  echo "Running Firefox with new instance"
else
  # Check if Firefox is already running
  if pgrep -f "firefox" > /dev/null; then
    echo "Firefox is already running, checking if it's responsive..."
    
    # Create a temporary file to test Firefox responsiveness
    TEMP_FILE=$(mktemp)
    
    # Try to get Firefox version with a timeout - if it hangs, Firefox is not responsive
    timeout 5s firefox --version > "$TEMP_FILE" 2>&1
    FIREFOX_RESPONSIVE=$?
    
    # Check the result
    if [ $FIREFOX_RESPONSIVE -eq 124 ] || [ $FIREFOX_RESPONSIVE -ne 0 ]; then
      echo "ERROR: Firefox is already running but not responding. Attempting to kill all Firefox processes..."
      
      # Kill all Firefox processes using pkill
      pkill -9 firefox
      
      # Wait a moment for processes to be killed
      sleep 2
      
      # Check if any Firefox processes are still running
      if pgrep -f "firefox" > /dev/null; then
        echo "ERROR: Failed to kill all Firefox processes. Please manually kill Firefox and try again."
        rm -f "$TEMP_FILE"
        exit 3  # Exit with error code 3 for "Firefox not responsive"
      else
        echo "Successfully killed all Firefox processes. Starting a new instance."
        FIREFOX_OPTIONS="--no-remote --new-instance"
      fi
    else
      # Clean up
      rm -f "$TEMP_FILE"
      
      echo "Firefox is responsive, using existing instance"
      FIREFOX_OPTIONS="--new-tab"  # Open in new tab of existing instance
    fi
  else
    echo "No Firefox instance running, starting new one"
    FIREFOX_OPTIONS="--no-remote"  # Only use --no-remote for new instances
  fi
fi

# Run Firefox with the URL
echo "Running Firefox with the URL..."
DISPLAY=:0 firefox \
  $FIREFOX_OPTIONS \
  --window-size=1920,1080 \
  "${URL}" &

FIREFOX_PID=$!
echo "Firefox started with PID: $FIREFOX_PID"

# Wait for log file to be created and populated
WAIT_COUNT=0
MACRO_COMPLETED=false

echo "Waiting for log file: $LOG_FILE"
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  # Check if log file exists
  if [ -f "$LOG_FILE" ]; then
    # Check if log file contains completion status
    if grep -q "Status=OK" "$LOG_FILE" || grep -q "Status=Error" "$LOG_FILE" || grep -q "\[status\] Macro completed" "$LOG_FILE"; then
      echo "Macro completion detected in log file"
      MACRO_COMPLETED=true
      break
    fi
  fi
  
  # Check if Firefox process is still running
  if ! ps -p $FIREFOX_PID > /dev/null; then
    echo "Firefox process has exited"
    break
  fi
  
  # Wait and increment counter
  sleep 5
  WAIT_COUNT=$((WAIT_COUNT + 1))
  echo "Waiting for macro completion... ($WAIT_COUNT/$((MAX_WAIT/5)))"
done

# Initialize exit code variable
EXIT_CODE=0

# Determine exit code based on log file content
if [ "$MACRO_COMPLETED" = true ]; then
  if grep -q "Status=Error" "$LOG_FILE"; then
    echo "Macro completed with error"
    EXIT_CODE=1
  else
    echo "Macro completed successfully"
    EXIT_CODE=0
  fi
  
  # If Firefox is still running and we're supposed to close it, kill it
  if ps -p $FIREFOX_PID > /dev/null; then
    # Check for closeBrowser=1 and make sure it's not closeBrowser=0 or closeBrowser=false
    if [[ "$URL" == *"closeBrowser=1"* ]] && [[ "$URL" != *"closeBrowser=0"* ]] && [[ "$URL" != *"closeBrowser=false"* ]]; then
      echo "Closing Firefox process (PID: $FIREFOX_PID)"
      kill $FIREFOX_PID 2>/dev/null || true
    else
      echo "Leaving Firefox running as closeBrowser is not set to 1"
    fi
  fi
else
  echo "Timeout waiting for macro completion or Firefox exited unexpectedly"
  EXIT_CODE=2
  
  # Kill Firefox if it's still running
  if ps -p $FIREFOX_PID > /dev/null; then
    echo "Killing Firefox process after timeout (PID: $FIREFOX_PID)"
    kill $FIREFOX_PID 2>/dev/null || true
  fi
fi

# Process the log file if it exists
if [ -f "$LOG_FILE" ]; then
  echo "Log file found: $LOG_FILE"
  LOG_CONTENT=$(cat "$LOG_FILE")
  STATUS_LINE=$(head -n 1 "$LOG_FILE")
  
  # Extract status from log file
  if [[ "$STATUS_LINE" != *"Status="* ]]; then
    # If first line doesn't contain Status=, look for it elsewhere in the file
    STATUS_LINE=$(grep -m 1 "Status=" "$LOG_FILE" || echo "Status=Unknown")
  fi
  
  echo "Status line: $STATUS_LINE"
  
  # Override exit code based on status from log file
  if [[ "$STATUS_LINE" == *"Status=OK"* ]]; then
    EXIT_CODE=0
    echo "Setting exit code to 0 based on Status=OK in log file"
  elif [[ "$STATUS_LINE" == *"Status=Error"* ]]; then
    EXIT_CODE=1
    echo "Setting exit code to 1 based on Status=Error in log file"
  fi
  
  # Extract echo data from the log
  # This will create a JSON object with variable names as keys and echo values as values
  ECHO_DATA="{}"
  
  # Skip the log header (first 3 lines)
  for i in {1..3}; do
    read -r line
  done < "$LOG_FILE"
  
  # Parse the log file to extract echo data
  while IFS= read -r line; do
    # Check if line contains variable name in echo command
    # Format: [info] Executing:  | echo | ${variableName} |  |
    if [[ $line =~ \[info\].*echo.*\$\{([^}]+)\}.* ]]; then
      # Extract variable name
      VAR_NAME="${BASH_REMATCH[1]}"
      
      # Read the next line which should contain the echo value start
      read -r next_line
      
      if [[ $next_line =~ \[echo\](.*) ]]; then
        # Start with the initial echo line
        ECHO_VALUE="${BASH_REMATCH[1]}"
        
        # Continue reading lines until we hit the next [info] line or end of file
        MULTILINE_VALUE=""
        while IFS= read -r echo_content_line; do
          if [[ $echo_content_line =~ ^\[info\].* ]]; then
            # Found the next [info] line, which means we've reached the end of the echo output
            # Move the file pointer back one line so this [info] line will be processed in the next iteration
            exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
            break
          fi
          # Skip empty lines and log headers
          if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
            continue
          fi
          # Append this line to our multiline value
          if [ -z "$MULTILINE_VALUE" ]; then
            MULTILINE_VALUE="$echo_content_line"
          else
            MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
          fi
        done < "$LOG_FILE"
        
        # If we found multiline content, use it
        if [ ! -z "$MULTILINE_VALUE" ]; then
          ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
        fi
        
        # Trim leading/trailing whitespace
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # Replace newlines with \n for JSON
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
        
        # Escape special characters in the value
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
        
        # Add to ECHO_DATA JSON
        if [ "$ECHO_DATA" = "{}" ]; then
          ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
        else
          # Use jq to add the new key-value pair
          if command -v jq &> /dev/null; then
            ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
          else
            # Fallback if jq is not available (less reliable)
            ECHO_DATA="${ECHO_DATA%\}},\"$VAR_NAME\":\"$ECHO_VALUE\"}"
          fi
        fi
      fi
    fi
  done < "$LOG_FILE"
  
  # Also extract stored variables from the log
  # Look for storeText commands to capture additional variables
  while IFS= read -r line; do
    # Format: [info] Executing:  | storeText | xpath=... | variableName |
    if [[ $line =~ \[info\].*storeText.*\|[^|]+\|[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]]; then
      # Extract variable name from storeText command
      VAR_NAME="${BASH_REMATCH[1]}"
      
      # Check if this variable was already captured via echo
      if command -v jq &> /dev/null; then
        VAR_EXISTS=$(echo "$ECHO_DATA" | jq "has(\"$VAR_NAME\")")
        if [ "$VAR_EXISTS" = "true" ]; then
          # Skip if already captured
          continue
        fi
      elif [[ "$ECHO_DATA" == *"\"$VAR_NAME\":"* ]]; then
        # Skip if already captured (basic check)
        continue
      fi
      
      # Look for echo commands with this variable to find its value
      VALUE_FOUND=false
      while IFS= read -r echo_line; do
        if [[ $echo_line =~ \[info\].*echo.*\$\{$VAR_NAME\}.* ]]; then
          # Found an echo for this variable, read the next line for the value
          read -r value_line
          if [[ $value_line =~ \[echo\](.*) ]]; then
            # Start with the initial echo line
            ECHO_VALUE="${BASH_REMATCH[1]}"
            
            # Continue reading lines until we hit the next [info] line or end of file
            MULTILINE_VALUE=""
            while IFS= read -r echo_content_line; do
              if [[ $echo_content_line =~ ^\[info\].* ]]; then
                # Found the next [info] line, which means we've reached the end of the echo output
                # Move the file pointer back one line so this [info] line will be processed in the next iteration
                exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
                break
              fi
              # Skip empty lines and log headers
              if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
                continue
              fi
              # Append this line to our multiline value
              if [ -z "$MULTILINE_VALUE" ]; then
                MULTILINE_VALUE="$echo_content_line"
              else
                MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
              fi
            done < "$LOG_FILE"
            
            # If we found multiline content, use it
            if [ ! -z "$MULTILINE_VALUE" ]; then
              ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
            fi
            
            # Trim leading/trailing whitespace
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Replace newlines with \n for JSON
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
            
            # Escape special characters in the value
            ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
            
            # Add to ECHO_DATA JSON
            if [ "$ECHO_DATA" = "{}" ]; then
              ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
            else
              # Use jq to add the new key-value pair
              if command -v jq &> /dev/null; then
                ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
              else
                # Fallback if jq is not available (less reliable)
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
  
  # Also look for direct echo commands that don't use variables
  # This captures cases like echo | some text | variableName |
  while IFS= read -r line; do
    if [[ $line =~ \[info\].*echo.*\|[^|]+\|[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]]; then
      # Extract variable name from echo command
      VAR_NAME="${BASH_REMATCH[1]}"
      
      # Check if this variable was already captured
      if command -v jq &> /dev/null; then
        VAR_EXISTS=$(echo "$ECHO_DATA" | jq "has(\"$VAR_NAME\")")
        if [ "$VAR_EXISTS" = "true" ]; then
          # Skip if already captured
          continue
        fi
      elif [[ "$ECHO_DATA" == *"\"$VAR_NAME\":"* ]]; then
        # Skip if already captured (basic check)
        continue
      fi
      
      # Read the next line which should contain the echo value
      read -r next_line
      
      if [[ $next_line =~ \[echo\](.*) ]]; then
        # Start with the initial echo line
        ECHO_VALUE="${BASH_REMATCH[1]}"
        
        # Continue reading lines until we hit the next [info] line or end of file
        MULTILINE_VALUE=""
        while IFS= read -r echo_content_line; do
          if [[ $echo_content_line =~ ^\[info\].* ]]; then
            # Found the next [info] line, which means we've reached the end of the echo output
            # Move the file pointer back one line so this [info] line will be processed in the next iteration
            exec < <(echo "$echo_content_line"; cat "$LOG_FILE")
            break
          fi
          # Skip empty lines and log headers
          if [[ -z "$echo_content_line" || "$echo_content_line" =~ ^(Status=|###|\[status\]) ]]; then
            continue
          fi
          # Append this line to our multiline value
          if [ -z "$MULTILINE_VALUE" ]; then
            MULTILINE_VALUE="$echo_content_line"
          else
            MULTILINE_VALUE="$MULTILINE_VALUE"$'\n'"$echo_content_line"
          fi
        done < "$LOG_FILE"
        
        # If we found multiline content, use it
        if [ ! -z "$MULTILINE_VALUE" ]; then
          ECHO_VALUE="$ECHO_VALUE"$'\n'"$MULTILINE_VALUE"
        fi
        
        # Trim leading/trailing whitespace
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # Replace newlines with \n for JSON
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed ':a;N;$!ba;s/\n/\\n/g')
        
        # Escape special characters in the value
        ECHO_VALUE=$(echo "$ECHO_VALUE" | sed 's/"/\\"/g')
        
        # Add to ECHO_DATA JSON
        if [ "$ECHO_DATA" = "{}" ]; then
          ECHO_DATA="{\"$VAR_NAME\":\"$ECHO_VALUE\"}"
        else
          # Use jq to add the new key-value pair
          if command -v jq &> /dev/null; then
            ECHO_DATA=$(echo "$ECHO_DATA" | jq --arg key "$VAR_NAME" --arg value "$ECHO_VALUE" '. + {($key): $value}')
          else
            # Fallback if jq is not available (less reliable)
            ECHO_DATA="${ECHO_DATA%\}},\"$VAR_NAME\":\"$ECHO_VALUE\"}"
          fi
        fi
      fi
    fi
  done < "$LOG_FILE"
  
  echo "Extracted echo data: $ECHO_DATA"
  
  # Send data to callback URL if provided
  if [ ! -z "$CALLBACK_URL" ]; then
    echo "Sending results to callback URL: $CALLBACK_URL"
    
    # Create a temporary file for the JSON payload
    TEMP_JSON_FILE=$(mktemp)
    
    # First create a simplified JSON without log content to ensure we have valid data
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
    
    # Check if we can add log content safely
    if command -v jq &> /dev/null; then
      # Validate the simplified JSON first
      if jq . "$TEMP_JSON_FILE" > /dev/null 2>&1; then
        # Try to create a full JSON with log content
        FULL_JSON_FILE=$(mktemp)
        
        # Use jq to properly escape the log content
        LOG_CONTENT_ESCAPED=$(echo "$LOG_CONTENT" | jq -R -s .)
        
        # Create the full JSON payload
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
        
        # Validate the full JSON
        if jq . "$FULL_JSON_FILE" > /dev/null 2>&1; then
          # Use the full JSON if valid
          TEMP_JSON_FILE="$FULL_JSON_FILE"
          echo "Using full JSON payload with log content"
        else
          echo "Full JSON payload is invalid, using simplified payload"
          # Keep using the simplified JSON
          rm -f "$FULL_JSON_FILE"
        fi
      else
        echo "Warning: Even simplified JSON is invalid. Attempting to fix..."
        # Try to create a minimal valid JSON
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
    
    # Send the data to the callback URL
    echo "Sending JSON payload to callback URL"
    curl -X POST \
      -H "Content-Type: application/json" \
      --data-binary @"$TEMP_JSON_FILE" \
      "$CALLBACK_URL"
    
    CURL_EXIT_CODE=$?
    echo "Callback request completed with exit code: $CURL_EXIT_CODE"
    
    # Clean up temporary files
    rm -f "$TEMP_JSON_FILE"
  else
    echo "No callback URL provided, skipping callback"
  fi
else
  echo "Log file not found after waiting $MAX_WAIT seconds"
fi

# Return the exit code based on log status
exit $EXIT_CODE