Project Overview
This project is a Dockerized solution designed to automate UI testing workflows using headless Chrome preloaded with the UI.Vision extension. It exposes an authenticated REST API that accepts webhook requests containing a list of serial numbers, a test identifier, and an outbound webhook URL. When a request is received, the system:

Validates the API key for secure access.
Initiates a concurrent task that launches a headless Chrome instance with the UI.Vision extension.
Executes a specified UI.Vision test (provided as a JSON file) after injecting dynamic variables.
Collects test results and posts them back to a designated outbound webhook URL.
The container is built to run all components required for this automation process within a single deployment unit, ensuring flexibility in triggering different tests and scalability to handle concurrent tasks. This design is particularly useful for automating browser-based checks and integrating with external systems via webhooks.



1. Project Structure
Set up your repository with a structure similar to:

pgsql
Copy
/project-root
  ├── Dockerfile
  ├── package.json
  ├── package-lock.json
  ├── src
  │    ├── server.js           // Express API server
  │    ├── taskRunner.js       // Code to launch Chrome/Puppeteer with UI.Vision
  │    └── utils.js            // Helper functions (e.g. API key check, callback POST)
  └── extensions
         └── uivision          // UI.Vision extension folder (unpacked CRX)
You’ll need to download or extract the UI.Vision extension files and place them in the extensions/uivision folder.
It will also need a folder for the macro files to live in so it can call the macro specified in the webhook sent to it

2. Dockerfile
Create a Dockerfile that installs Node.js, headless Chrome, and the required libraries. For example:

dockerfile
Copy
# Use an official Node.js runtime as a parent image
FROM node:18-slim

# Install necessary packages: wget, unzip, and dependencies for Chrome
RUN apt-get update && \
    apt-get install -y wget gnupg ca-certificates --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    apt-get install -y google-chrome-stable --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /usr/src/app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy the source code and UI.Vision extension into the container
COPY src ./src
COPY extensions ./extensions

# Expose the API port (for example, 3000)
EXPOSE 3000

# Start the server
CMD ["node", "src/server.js"]
Notes:

Ensure that you include all necessary OS libraries so that Puppeteer can run Chrome. You might need to add libraries like libnss3, libxss1, libappindicator3-1, etc. (depending on your environment).
If headless mode does not allow extensions by default, you may need to use Chrome’s “headless” flag alternatives (see below).


3. package.json & Dependencies
Your Node.js project should include Express and Puppeteer (or Puppeteer-core). For example:

json
Copy
{
  "name": "uivision-automation",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "puppeteer": "^20.7.4",
    "axios": "^1.4.0" // for outbound webhook POSTs
  }
}
4. Server Code (src/server.js)
Develop an Express server that:

Exposes an endpoint (e.g. POST /run-test) that accepts a JSON payload.
Validates the API key (using a header or query parameter).
Extracts parameters: list of serial numbers, test identifier, outbound webhook URL.
Dispatches a task (using an async function or job queue) by calling your task runner module.
A simplified version:

javascript
Copy
const express = require('express');
const { runTest } = require('./taskRunner');
const { validateApiKey } = require('./utils');

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || 'your-api-key';

app.use(express.json());

// Webhook endpoint
app.post('/run-test', async (req, res) => {
  const apiKey = req.headers['x-api-key'];
  if (!validateApiKey(apiKey, API_KEY)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Expect payload with serialNumbers, testId, outboundWebhook
  const { serialNumbers, testId, outboundWebhook } = req.body;
  if (!serialNumbers || !testId || !outboundWebhook) {
    return res.status(400).json({ error: 'Missing parameters' });
  }

  // Run the test asynchronously
  runTest(serialNumbers, testId, outboundWebhook)
    .then(() => console.log('Test dispatched'))
    .catch(err => console.error('Error running test:', err));

  res.json({ status: 'Test started' });
});

app.listen(PORT, () => console.log(`Server listening on port ${PORT}`));
5. Task Runner Module (src/taskRunner.js)
This module uses Puppeteer to launch a headless Chrome instance with the UI.Vision extension loaded. Note that standard headless mode disables extensions. To work around this, you may need to run Chrome in “headful” mode without a visible window by using a virtual framebuffer (or try launching with --headless=new if supported).

Example code:

javascript
Copy
const puppeteer = require('puppeteer');
const axios = require('axios');
const path = require('path');

async function runTest(serialNumbers, testId, outboundWebhook) {
  // Determine test file path based on testId (assuming UI.Vision test JSON is stored locally)
  const testFilePath = path.resolve(__dirname, '../extensions/uivision/tests', `${testId}.json`);
  
  // Launch Chrome with UI.Vision extension loaded
  const browser = await puppeteer.launch({
    headless: false, // use headful mode if headless disables extensions
    args: [
      `--disable-extensions-except=${path.resolve(__dirname, '../extensions/uivision')}`,
      `--load-extension=${path.resolve(__dirname, '../extensions/uivision')}`,
      '--no-sandbox',
      '--disable-setuid-sandbox'
    ]
  });

  const page = await browser.newPage();

  // Optionally navigate to a blank page or a specific URL if needed
  await page.goto('about:blank');

  // Inject dynamic variables into UI.Vision test environment
  // You can use page.evaluate to set window variables or use query parameters.
  await page.evaluate((serials) => {
    window.testVariables = { serialNumbers: serials };
  }, serialNumbers);

  // Trigger UI.Vision execution. There are two approaches:
  // 1. If UI.Vision exposes a JS API, call that API to run the test.
  // 2. If not, simulate clicking the UI.Vision UI by navigating to a URL that starts the test.
  // For example, assume a global function window.runUIVisionTest exists.
  await page.evaluate(async (testFilePath) => {
    // This is pseudo-code: you need to adapt this to how UI.Vision is triggered.
    if (window.runUIVisionTest) {
      await window.runUIVisionTest(testFilePath);
    } else {
      console.error('UI.Vision API not available');
    }
  }, testFilePath);

  // Wait for the test to complete. This can be done by polling or listening for a callback.
  // For example, wait for a global variable to be set.
  await page.waitForFunction('window.testCompleted === true', { timeout: 60000 }).catch(() => {
    console.error('Test timed out');
  });

  // Collect the test results
  const results = await page.evaluate(() => {
    return window.testResults || { status: 'unknown' };
  });

  // Close browser
  await browser.close();

  // Post the results to the outbound webhook
  try {
    await axios.post(outboundWebhook, results);
  } catch (error) {
    console.error('Error posting results to outbound webhook:', error);
  }
}

module.exports = { runTest };
Key points:

UI.Vision Invocation:
Adapt the code in the page.evaluate section to correctly trigger the UI.Vision test. Depending on how your UI.Vision extension exposes its functionality, you might have to simulate user interaction (e.g., clicking a button) or call a custom JS function.
Headless Mode Issue:
Since Chrome in true headless mode disables extensions, you might run in “headful” mode but without showing the window (using xvfb on Linux or another virtual display solution). Alternatively, check if the --headless=new flag works with your UI.Vision version.
Timeouts and Logging:
Adjust wait times and logging as needed.
6. Utility Module (src/utils.js)
Create a simple utility for validating API keys:

javascript
Copy
function validateApiKey(receivedKey, expectedKey) {
  return receivedKey && receivedKey === expectedKey;
}

module.exports = { validateApiKey };
7. Environment Variables & Deployment
API Key:
Use environment variables to pass the API key (e.g. via Docker run command:
docker run -e API_KEY=your-secret-key -p 3000:3000 your-image).

Port Configuration:
Configure the container to use a configurable port via an environment variable.

Scaling & Concurrency:
The Express server dispatches tasks asynchronously so multiple tests can run concurrently. Monitor system resource usage and consider a job queue if you expect heavy loads.

8. Building and Running the Docker Container
Build the Docker Image:

bash
Copy
docker build -t uivision-automation .
Run the Container:

bash
Copy
docker run -d -e API_KEY=your-secret-key -p 3000:3000 uivision-automation
Trigger a Test:
Make an authenticated POST request to http://localhost:3000/run-test with a JSON payload like:

json
Copy
{
  "serialNumbers": ["SN123", "SN456"],
  "testId": "test1",
  "outboundWebhook": "http://your-callback-url.com/receive"
}
9. Final Considerations
Error Handling:
Ensure each step has proper error handling. If a test fails or times out, log the error and post an error message to the outbound webhook.

Security:
Limit exposure by requiring an API key and potentially adding rate limiting or IP filtering.

Testing:
Thoroughly test the integration locally. Verify that the UI.Vision extension loads correctly and that your automation trigger correctly starts the test.

Extension Updates:
If the UI.Vision extension is updated, be sure to update the files in your repository.