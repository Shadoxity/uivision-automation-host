# UI.Vision Automation Server

A Dockerized solution for automating UI testing workflows using Chromium with the UI.Vision extension in a VNC environment.

## Overview

This project provides a REST API that accepts webhook requests to run UI.Vision macros and reports results back via another webhook. It's designed to handle macro execution with isolated Chromium instances running in a virtual desktop environment.

## Features

- Authenticated REST API for triggering UI.Vision tests
- Support for running individual macros or entire folders
- Flexible URL parameters for customizing UI.Vision behavior
- Concurrent test execution with isolated Chromium instances
- Web-based VNC access for monitoring and debugging
- Webhook-based result reporting
- Docker containerization for easy deployment
- Configurable timeout settings for long-running macros
- Logs and other run output data is available in your mounted data drive
- Browser downloads save to the uivision folder automatically

## Setup

### Prerequisites

- Docker

### Docker Requirements

This container requires specific Docker capabilities to run properly:

- `SYS_ADMIN` capability: Required for Chromium to run properly in the container
- `seccomp=unconfined` security option: Needed to allow proper browser functionality

These requirements are automatically included in the docker-compose.yml template, but if you're running the container directly with `docker run`, you must include these options:

```bash
docker run -d \
  --cap-add=SYS_ADMIN \
  --security-opt seccomp=unconfined \
  -p 3000:3000 -p 6080:6080 \
  -e API_KEY=your-secret-key \
  -e API_PORT=3000 \
  -e VNC_PASSWORD=password \
  -e VNC_RESOLUTION=1920x1080 \
  uivision-automation
```

### Installation Options

#### Option 1: Using the Docker Hub Image (Recommended)

The easiest way to get started is to use the pre-built Docker image from Docker Hub:

```bash
docker run -d \
  --cap-add=SYS_ADMIN \
  --security-opt seccomp=unconfined \
  -p 3000:3000 -p 6080:6080 \
  -e API_KEY=your-secret-key \
  -e API_PORT=3000 \
  -e VNC_PASSWORD=password \
  -e VNC_RESOLUTION=1920x1080 \
  -v /path/to/your/data:/usr/src/uivision/ \
  shadoxity/uivision-automation-host:latest
```

This will pull the latest image from Docker Hub and run it with your specified environment variables and mounted macro files.

#### Option 2: Building from Source

If you need to customize the image or make modifications to the code, you can build from source:

1. Clone this repository
2. Place your macro files in the `data/macros` directory
3. Build the Docker image:

```bash
docker build -t uivision-automation .
```

4. Run the container:

```bash
docker run -d \
  --cap-add=SYS_ADMIN \
  --security-opt seccomp=unconfined \
  -p 3000:3000 -p 6080:6080 \
  -e API_KEY=your-secret-key \
  -e API_PORT=3000 \
  -e VNC_PASSWORD=password \
  -e VNC_RESOLUTION=1920x1080 \
  -v /path/to/your/macros:/usr/src/uivision/macros \
  uivision-automation
```

### Using Docker Compose

For easier deployment, you can use Docker Compose:

1. Copy the template file to create your own docker-compose.yml:
   ```bash
   cp docker-compose.template.yml docker-compose.yml
   ```

2. Edit the docker-compose.yml file to set your own values for:
   - API_KEY (for API authentication)
   - API_PORT (port for the API server)
   - VNC_PASSWORD (for VNC access)
   - VNC_RESOLUTION (screen resolution for the VNC server)
   - Volume paths (to mount your macro files)

   **Important**: If your API key or password contains special characters like `$`, you need to escape them with an additional `$` in the docker-compose.yml file. For example, `my$password` should be written as `my$$password`.

3. If you want to use the Docker Hub image instead of building locally, update the `image` line in your docker-compose.yml:
   ```yaml
   image: shadoxity/uivision-automation-host:latest
   ```

4. Start the container:
   ```bash
   docker-compose up -d
   ```

Note: The docker-compose.yml file is excluded from git to prevent committing sensitive information. Always use the template as a starting point.

## Usage

### API Endpoints

#### Run Macro or Folder

```
POST /run-macro
```

Headers:
```
x-api-key: your-secret-key
Content-Type: application/json
```

Request Body:
```json
{
  "name": "your-macro-name",
  "isFolder": false,
  "outboundWebhook": "http://your-callback-url.com/receive",
  "newInstance": true,
  "timeout": 600,
  "urlParams": {
    "closeBrowser": "1",
    "closeRPA": "1",
    "cmd_var1": "value1",
    "cmd_var2": "value2",
    "cmd_var3": "value3"
  }
}
```

Parameters:
- `name`: The name of the macro or folder to run (required)
- `isFolder`: Whether the name refers to a folder (default: false)
- `outboundWebhook`: URL to send results to when the macro is complete (required)
- `newInstance`: Whether to force a new Chromium instance (default: true)
- `timeout`: Maximum time in seconds to wait for macro completion (default: 300 - 5 minutes)
- `urlParams`: URL parameters to customize UI.Vision behavior, including variables

Response:
```json
{
  "status": "Test started", 
  "name": "your-macro-name",
  "isFolder": false,
  "newInstance": true,
  "timeout": 600,
  "urlParamsCount": 6
}
```

#### Health Check

```
GET /health
```

Response:
```json
{
  "status": "ok"
}
```

## Environment Variables

- `API_PORT`: The port to run the server on (default: 3000)
- `API_KEY`: The API key for authentication (default: "default-api-key")
- `VNC_PASSWORD`: Password for VNC access (default: "password")
- `VNC_RESOLUTION`: Screen resolution for the VNC server (default: "1920x1080")

## Web-Based VNC Access for Debugging

You can access the container's desktop environment using a web browser:

1. Open your browser and navigate to `http://localhost:6080` (or your server's IP)
2. Enter the password you set in the `VNC_PASSWORD` environment variable
3. You'll see the desktop environment where Chromium is running with UI.Vision

This web-based VNC access makes it easy to monitor and debug your UI.Vision macros without needing a dedicated VNC client.

## UI.Vision CLI Integration

This project uses the UI.Vision command line interface to run macros in a virtual desktop environment. The integration works as follows:

1. The server receives a webhook request with macro/folder details and parameters
2. It launches Chromium with the UI.Vision extension in the VNC environment
3. It passes command line parameters to UI.Vision:
   - `macro` or `folder`: The name of the macro or folder to run
   - `direct`: Set to 1 to run directly without dialog
   - `storage`: Set to "xfile" to use file storage
   - `savelog`: The name of the log file to save results to (your mounted data folder)
   - Additional URL parameters as specified in the `urlParams` object

### Chromium Instance Control

The `newInstance` parameter controls how Chromium is launched:

- When set to `true` (default), a new tab is opened if Chromium is already running
- When set to `false`, the system will reuse the existing Chromium instance if available

Chromium is always launched with these options for security and stability:
```
--no-sandbox --no-default-browser-check --no-first-run --disable-popup-blocking --disable-session-crashed-bubble --disable-infobars --disable-notifications --disable-save-password-bubble --disable-translate --disable-sync-preferences
```

This approach prevents browser startup issues while allowing you to either use an existing Chromium instance or create a new one based on your needs.

### Macro Execution and Completion

The system monitors the log file for macro completion rather than waiting for Chromium to exit. This allows:

1. Detection of macro completion even if Chromium remains open
2. Proper handling of the `closeBrowser` parameter:
   - When set to "1", Chromium is automatically closed after the macro completes
   - When set to "0", Chromium remains open for subsequent macro executions

The script detects completion by looking for:
- `Status=OK` (successful completion)
- `Status=Error` (error during execution)
- `[status] Macro completed` (completion message in the log)

If the macro doesn't complete within the timeout period, the script will terminate Chromium and report a timeout error.

### Timeout Configuration

The system supports configurable timeout settings for macro execution:

- Default timeout is 300 seconds (5 minutes)
- You can specify a custom timeout in the API request using the `timeout` parameter
- The timeout value must be a positive integer representing seconds
- If a macro doesn't complete within the specified timeout, Chromium will be terminated and an error will be reported

For long-running macros, you may need to increase the timeout value. For example, to set a 10-minute timeout:

```json
{
  "name": "long-running-macro",
  "outboundWebhook": "http://your-callback-url.com/receive",
  "timeout": 600
}
```

### Supported URL Parameters

All URL parameters are supported in the `urlParams` object. For detailed information, please refer to the UI.Vision documentation. [UI.Vision documentation](https://ui.vision/rpa/docs#cmd).


## Callback Response

When a macro completes, the server sends a POST request to the specified `outboundWebhook` URL with the following JSON payload:

```json
{
  "status": "Status=OK",
  "name": "your-macro-name",
  "isFolder": false,
  "newInstance": true,
  "executionTime": "2023-03-15T12:34:56.789Z",
  "exitCode": 0,
  "timeout": 600,
  "echoData": {
    "coverageType": "Factory warranty",
    "serviceType": "Warranty Hardware Maintenance On-Site",
    "status": "Expired",
    "startDate": "January 20, 2020",
    "endDate": "March 09, 2021"
  },
  "logContent": "Status=OK\nMore log content..."
}
```

### Echo Data Extraction

The system automatically extracts data from your UI.Vision macros in two ways:

1. **Echo Commands**: When your macro uses the `echo` command with a variable, like:
   ```
   echo | ${variableName} |
   ```
   The system captures the output and includes it in the `echoData` object in the callback response.

2. **StoreText Commands**: The system also looks for variables created with `storeText` commands:
   ```
   storeText | xpath=//div/element | variableName |
   ```
   If these variables are not already captured via echo commands, the system will attempt to find their values in the log.

#### Handling of Multiline Values

The system captures the complete output of echo commands, including multiline values. When a variable contains multiple lines of text, all lines are preserved in the `echoData` object with newlines converted to `\n` characters in the JSON response.

This allows you to:
- Capture complete, detailed content for all variables
- Extract structured data like tables or multi-part information
- Maintain valid JSON formatting while preserving the full content

The system intelligently detects the end of each echo command by looking for the next command in the log file, ensuring that all lines of output are properly captured.

This automatic extraction makes it easy to get specific data points from your macro execution without having to parse the entire log content. The extracted data is included in the `echoData` field of the callback response as a structured JSON object.

For more information on the UI.Vision command line interface, see the [UI.Vision documentation](https://ui.vision/rpa/docs#cmd).

## License

MIT