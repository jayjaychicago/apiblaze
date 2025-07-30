const AWS = require('aws-sdk');
const { handleOAuthCallback } = require('../oauth-handler');

const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
  console.log('OAuth Callback Event:', JSON.stringify(event, null, 2));

  try {
    const { customerId, providerType, code, state, redirectUri } = JSON.parse(event.body);

    // Validate required parameters
    if (!customerId || !providerType || !code || !redirectUri) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'Content-Type,Authorization',
          'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        body: JSON.stringify({
          error: 'Missing required parameters: customerId, providerType, code, redirectUri'
        })
      };
    }

    // Handle OAuth callback
    const result = await handleOAuthCallback(customerId, providerType, code, redirectUri);

    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
      },
      body: JSON.stringify(result)
    };

  } catch (error) {
    console.error('OAuth Callback Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
      },
      body: JSON.stringify({
        error: 'OAuth callback failed',
        message: error.message
      })
    };
  }
}; 