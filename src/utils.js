const axios = require('axios');

/**
 * Validates the API key
 * @param {string} receivedKey - The API key received in the request
 * @param {string} expectedKey - The expected API key
 * @returns {boolean} - Whether the API key is valid
 */
function validateApiKey(receivedKey, expectedKey) {
  return receivedKey && receivedKey === expectedKey;
}

/**
 * Sends test results to the outbound webhook
 * @param {string} url - The outbound webhook URL
 * @param {object} results - The test results to send
 * @returns {Promise} - A promise that resolves when the webhook is sent
 */
async function sendWebhookResults(url, results) {
  try {
    const response = await axios.post(url, results);
    console.log(`Webhook sent to ${url}, status: ${response.status}`);
    return response;
  } catch (error) {
    console.error(`Error sending webhook to ${url}:`, error.message);
    throw error;
  }
}

module.exports = {
  validateApiKey,
  sendWebhookResults
}; 