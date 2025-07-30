const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Configure AWS
AWS.config.update({ region: process.env.AWS_REGION });
const dynamodb = new AWS.DynamoDB.DocumentClient();

// Utility functions
const generateResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
  },
  body: JSON.stringify(body)
});

const validateInternalApiKey = (headers) => {
  const authHeader = headers.Authorization || headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return false;
  }
  const token = authHeader.replace('Bearer ', '');
  // In production, validate against a secure token
  return token === process.env.INTERNAL_API_KEY;
};

const validateCognitoToken = async (token) => {
  try {
    const cognito = new AWS.CognitoIdentityServiceProvider();
    const result = await cognito.getUser({
      AccessToken: token
    }).promise();
    return result;
  } catch (error) {
    console.error('Cognito validation error:', error);
    return null;
  }
};

// Project management functions
const createProject = async (projectData) => {
  // Validate required fields
  if (!projectData.project_id) {
    throw new Error('project_id is required');
  }
  if (!projectData.target_url) {
    throw new Error('target_url is required');
  }
  if (!projectData.customer_id) {
    throw new Error('customer_id is required');
  }

  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    Item: {
      PK: `PROJECT#${projectData.project_id}`,
      SK: `VERSION#${projectData.api_version || 'v1'}`,
      GSI1PK: `CUSTOMER#${projectData.customer_id || 'default'}`,
      GSI1SK: `PROJECT#${projectData.project_id}`,
      project_id: projectData.project_id,
      api_version: projectData.api_version || 'v1',
      customer_id: projectData.customer_id,
      target_url: projectData.target_url,
      auth_type: projectData.auth_type || 'api_key',
      target_auth_type: projectData.target_auth_type || 'none',
      target_api_key: projectData.target_api_key,
      active: projectData.active !== false,
      created_at: Date.now(),
      updated_at: Date.now(),
      ...projectData
    }
  };

  await dynamodb.put(params).promise();
  return params.Item;
};

const getProject = async (projectId, apiVersion = 'v1') => {
  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    Key: {
      PK: `PROJECT#${projectId}`,
      SK: `VERSION#${apiVersion}`
    }
  };

  const result = await dynamodb.get(params).promise();
  return result.Item;
};

const updateProject = async (projectId, apiVersion, updates) => {
  const updateExpression = [];
  const expressionAttributeNames = {};
  const expressionAttributeValues = {};

  Object.entries(updates).forEach(([key, value]) => {
    if (key !== 'project_id' && key !== 'api_version') {
      updateExpression.push(`#${key} = :${key}`);
      expressionAttributeNames[`#${key}`] = key;
      expressionAttributeValues[`:${key}`] = value;
    }
  });

  updateExpression.push('#updated_at = :updated_at');
  expressionAttributeNames['#updated_at'] = 'updated_at';
  expressionAttributeValues[':updated_at'] = Date.now();

  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    Key: {
      PK: `PROJECT#${projectId}`,
      SK: `VERSION#${apiVersion}`
    },
    UpdateExpression: `SET ${updateExpression.join(', ')}`,
    ExpressionAttributeNames: expressionAttributeNames,
    ExpressionAttributeValues: expressionAttributeValues,
    ReturnValues: 'ALL_NEW'
  };

  const result = await dynamodb.update(params).promise();
  return result.Attributes;
};

const deleteProject = async (projectId, apiVersion = 'v1') => {
  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    Key: {
      PK: `PROJECT#${projectId}`,
      SK: `VERSION#${apiVersion}`
    }
  };

  await dynamodb.delete(params).promise();
  return { success: true };
};

const listProjects = async (customerId) => {
  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    IndexName: 'GSI1',
    KeyConditionExpression: 'GSI1PK = :customer_id',
    ExpressionAttributeValues: {
      ':customer_id': `CUSTOMER#${customerId}`
    }
  };

  const result = await dynamodb.query(params).promise();
  return result.Items;
};

// User management functions
const createUser = async (userData) => {
  const params = {
    TableName: process.env.DYNAMODB_USERS_TABLE,
    Item: {
      user_id: userData.user_id || uuidv4(),
      email: userData.email,
      customer_id: userData.customer_id,
      user_role: userData.user_role || 'user',
      created_at: Date.now(),
      updated_at: Date.now(),
      ...userData
    }
  };

  await dynamodb.put(params).promise();
  return params.Item;
};

const getUser = async (userId) => {
  const params = {
    TableName: process.env.DYNAMODB_USERS_TABLE,
    Key: {
      user_id: userId
    }
  };

  const result = await dynamodb.get(params).promise();
  return result.Item;
};

const getUserByEmail = async (email) => {
  const params = {
    TableName: process.env.DYNAMODB_USERS_TABLE,
    IndexName: 'email-index',
    KeyConditionExpression: 'email = :email',
    ExpressionAttributeValues: {
      ':email': email
    }
  };

  const result = await dynamodb.query(params).promise();
  return result.Items[0];
};

const updateUser = async (userId, updates) => {
  const updateExpression = [];
  const expressionAttributeNames = {};
  const expressionAttributeValues = {};

  Object.entries(updates).forEach(([key, value]) => {
    if (key !== 'user_id') {
      updateExpression.push(`#${key} = :${key}`);
      expressionAttributeNames[`#${key}`] = key;
      expressionAttributeValues[`:${key}`] = value;
    }
  });

  updateExpression.push('#updated_at = :updated_at');
  expressionAttributeNames['#updated_at'] = 'updated_at';
  expressionAttributeValues[':updated_at'] = Date.now();

  const params = {
    TableName: process.env.DYNAMODB_USERS_TABLE,
    Key: {
      user_id: userId
    },
    UpdateExpression: `SET ${updateExpression.join(', ')}`,
    ExpressionAttributeNames: expressionAttributeNames,
    ExpressionAttributeValues: expressionAttributeValues,
    ReturnValues: 'ALL_NEW'
  };

  const result = await dynamodb.update(params).promise();
  return result.Attributes;
};

// User project access functions
const grantUserAccess = async (userId, projectId, accessData) => {
  const params = {
    TableName: process.env.DYNAMODB_USER_PROJECT_ACCESS_TABLE,
    Item: {
      user_id: userId,
      project_id: projectId,
      customer_id: accessData.customer_id,
      has_access: accessData.has_access !== false,
      access_level: accessData.access_level || 'user',
      created_at: Date.now(),
      updated_at: Date.now(),
      ...accessData
    }
  };

  await dynamodb.put(params).promise();
  return params.Item;
};

const getUserAccess = async (userId, projectId) => {
  const params = {
    TableName: process.env.DYNAMODB_USER_PROJECT_ACCESS_TABLE,
    Key: {
      user_id: userId,
      project_id: projectId
    }
  };

  const result = await dynamodb.get(params).promise();
  return result.Item;
};

const revokeUserAccess = async (userId, projectId) => {
  const params = {
    TableName: process.env.DYNAMODB_USER_PROJECT_ACCESS_TABLE,
    Key: {
      user_id: userId,
      project_id: projectId
    }
  };

  await dynamodb.delete(params).promise();
  return { success: true };
};

// API key management functions
const createApiKey = async (apiKeyData) => {
  const params = {
    TableName: process.env.DYNAMODB_API_KEYS_TABLE,
    Item: {
      api_key_hash: apiKeyData.api_key_hash,
      project_id: apiKeyData.project_id,
      user_id: apiKeyData.user_id,
      name: apiKeyData.name,
      active: apiKeyData.active !== false,
      expires_at: apiKeyData.expires_at,
      created_at: Date.now(),
      updated_at: Date.now(),
      ...apiKeyData
    }
  };

  await dynamodb.put(params).promise();
  return params.Item;
};

const getApiKey = async (apiKeyHash, projectId) => {
  const params = {
    TableName: process.env.DYNAMODB_API_KEYS_TABLE,
    Key: {
      api_key_hash: apiKeyHash,
      project_id: projectId
    }
  };

  const result = await dynamodb.get(params).promise();
  return result.Item;
};

const listUserApiKeys = async (userId) => {
  const params = {
    TableName: process.env.DYNAMODB_API_KEYS_TABLE,
    IndexName: 'user_id-index',
    KeyConditionExpression: 'user_id = :user_id',
    ExpressionAttributeValues: {
      ':user_id': userId
    }
  };

  const result = await dynamodb.query(params).promise();
  return result.Items;
};

const deactivateApiKey = async (apiKeyHash, projectId) => {
  const params = {
    TableName: process.env.DYNAMODB_API_KEYS_TABLE,
    Key: {
      api_key_hash: apiKeyHash,
      project_id: projectId
    },
    UpdateExpression: 'SET #active = :active, #updated_at = :updated_at',
    ExpressionAttributeNames: {
      '#active': 'active',
      '#updated_at': 'updated_at'
    },
    ExpressionAttributeValues: {
      ':active': false,
      ':updated_at': Date.now()
    },
    ReturnValues: 'ALL_NEW'
  };

  const result = await dynamodb.update(params).promise();
  return result.Attributes;
};

// Main handler
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  // Handle CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return generateResponse(200, {});
  }

  try {
    // Handle both direct API Gateway events and direct body calls
    let path, method, headers, body, queryStringParameters;
    
    if (event.path && event.httpMethod) {
      // Full API Gateway event
      path = event.path;
      method = event.httpMethod;
      headers = event.headers || {};
      body = event.body ? JSON.parse(event.body) : {};
      queryStringParameters = event.queryStringParameters || {};
    } else {
      // Direct body call (for testing)
      path = '/admin/projects';
      method = 'POST';
      headers = {};
      body = event;
      queryStringParameters = {};
    }

    // Validate internal API key for admin operations (temporarily disabled for debugging)
    // if (!validateInternalApiKey(headers)) {
    //   return generateResponse(401, { error: 'Unauthorized' });
    // }

    // Route based on path (strip /admin prefix if present)
    const cleanPath = path.startsWith('/admin') ? path.substring(6) : path;
    
    if (cleanPath.startsWith('/projects')) {
      const projectId = cleanPath.split('/')[2];
      const apiVersion = cleanPath.split('/')[3] || 'v1';

      if (method === 'POST' && !projectId) {
        // Create new project
        const project = await createProject(body);
        return generateResponse(201, project);
      } else if (method === 'GET' && projectId) {
        // Get project
        const project = await getProject(projectId, apiVersion);
        if (!project) {
          return generateResponse(404, { error: 'Project not found' });
        }
        return generateResponse(200, project);
      } else if (method === 'PUT' && projectId) {
        // Update project
        const project = await updateProject(projectId, apiVersion, body);
        return generateResponse(200, project);
      } else if (method === 'DELETE' && projectId) {
        // Delete project
        await deleteProject(projectId, apiVersion);
        return generateResponse(200, { success: true });
      } else if (method === 'GET' && !projectId) {
        // List projects for customer
        const customerId = queryStringParameters.customer_id || 'default';
        const projects = await listProjects(customerId);
        return generateResponse(200, { projects });
      }
    } else if (cleanPath.startsWith('/users')) {
      const userId = cleanPath.split('/')[2];

      if (method === 'POST' && !userId) {
        // Create new user
        const user = await createUser(body);
        return generateResponse(201, user);
      } else if (method === 'GET' && userId) {
        // Get user
        const user = await getUser(userId);
        if (!user) {
          return generateResponse(404, { error: 'User not found' });
        }
        return generateResponse(200, user);
      } else if (method === 'PUT' && userId) {
        // Update user
        const user = await updateUser(userId, body);
        return generateResponse(200, user);
      } else if (method === 'GET' && body.email) {
        // Get user by email
        const user = await getUserByEmail(body.email);
        if (!user) {
          return generateResponse(404, { error: 'User not found' });
        }
        return generateResponse(200, user);
      }
    } else if (cleanPath.includes('/users/') && cleanPath.includes('/projects/') && cleanPath.includes('/access')) {
      const pathParts = cleanPath.split('/');
      const userId = pathParts[2];
      const projectId = pathParts[4];

      if (method === 'POST') {
        // Grant user access
        const access = await grantUserAccess(userId, projectId, body);
        return generateResponse(201, access);
      } else if (method === 'GET') {
        // Get user access
        const access = await getUserAccess(userId, projectId);
        if (!access) {
          return generateResponse(404, { error: 'Access not found' });
        }
        return generateResponse(200, access);
      } else if (method === 'DELETE') {
        // Revoke user access
        await revokeUserAccess(userId, projectId);
        return generateResponse(200, { success: true });
      }
    } else if (cleanPath.startsWith('/api-keys')) {
      const apiKeyHash = cleanPath.split('/')[2];
      const projectId = cleanPath.split('/')[3];

      if (method === 'POST' && !apiKeyHash) {
        // Create new API key
        const apiKey = await createApiKey(body);
        return generateResponse(201, apiKey);
      } else if (method === 'GET' && apiKeyHash && projectId) {
        // Get API key
        const apiKey = await getApiKey(apiKeyHash, projectId);
        if (!apiKey) {
          return generateResponse(404, { error: 'API key not found' });
        }
        return generateResponse(200, apiKey);
      } else if (method === 'DELETE' && apiKeyHash && projectId) {
        // Deactivate API key
        const apiKey = await deactivateApiKey(apiKeyHash, projectId);
        return generateResponse(200, apiKey);
      } else if (method === 'GET' && body.user_id) {
        // List user API keys
        const apiKeys = await listUserApiKeys(body.user_id);
        return generateResponse(200, { api_keys: apiKeys });
      }
    }

    return generateResponse(404, { error: 'Endpoint not found' });

  } catch (error) {
    console.error('Error:', error);
    
    // Handle validation errors
    if (error.message && error.message.includes('is required')) {
      return generateResponse(400, { error: error.message });
    }
    
    // Handle DynamoDB errors
    if (error.code === 'ConditionalCheckFailedException') {
      return generateResponse(409, { error: 'Resource already exists' });
    }
    
    if (error.code === 'ResourceNotFoundException') {
      return generateResponse(404, { error: 'Resource not found' });
    }
    
    // Default error response
    return generateResponse(500, { error: 'Internal server error' });
  }
}; 