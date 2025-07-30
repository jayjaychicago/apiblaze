const AWS = require('aws-sdk');
const crypto = require('crypto');
const https = require('https');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const cognito = new AWS.CognitoIdentityServiceProvider();

// OAuth provider configurations
const OAUTH_PROVIDERS = {
  google: {
    tokenUrl: 'https://oauth2.googleapis.com/token',
    userInfoUrl: 'https://www.googleapis.com/oauth2/v2/userinfo',
    scope: 'openid email profile'
  },
  github: {
    tokenUrl: 'https://github.com/login/oauth/access_token',
    userInfoUrl: 'https://api.github.com/user',
    scope: 'read:user user:email'
  },
  microsoft: {
    tokenUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    userInfoUrl: 'https://graph.microsoft.com/v1.0/me',
    scope: 'openid email profile'
  },
  // Add more providers as needed
};

exports.handler = async (event) => {
  console.log('OAuth Handler Event:', JSON.stringify(event, null, 2));

  try {
    // Handle different trigger types
    switch (event.triggerSource) {
      case 'PreAuthentication_Authentication':
        return await handlePreAuthentication(event);
      case 'PreTokenGeneration_Authentication':
        return await handlePreTokenGeneration(event);
      case 'PreTokenGeneration_NewPasswordChallenge':
        return await handlePreTokenGeneration(event);
      default:
        return event;
    }
  } catch (error) {
    console.error('OAuth Handler Error:', error);
    throw error;
  }
};

async function handlePreAuthentication(event) {
  const { userAttributes } = event.request;
  
  // Check if user is trying to authenticate with OAuth
  if (userAttributes.oauth_provider && userAttributes.oauth_provider_user_id) {
    // Validate OAuth provider configuration
    const customerId = userAttributes.customer_id;
    const providerType = userAttributes.oauth_provider;
    
    const oauthConfig = await getCustomerOAuthConfig(customerId, providerType);
    if (!oauthConfig) {
      throw new Error(`OAuth provider ${providerType} not configured for customer ${customerId}`);
    }
  }
  
  return event;
}

async function handlePreTokenGeneration(event) {
  const { userAttributes } = event.request;
  
  // Add custom claims to the token
  const claimsToAdd = {};
  
  if (userAttributes.customer_id) {
    claimsToAdd['custom:customer_id'] = userAttributes.customer_id;
  }
  
  if (userAttributes.oauth_provider) {
    claimsToAdd['custom:oauth_provider'] = userAttributes.oauth_provider;
  }
  
  if (userAttributes.oauth_provider_user_id) {
    claimsToAdd['custom:oauth_provider_user_id'] = userAttributes.oauth_provider_user_id;
  }
  
  // Add claims to the response
  event.response = {
    ...event.response,
    claimsOverrideDetails: {
      claimsToAddOrOverride: claimsToAdd
    }
  };
  
  return event;
}

async function getCustomerOAuthConfig(customerId, providerType) {
  const params = {
    TableName: 'apiblaze-customer-oauth-configs',
    Key: {
      customer_id: customerId,
      provider_id: providerType
    }
  };
  
  try {
    const result = await dynamodb.get(params).promise();
    return result.Item;
  } catch (error) {
    console.error('Error getting OAuth config:', error);
    return null;
  }
}

// Function to handle OAuth callback and user creation/linking
async function handleOAuthCallback(customerId, providerType, authCode, redirectUri) {
  try {
    // Get customer's OAuth configuration
    const oauthConfig = await getCustomerOAuthConfig(customerId, providerType);
    if (!oauthConfig) {
      throw new Error(`OAuth provider ${providerType} not configured for customer ${customerId}`);
    }
    
    // Exchange authorization code for access token
    const tokenResponse = await exchangeCodeForToken(providerType, authCode, oauthConfig, redirectUri);
    
    // Get user info from OAuth provider
    const userInfo = await getUserInfo(providerType, tokenResponse.access_token);
    
    // Find or create user in Cognito
    const cognitoUser = await findOrCreateCognitoUser(customerId, providerType, userInfo);
    
    return {
      success: true,
      user: cognitoUser,
      accessToken: tokenResponse.access_token
    };
  } catch (error) {
    console.error('OAuth callback error:', error);
    throw error;
  }
}

async function exchangeCodeForToken(providerType, authCode, oauthConfig, redirectUri) {
  const provider = OAUTH_PROVIDERS[providerType];
  if (!provider) {
    throw new Error(`Unsupported OAuth provider: ${providerType}`);
  }
  
  const tokenData = {
    client_id: oauthConfig.client_id,
    client_secret: oauthConfig.client_secret,
    code: authCode,
    grant_type: 'authorization_code',
    redirect_uri: redirectUri
  };
  
  return new Promise((resolve, reject) => {
    const postData = Object.keys(tokenData)
      .map(key => `${key}=${encodeURIComponent(tokenData[key])}`)
      .join('&');
    
    const options = {
      hostname: new URL(provider.tokenUrl).hostname,
      port: 443,
      path: new URL(provider.tokenUrl).pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData)
      }
    };
    
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          resolve(response);
        } catch (error) {
          reject(new Error(`Invalid token response: ${data}`));
        }
      });
    });
    
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function getUserInfo(providerType, accessToken) {
  const provider = OAUTH_PROVIDERS[providerType];
  if (!provider) {
    throw new Error(`Unsupported OAuth provider: ${providerType}`);
  }
  
  return new Promise((resolve, reject) => {
    const options = {
      hostname: new URL(provider.userInfoUrl).hostname,
      port: 443,
      path: new URL(provider.userInfoUrl).pathname,
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'User-Agent': 'ApiBlaze/1.0'
      }
    };
    
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const response = JSON.parse(data);
          resolve(response);
        } catch (error) {
          reject(new Error(`Invalid user info response: ${data}`));
        }
      });
    });
    
    req.on('error', reject);
    req.end();
  });
}

async function findOrCreateCognitoUser(customerId, providerType, userInfo) {
  try {
    // Try to find existing user by OAuth provider user ID
    const listParams = {
      UserPoolId: process.env.USER_POOL_ID,
      Filter: `custom:oauth_provider_user_id = "${userInfo.id}" AND custom:oauth_provider = "${providerType}"`
    };
    
    const listResult = await cognito.listUsers(listParams).promise();
    
    if (listResult.Users.length > 0) {
      // User exists, return existing user
      return listResult.Users[0];
    }
    
    // Create new user
    const createParams = {
      UserPoolId: process.env.USER_POOL_ID,
      Username: userInfo.email,
      UserAttributes: [
        {
          Name: 'email',
          Value: userInfo.email
        },
        {
          Name: 'email_verified',
          Value: 'true'
        },
        {
          Name: 'custom:customer_id',
          Value: customerId
        },
        {
          Name: 'custom:oauth_provider',
          Value: providerType
        },
        {
          Name: 'custom:oauth_provider_user_id',
          Value: userInfo.id.toString()
        }
      ],
      MessageAction: 'SUPPRESS' // Don't send welcome email
    };
    
    const createResult = await cognito.adminCreateUser(createParams).promise();
    return createResult.User;
  } catch (error) {
    console.error('Error finding/creating Cognito user:', error);
    throw error;
  }
}

// Export additional functions for use in other Lambda functions
module.exports = {
  handler: exports.handler,
  handleOAuthCallback,
  getCustomerOAuthConfig,
  exchangeCodeForToken,
  getUserInfo,
  findOrCreateCognitoUser
}; 