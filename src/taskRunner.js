const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const { sendWebhookResults } = require('./utils');

// Keep track of running processes
let runningProcesses = {};
let processCounter = 0;

/**
 * Runs a UI.Vision test with the specified parameters
 * @param {string} name - The name of the macro or folder to run
 * @param {string} outboundWebhook - URL to send test results to
 * @param {boolean} isFolder - Whether name refers to a folder (default: false)
 * @param {object} urlParams - Additional URL parameters including cmd_var1, cmd_var2, cmd_var3
 * @param {boolean} newInstance - Whether to force a new Firefox instance (default: true)
 * @param {number} timeout - Timeout in seconds (default: 300 - 5 minutes)
 * @returns {Promise} - A promise that resolves when the test is complete
 */
async function runTest(name, outboundWebhook, isFolder = false, urlParams = {}, newInstance = true, timeout = 300) {
  const processId = processCounter++;
  console.log(`Starting test "${name}" with process ID ${processId}, isFolder: ${isFolder}, newInstance: ${newInstance}, timeout: ${timeout}s`);
  
  // Check if the macro file exists in the new location
  // Only check if it's a macro, not a folder
  if (!isFolder) {
    const macroFilePath = `/usr/src/uivision/macros/${name}.json`;
    if (!fs.existsSync(macroFilePath)) {
      throw new Error(`Macro file not found: ${macroFilePath}`);
    }
  }
  
  // Check if we should force a new instance
  if (urlParams.hasOwnProperty('newInstance')) {
    newInstance = urlParams.newInstance === '1' || urlParams.newInstance === 'true';
    // Remove from urlParams as we'll handle it separately
    delete urlParams.newInstance;
  }
  
  // Check if timeout was provided in urlParams (for backward compatibility)
  if (urlParams.hasOwnProperty('timeout')) {
    timeout = parseInt(urlParams.timeout, 10) || 300;
    // Remove from urlParams as we'll handle it separately
    delete urlParams.timeout;
  }
  
  // Ensure timeout is a valid number
  timeout = parseInt(timeout, 10) || 300;
  
  // Ensure closeBrowser and closeRPA are strings
  if (urlParams.hasOwnProperty('closeBrowser')) {
    urlParams.closeBrowser = String(urlParams.closeBrowser);
  }
  if (urlParams.hasOwnProperty('closeRPA')) {
    urlParams.closeRPA = String(urlParams.closeRPA);
  }
  
  // Convert urlParams to a JSON string
  const urlParamsStr = JSON.stringify(urlParams);
  
  // Path to the shell script
  const scriptPath = '/usr/src/app/src/run-firefox.sh';
  
  // Build the command to run the shell script
  const command = `${scriptPath} "${name}" "${outboundWebhook}" "${isFolder ? 1 : 0}" '${urlParamsStr}' "${newInstance ? 1 : 0}" "${timeout}"`;
  
  console.log(`Executing command: ${command}`);
  
  return new Promise((resolve, reject) => {
    // Flag to track if a webhook has already been sent
    let webhookSent = false;
    
    // Execute the command
    const process = exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error executing command: ${error.message}`);
        
        // Check for specific error codes
        let errorMessage = error.message;
        if (error.code === 3) {
          errorMessage = "Firefox is already running but not responding. Please kill the existing Firefox process and try again.";
          console.error(errorMessage);
        }
        
        // Only send webhook if one hasn't been sent by the Firefox script
        if (!webhookSent && !stdout.includes("Sending JSON payload to callback URL")) {
          webhookSent = true;
          // Send error to the outbound webhook
          sendWebhookResults(outboundWebhook, {
            status: 'error',
            name,
            isFolder,
            newInstance,
            timeout,
            error: errorMessage,
            timestamp: new Date().toISOString()
          }).catch(err => console.error('Error sending webhook:', err));
        }
        
        reject(error);
        return;
      }
      
      if (stderr) {
        console.error(`Command stderr: ${stderr}`);
      }
      
      console.log(`Command stdout: ${stdout}`);
      
      // UI.Vision will handle sending results to the outbound webhook
      // via the callback parameter
      
      console.log(`Test "${name}" completed`);
      
      // Remove from running processes
      delete runningProcesses[processId];
      
      resolve({
        status: 'completed',
        name,
        isFolder,
        newInstance,
        timeout,
        timestamp: new Date().toISOString()
      });
    });
    
    // Store the process
    runningProcesses[processId] = process;
    
    // Handle process exit
    process.on('exit', (code) => {
      console.log(`Process for test "${name}" exited with code ${code}`);
      
      // Remove from running processes
      delete runningProcesses[processId];
      
      if (code !== 0 && !webhookSent) {
        // Only send webhook if one hasn't been sent already
        webhookSent = true;
        // Send error to the outbound webhook
        sendWebhookResults(outboundWebhook, {
          status: 'error',
          name,
          isFolder,
          newInstance,
          timeout,
          error: `Process exited with code ${code}`,
          timestamp: new Date().toISOString()
        }).catch(err => console.error('Error sending webhook:', err));
      }
    });
  });
}

module.exports = { runTest }; 