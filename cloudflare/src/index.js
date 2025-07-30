/**
 * APIBLAZE - Main Cloudflare Worker
 * Handles routing, authentication, and API proxying
 */

// Utility functions
const generateApiKey = () => {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = 'apiblaze_';
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
};

const hashApiKey = (apiKey) => {
  // Simple hash function that works in Cloudflare Workers
  let hash = 0;
  for (let i = 0; i < apiKey.length; i++) {
    const char = apiKey.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  return Math.abs(hash).toString(36);
};

const parseJWT = (token) => {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(atob(base64).split('').map(c => {
      return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
    }).join(''));
    return JSON.parse(jsonPayload);
  } catch (error) {
    return null;
  }
};

const validateCognitoToken = async (token) => {
  try {
    // In production, validate against Cognito JWKS
    const decoded = parseJWT(token);
    if (!decoded) return null;
    
    // Basic validation - in production, verify signature and expiration
    if (decoded.aud !== env.COGNITO_USER_POOL_CLIENT_ID) return null;
    if (decoded.exp < Date.now() / 1000) return null;
    
    return decoded;
  } catch (error) {
    return null;
  }
};

const getProjectConfig = async (projectId, env) => {
  try {
    console.log('Getting project config for:', projectId);
    
    // Try KV cache first
    let config = await env.PROJECTS.get(projectId, { type: 'json' });
    console.log('KV lookup result:', config ? 'found' : 'not found');
    
    if (!config) {
      console.log('KV cache miss, trying DynamoDB fallback...');
      console.log('API Gateway URL:', `${env.API_GATEWAY_URL}/projects/${projectId}`);
      console.log('Internal API Key:', env.INTERNAL_API_KEY ? 'present' : 'missing');
      
      // Fallback to DynamoDB
      const response = await fetch(`${env.API_GATEWAY_URL}/projects/${projectId}`, {
        headers: {
          'Authorization': `Bearer ${env.INTERNAL_API_KEY}`,
          'Content-Type': 'application/json'
        }
      });
      
      console.log('DynamoDB response status:', response.status);
      console.log('DynamoDB response headers:', Object.fromEntries(response.headers.entries()));
      
      if (response.ok) {
        config = await response.json();
        console.log('DynamoDB lookup successful, caching in KV...');
        // Cache in KV
        await env.PROJECTS.put(projectId, JSON.stringify(config), { expirationTtl: 300 });
        console.log('Project cached in KV successfully');
      } else {
        console.log('DynamoDB lookup failed');
        const errorText = await response.text();
        console.log('DynamoDB error response:', errorText);
      }
    }
    
    return config;
  } catch (error) {
    console.error('Error getting project config:', error);
    return null;
  }
};

const validateApiKey = async (apiKey, projectId, env) => {
  try {
    const hashedKey = hashApiKey(apiKey);
    const keyData = await env.API_KEYS.get(`${hashedKey}:${projectId}`, { type: 'json' });
    
    if (!keyData) return null;
    
    // Check if key is active and not expired
    if (!keyData.active || (keyData.expires_at && keyData.expires_at < Date.now())) {
      return null;
    }
    
    return keyData;
  } catch (error) {
    console.error('Error validating API key:', error);
    return null;
  }
};

const getUserAccess = async (userId, projectId, env) => {
  try {
    // Try KV cache first
    let access = await env.USER_ACCESS.get(`${userId}:${projectId}`, { type: 'json' });
    
    if (!access) {
      // Fallback to DynamoDB
      const response = await fetch(`${env.API_GATEWAY_URL}/users/${userId}/projects/${projectId}/access`, {
        headers: {
          'Authorization': `Bearer ${env.INTERNAL_API_KEY}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (response.ok) {
        access = await response.json();
        // Cache in KV
        await env.USER_ACCESS.put(`${userId}:${projectId}`, JSON.stringify(access), { expirationTtl: 300 });
      }
    }
    
    return access;
  } catch (error) {
    console.error('Error getting user access:', error);
    return null;
  }
};

const proxyRequest = async (request, targetUrl, authHeaders = {}) => {
  try {
    const url = new URL(request.url);
    const targetUrlObj = new URL(targetUrl);
    
    // Build the target URL
    targetUrlObj.pathname = url.pathname;
    targetUrlObj.search = url.search;
    
    // Prepare headers
    const headers = new Headers();
    
    // Copy original headers, excluding host
    for (const [key, value] of request.headers.entries()) {
      if (key.toLowerCase() !== 'host') {
        headers.set(key, value);
      }
    }
    
    // Add auth headers
    Object.entries(authHeaders).forEach(([key, value]) => {
      if (value) headers.set(key, value);
    });
    
    // Set host header for target
    headers.set('Host', targetUrlObj.host);
    
    // Create the proxy request
    const proxyRequest = new Request(targetUrlObj.toString(), {
      method: request.method,
      headers: headers,
      body: request.body,
      redirect: 'follow'
    });
    
    // Make the request
    const response = await fetch(proxyRequest);
    
    // Return the response
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers
    });
  } catch (error) {
    console.error('Proxy error:', error);
    return new Response(JSON.stringify({ error: 'Proxy error' }), {
      status: 502,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};

const handleApiRequest = async (request, env) => {
  const url = new URL(request.url);
  const hostname = url.hostname;
  
  // Extract project ID from subdomain
  const subdomain = hostname.split('.')[0];
  if (subdomain === 'www' || subdomain === 'api' || subdomain === 'dashboard' || subdomain === 'apiportal') {
    return new Response('Not found', { status: 404 });
  }
  
  const projectId = subdomain;
  
  // Add debugging
  console.log('Subdomain request:', {
    hostname,
    subdomain,
    projectId,
    path: url.pathname
  });
  
  // Simple test endpoint
  if (projectId === 'test') {
    return new Response(JSON.stringify({
      message: 'Subdomain routing is working!',
      hostname,
      subdomain,
      projectId,
      path: url.pathname
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  // Get project configuration - convert to lowercase for case-insensitive lookup
  const projectConfig = await getProjectConfig(projectId.toLowerCase(), env);
  console.log('Project config result:', projectConfig ? 'found' : 'not found');
  
  if (!projectConfig) {
    return new Response(JSON.stringify({ error: 'Project not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  // Check if project is active
  if (!projectConfig.active) {
    return new Response(JSON.stringify({ error: 'Project is inactive' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  // Handle authentication based on project settings
  let authResult = null;
  
  switch (projectConfig.auth_type) {
    case 'api_key':
      const apiKey = request.headers.get('X-API-Key') || request.headers.get('Authorization')?.replace('Bearer ', '');
      if (!apiKey) {
        return new Response(JSON.stringify({ error: 'API key required' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      authResult = await validateApiKey(apiKey, projectId, env);
      if (!authResult) {
        return new Response(JSON.stringify({ error: 'Invalid API key' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      break;
      
    case 'oauth':
      const authHeader = request.headers.get('Authorization');
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return new Response(JSON.stringify({ error: 'OAuth token required' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      
      const token = authHeader.replace('Bearer ', '');
      const decodedToken = await validateCognitoToken(token);
      if (!decodedToken) {
        return new Response(JSON.stringify({ error: 'Invalid OAuth token' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      
      // Check user access to project
      const userAccess = await getUserAccess(decodedToken.sub, projectId, env);
      if (!userAccess || !userAccess.has_access) {
        return new Response(JSON.stringify({ error: 'Access denied' }), {
          status: 403,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      
      authResult = { user_id: decodedToken.sub, access_level: userAccess.access_level };
      break;
      
    case 'none':
      // No authentication required
      break;
      
    default:
      return new Response(JSON.stringify({ error: 'Invalid authentication type' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
  }
  
  // Prepare auth headers for target server
  let targetAuthHeaders = {};
  
  if (projectConfig.target_auth_type === 'api_key') {
    targetAuthHeaders['X-API-Key'] = projectConfig.target_api_key;
  } else if (projectConfig.target_auth_type === 'oauth' && authResult) {
    // Get OAuth token for target server
    const oauthToken = await env.OAUTH_TOKENS.get(`${authResult.user_id}:${projectId}`, { type: 'json' });
    if (oauthToken && oauthToken.access_token) {
      targetAuthHeaders['Authorization'] = `Bearer ${oauthToken.access_token}`;
    }
  }
  
  // Proxy the request to target server
  return await proxyRequest(request, projectConfig.target_url, targetAuthHeaders);
};

const handleCommandLineInterface = async (request, env) => {
  const url = new URL(request.url);
  
  if (request.method === 'POST') {
    try {
      console.log('POST request received');
      console.log('Request headers:', Object.fromEntries(request.headers.entries()));
      
      let body;
      try {
        body = await request.json();
        console.log('Request body:', body);
      } catch (jsonError) {
        console.error('JSON parsing error:', jsonError);
        return new Response(JSON.stringify({ error: 'Invalid JSON in request body' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      
      // Handle different CLI commands
      if (body && body.target) {
        // Create a new API proxy
        const projectId = generateApiKey().replace('apiblaze_', '').toLowerCase();
        const apiKey = generateApiKey();
        
        console.log('Generated project ID:', projectId);
        console.log('Generated API key:', apiKey);
        
        // Store project data in KV and DynamoDB via API Gateway
        try {
          const projectData = {
            project_id: projectId,
            target_url: body.target,
            auth_type: body.auth_type || 'api_key',
            customer_id: body.customer_id || 'default',
            active: true,
            created_at: Date.now()
          };
          
          // Store in KV namespace for fast access
          await env.PROJECTS.put(projectId, JSON.stringify(projectData));
          
          // Store API key hash in KV
          const apiKeyHash = await hashApiKey(apiKey);
          await env.API_KEYS.put(`${apiKeyHash}:${projectId}`, JSON.stringify({
            project_id: projectId,
            created_at: Date.now(),
            active: true
          }));
          
          console.log('Project and API key stored in KV successfully');
          
          // Try to store in DynamoDB via API Gateway
          try {
            console.log('Attempting to store in DynamoDB via API Gateway...');
            console.log('API Gateway URL:', `${env.API_GATEWAY_URL}/projects`);
            console.log('Project data being sent:', JSON.stringify(projectData));
            
            const response = await fetch(`${env.API_GATEWAY_URL}/projects`, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${env.INTERNAL_API_KEY}`,
                'Content-Type': 'application/json'
              },
              body: JSON.stringify(projectData)
            });
            
            console.log('API Gateway response status:', response.status);
            const responseText = await response.text();
            console.log('API Gateway response body:', responseText);
            
            if (response.ok) {
              console.log('Project stored in DynamoDB successfully');
            } else {
              console.log('API Gateway response not OK:', response.status);
            }
          } catch (apiError) {
            console.error('API Gateway error:', apiError);
          }
          
          return new Response(JSON.stringify({
            success: true,
            project_id: projectId,
            api_key: apiKey,
            endpoint: `https://${projectId}.apiblaze.com`,
            message: 'Project created and stored in KV successfully'
          }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        } catch (kvError) {
          console.error('KV storage error:', kvError);
          // Return success even if KV storage fails (graceful degradation)
          return new Response(JSON.stringify({
            success: true,
            project_id: projectId,
            api_key: apiKey,
            endpoint: `https://${projectId}.apiblaze.com`,
            message: 'Project created (KV storage failed, using fallback)',
            warning: 'Data not persisted to cache'
          }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        
        
      }
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Invalid request' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
  
  // Return CLI help
  return new Response(JSON.stringify({
    message: 'APIBLAZE CLI',
    usage: 'curl -X POST https://apiblaze.com --data \'{"target": "https://api.example.com"}\'',
    examples: [
      'Create API proxy: curl -X POST https://apiblaze.com --data \'{"target": "https://api.example.com"}\'',
      'Use API proxy: curl -H "X-API-Key: your_key" https://yourproject.apiblaze.com/endpoint'
    ]
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
};

const handleRedeployment = async (request, env) => {
  const url = new URL(request.url);
  const pathParts = url.pathname.split('/');
  const projectId = pathParts[2];
  const apiVersion = pathParts[3] || 'v1';
  
  if (request.method === 'POST') {
    try {
      const body = await request.json();
      
      // Clear project cache to force refresh
      await env.PROJECTS.delete(projectId);
      
      // Log redeployment
      console.log(`Redeployment triggered for project ${projectId} version ${apiVersion}`, {
        trigger: body.trigger,
        timestamp: Date.now()
      });
      
      return new Response(JSON.stringify({
        success: true,
        project_id: projectId,
        api_version: apiVersion,
        redeployed_at: Date.now()
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
      
    } catch (error) {
      console.error('Redeployment error:', error);
      return new Response(JSON.stringify({ error: 'Redeployment failed' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
  
  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { 'Content-Type': 'application/json' }
  });
};

// Main request handler
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const hostname = url.hostname;
    const path = url.pathname;
    
    try {
      // Route based on hostname and path
      if (hostname === 'apiblaze.com' || hostname === 'www.apiblaze.com' || hostname === 'apiblaze-worker.julien-529.workers.dev') {
        // Handle redeployment endpoint
        if (path.startsWith('/projects/') && path.includes('/redeploy')) {
          return await handleRedeployment(request, env);
        }
        
        return await handleCommandLineInterface(request, env);
      } else if (hostname.endsWith('.apiblaze.com') || hostname.endsWith('.workers.dev')) {
        return await handleApiRequest(request, env);
      } else {
        return new Response('Not found', { status: 404 });
      }
    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({ error: 'Internal server error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
}; 