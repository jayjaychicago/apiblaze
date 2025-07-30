const AWS = require('aws-sdk');

// Configure AWS
AWS.config.update({ region: process.env.AWS_REGION });

// Utility functions
const logEvent = (message, data = {}) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    message,
    ...data
  }));
};

const updateCloudflareKV = async (namespace, key, value) => {
  try {
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/storage/kv/namespaces/${namespace}/values/${encodeURIComponent(key)}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(value)
    });

    if (!response.ok) {
      throw new Error(`Failed to update KV: ${response.statusText}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Error updating Cloudflare KV:', error);
    throw error;
  }
};

const invalidateCloudflareCache = async (projectId) => {
  try {
    // In production, this would invalidate the Cloudflare cache for the project
    // For now, we'll just log the invalidation
    logEvent('Cache invalidation requested', { project_id: projectId });
    
    // You could also trigger a Cloudflare Worker redeployment here
    // by calling the Cloudflare API to update the worker
    
    return true;
  } catch (error) {
    console.error('Error invalidating cache:', error);
    throw error;
  }
};

const getKVNamespaceId = async (namespaceName) => {
  try {
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/storage/kv/namespaces`, {
      headers: {
        'Authorization': `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to get KV namespaces: ${response.statusText}`);
    }

    const data = await response.json();
    const namespace = data.result.find(ns => ns.title === namespaceName);
    
    if (!namespace) {
      throw new Error(`KV namespace not found: ${namespaceName}`);
    }

    return namespace.id;
  } catch (error) {
    console.error('Error getting KV namespace ID:', error);
    throw error;
  }
};

const handleProjectUpdate = async (newImage, oldImage) => {
  const projectId = newImage.project_id;
  const apiVersion = newImage.api_version;
  
  logEvent('Processing project update', { 
    project_id: projectId, 
    api_version: apiVersion,
    event_type: oldImage ? 'UPDATE' : 'INSERT'
  });

  try {
    // Get KV namespace IDs
    const projectsNamespaceId = await getKVNamespaceId('PROJECTS');
    const apiKeysNamespaceId = await getKVNamespaceId('API_KEYS');
    const userAccessNamespaceId = await getKVNamespaceId('USER_ACCESS');

    // Update PROJECTS cache
    const projectConfig = {
      project_id: projectId,
      api_version: apiVersion,
      customer_id: newImage.customer_id,
      target_url: newImage.target_url,
      auth_type: newImage.auth_type,
      target_auth_type: newImage.target_auth_type,
      target_api_key: newImage.target_api_key,
      active: newImage.active,
      github_repo: newImage.github_repo,
      github_branch: newImage.github_branch,
      openapi_spec: newImage.openapi_spec,
      last_deployment: newImage.last_deployment,
      updated_at: newImage.updated_at
    };

    await updateCloudflareKV(projectsNamespaceId, projectId, projectConfig);
    logEvent('Updated PROJECTS cache', { project_id: projectId });

    // If auth type changed, we might need to update related caches
    if (oldImage && oldImage.auth_type !== newImage.auth_type) {
      logEvent('Auth type changed', { 
        project_id: projectId, 
        old_auth_type: oldImage.auth_type, 
        new_auth_type: newImage.auth_type 
      });
      
      // Clear related caches
      // This would clear API keys cache if switching from API key auth
      if (oldImage.auth_type === 'api_key' && newImage.auth_type !== 'api_key') {
        // Clear API keys cache for this project
        logEvent('Clearing API keys cache', { project_id: projectId });
      }
    }

    // If target URL changed, invalidate cache
    if (oldImage && oldImage.target_url !== newImage.target_url) {
      logEvent('Target URL changed', { 
        project_id: projectId, 
        old_url: oldImage.target_url, 
        new_url: newImage.target_url 
      });
      
      await invalidateCloudflareCache(projectId);
    }

    // If project was deactivated, clear caches
    if (oldImage && oldImage.active && !newImage.active) {
      logEvent('Project deactivated', { project_id: projectId });
      
      // Clear all caches for this project
      await updateCloudflareKV(projectsNamespaceId, projectId, null);
      await updateCloudflareKV(apiKeysNamespaceId, `*:${projectId}`, null);
      await updateCloudflareKV(userAccessNamespaceId, `*:${projectId}`, null);
    }

    logEvent('Project update processed successfully', { project_id: projectId });

  } catch (error) {
    console.error('Error handling project update:', error);
    throw error;
  }
};

const handleProjectDeletion = async (oldImage) => {
  const projectId = oldImage.project_id;
  
  logEvent('Processing project deletion', { project_id: projectId });

  try {
    // Get KV namespace IDs
    const projectsNamespaceId = await getKVNamespaceId('PROJECTS');
    const apiKeysNamespaceId = await getKVNamespaceId('API_KEYS');
    const userAccessNamespaceId = await getKVNamespaceId('USER_ACCESS');
    const oauthTokensNamespaceId = await getKVNamespaceId('OAUTH_TOKENS');

    // Clear all caches for this project
    await updateCloudflareKV(projectsNamespaceId, projectId, null);
    
    // Clear API keys cache (this would need to be done for all keys in production)
    await updateCloudflareKV(apiKeysNamespaceId, `*:${projectId}`, null);
    
    // Clear user access cache
    await updateCloudflareKV(userAccessNamespaceId, `*:${projectId}`, null);
    
    // Clear OAuth tokens cache
    await updateCloudflareKV(oauthTokensNamespaceId, `*:${projectId}`, null);

    // Invalidate Cloudflare cache
    await invalidateCloudflareCache(projectId);

    logEvent('Project deletion processed successfully', { project_id: projectId });

  } catch (error) {
    console.error('Error handling project deletion:', error);
    throw error;
  }
};

const handleUserAccessUpdate = async (newImage, oldImage) => {
  const userId = newImage.user_id;
  const projectId = newImage.project_id;
  
  logEvent('Processing user access update', { 
    user_id: userId, 
    project_id: projectId 
  });

  try {
    const userAccessNamespaceId = await getKVNamespaceId('USER_ACCESS');
    
    const accessData = {
      user_id: userId,
      project_id: projectId,
      customer_id: newImage.customer_id,
      has_access: newImage.has_access,
      access_level: newImage.access_level,
      updated_at: newImage.updated_at
    };

    await updateCloudflareKV(userAccessNamespaceId, `${userId}:${projectId}`, accessData);
    
    logEvent('User access update processed successfully', { 
      user_id: userId, 
      project_id: projectId 
    });

  } catch (error) {
    console.error('Error handling user access update:', error);
    throw error;
  }
};

const handleApiKeyUpdate = async (newImage, oldImage) => {
  const apiKeyHash = newImage.api_key_hash;
  const projectId = newImage.project_id;
  
  logEvent('Processing API key update', { 
    api_key_hash: apiKeyHash, 
    project_id: projectId 
  });

  try {
    const apiKeysNamespaceId = await getKVNamespaceId('API_KEYS');
    
    const keyData = {
      api_key_hash: apiKeyHash,
      project_id: projectId,
      user_id: newImage.user_id,
      name: newImage.name,
      active: newImage.active,
      expires_at: newImage.expires_at,
      updated_at: newImage.updated_at
    };

    await updateCloudflareKV(apiKeysNamespaceId, `${apiKeyHash}:${projectId}`, keyData);
    
    logEvent('API key update processed successfully', { 
      api_key_hash: apiKeyHash, 
      project_id: projectId 
    });

  } catch (error) {
    console.error('Error handling API key update:', error);
    throw error;
  }
};

// Main handler
exports.handler = async (event) => {
  logEvent('DynamoDB Stream event received', { 
    record_count: event.Records?.length || 0 
  });

  try {
    for (const record of event.Records) {
      const { eventName, dynamodb } = record;
      const { NewImage, OldImage } = dynamodb;
      
      // Parse the DynamoDB record
      const newImage = NewImage ? AWS.DynamoDB.Converter.unmarshall(NewImage) : null;
      const oldImage = OldImage ? AWS.DynamoDB.Converter.unmarshall(OldImage) : null;
      
      logEvent('Processing DynamoDB record', {
        event_name: eventName,
        table_name: record.eventSourceARN.split('/')[1],
        has_new_image: !!newImage,
        has_old_image: !!oldImage
      });

      // Route based on table name
      const tableName = record.eventSourceARN.split('/')[1];
      
      switch (tableName) {
        case 'apiblaze-projects':
          if (eventName === 'REMOVE') {
            await handleProjectDeletion(oldImage);
          } else {
            await handleProjectUpdate(newImage, oldImage);
          }
          break;
          
        case 'apiblaze-user-project-access':
          if (eventName !== 'REMOVE') {
            await handleUserAccessUpdate(newImage, oldImage);
          }
          break;
          
        case 'apiblaze-api-keys':
          if (eventName !== 'REMOVE') {
            await handleApiKeyUpdate(newImage, oldImage);
          }
          break;
          
        default:
          logEvent('Unhandled table', { table_name: tableName });
      }
    }

    logEvent('DynamoDB Stream processing completed successfully');

  } catch (error) {
    console.error('Error processing DynamoDB Stream:', error);
    throw error;
  }
}; 