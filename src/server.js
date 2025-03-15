const express = require('express');
const { runTest } = require('./taskRunner');
const { validateApiKey } = require('./utils');

const app = express();
const API_PORT = process.env.API_PORT || 3000;
const API_KEY = (process.env.API_KEY || 'default-api-key').replace(/^'|'$/g, '');

app.use(express.json());

// Webhook endpoint
app.post('/run-macro', async (req, res) => {
  const apiKey = req.headers['x-api-key'];
  console.log(`Received API key: ${apiKey}`);
  console.log(`Expected API key: ${API_KEY}`);
  if (!validateApiKey(apiKey, API_KEY)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Extract parameters from the webhook payload
  const { 
    name,                // Name of macro or folder
    isFolder = false,    // Whether name refers to a folder (default: false)
    outboundWebhook,     // URL to send results to
    urlParams = {},      // Additional URL parameters including cmd_var1, cmd_var2, cmd_var3
    newInstance = true,  // Whether to force a new Firefox instance (default: true)
    timeout = 300        // Timeout in seconds (default: 300 - 5 minutes)
  } = req.body;

  if (!name || !outboundWebhook) {
    return res.status(400).json({ error: 'Missing required parameters: name and outboundWebhook' });
  }

  // Validate urlParams format
  if (urlParams && typeof urlParams !== 'object') {
    return res.status(400).json({ error: 'urlParams must be an object' });
  }

  // Validate timeout
  const timeoutValue = parseInt(timeout, 10) || 300;
  
  // Run the test asynchronously
  runTest(name, outboundWebhook, isFolder, urlParams, newInstance, timeoutValue)
    .then(() => console.log(`Test "${name}" dispatched`))
    .catch(err => console.error(`Error running test "${name}":`, err));

  // Respond immediately to the webhook
  res.json({ 
    status: 'Test started', 
    name,
    isFolder,
    newInstance,
    timeout: timeoutValue,
    urlParamsCount: Object.keys(urlParams).length
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(API_PORT, () => console.log(`Server listening on port ${API_PORT}`)); 