const crypto = require('crypto');
const AWS = require('aws-sdk');

// Configure AWS
AWS.config.update({ region: process.env.AWS_REGION });
const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();

// Utility functions
const generateResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Hub-Signature-256',
    'Access-Control-Allow-Methods': 'POST,OPTIONS'
  },
  body: JSON.stringify(body)
});

const verifyGitHubSignature = (payload, signature, secret) => {
  if (!signature) return false;
  
  const expectedSignature = 'sha256=' + crypto
    .createHmac('sha256', secret)
    .update(payload)
    .digest('hex');
  
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
};

const fetchOpenAPISpec = async (url, token = null) => {
  try {
    const headers = {
      'User-Agent': 'APIBLAZE-GitHub-Webhook/1.0'
    };
    
    if (token) {
      headers['Authorization'] = `token ${token}`;
    }
    
    const response = await fetch(url, { headers });
    
    if (!response.ok) {
      throw new Error(`Failed to fetch OpenAPI spec: ${response.statusText}`);
    }
    
    return await response.text();
  } catch (error) {
    console.error('Error fetching OpenAPI spec:', error);
    throw error;
  }
};

const parseOpenAPISpec = (specContent) => {
  try {
    // Try to parse as JSON first
    return JSON.parse(specContent);
  } catch (error) {
    // If JSON fails, try YAML
    const yaml = require('js-yaml');
    return yaml.load(specContent);
  }
};

const extractProjectInfo = (openAPISpec) => {
  const info = openAPISpec.info || {};
  const servers = openAPISpec.servers || [];
  
  return {
    title: info.title || 'Unknown API',
    version: info.version || '1.0.0',
    description: info.description || '',
    base_url: servers[0]?.url || '',
    paths: Object.keys(openAPISpec.paths || {}).length,
    components: Object.keys(openAPISpec.components || {}).length
  };
};

const findProjectsByGitHubRepo = async (repoFullName, branch = 'main') => {
  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    FilterExpression: 'github_repo = :repo AND github_branch = :branch',
    ExpressionAttributeValues: {
      ':repo': repoFullName,
      ':branch': branch
    }
  };
  
  const result = await dynamodb.scan(params).promise();
  return result.Items;
};

const updateProjectSpec = async (projectId, apiVersion, specData) => {
  const params = {
    TableName: process.env.DYNAMODB_PROJECTS_TABLE,
    Key: {
      project_id: projectId,
      api_version: apiVersion
    },
    UpdateExpression: 'SET #spec = :spec, #spec_hash = :spec_hash, #updated_at = :updated_at, #last_deployment = :last_deployment',
    ExpressionAttributeNames: {
      '#spec': 'openapi_spec',
      '#spec_hash': 'openapi_spec_hash',
      '#updated_at': 'updated_at',
      '#last_deployment': 'last_deployment'
    },
    ExpressionAttributeValues: {
      ':spec': specData,
      ':spec_hash': crypto.createHash('sha256').update(JSON.stringify(specData)).digest('hex'),
      ':updated_at': Date.now(),
      ':last_deployment': Date.now()
    },
    ReturnValues: 'ALL_NEW'
  };
  
  const result = await dynamodb.update(params).promise();
  return result.Attributes;
};

const storeSpecInS3 = async (projectId, apiVersion, specContent) => {
  const key = `specs/${projectId}/${apiVersion}/openapi.yaml`;
  
  const params = {
    Bucket: process.env.DEPLOYMENT_ARTIFACTS_BUCKET,
    Key: key,
    Body: specContent,
    ContentType: 'application/x-yaml',
    Metadata: {
      'project-id': projectId,
      'api-version': apiVersion,
      'last-updated': new Date().toISOString()
    }
  };
  
  await s3.putObject(params).promise();
  return key;
};

const triggerCloudflareRedeployment = async (projectId, apiVersion) => {
  try {
    // In production, this would trigger a Cloudflare Worker redeployment
    // For now, we'll update the KV cache to reflect the changes
    const response = await fetch(`${process.env.API_GATEWAY_URL}/projects/${projectId}/redeploy`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.INTERNAL_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        project_id: projectId,
        api_version: apiVersion,
        trigger: 'github_webhook'
      })
    });
    
    if (!response.ok) {
      throw new Error(`Failed to trigger redeployment: ${response.statusText}`);
    }
    
    return await response.json();
  } catch (error) {
    console.error('Error triggering redeployment:', error);
    throw error;
  }
};

const processOpenAPISpecChange = async (repoFullName, branch, filePath, commitSha) => {
  try {
    // Find projects associated with this GitHub repo
    const projects = await findProjectsByGitHubRepo(repoFullName, branch);
    
    if (projects.length === 0) {
      console.log(`No projects found for repo: ${repoFullName} branch: ${branch}`);
      return { processed: 0, updated: 0 };
    }
    
    let processed = 0;
    let updated = 0;
    
    for (const project of projects) {
      processed++;
      
      try {
        // Fetch the updated OpenAPI spec from GitHub
        const rawUrl = `https://raw.githubusercontent.com/${repoFullName}/${branch}/${filePath}`;
        const specContent = await fetchOpenAPISpec(rawUrl);
        
        // Parse the spec
        const specData = parseOpenAPISpec(specContent);
        const projectInfo = extractProjectInfo(specData);
        
        // Store spec in S3
        const s3Key = await storeSpecInS3(project.project_id, project.api_version, specContent);
        
        // Update project in DynamoDB
        const updatedProject = await updateProjectSpec(
          project.project_id,
          project.api_version,
          {
            ...specData,
            s3_key: s3Key,
            github_commit: commitSha,
            project_info: projectInfo
          }
        );
        
        // Trigger Cloudflare redeployment
        await triggerCloudflareRedeployment(project.project_id, project.api_version);
        
        console.log(`Updated project ${project.project_id} with new spec from ${filePath}`);
        updated++;
        
      } catch (error) {
        console.error(`Error processing project ${project.project_id}:`, error);
      }
    }
    
    return { processed, updated };
    
  } catch (error) {
    console.error('Error processing OpenAPI spec change:', error);
    throw error;
  }
};

// Main handler
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  // Handle CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return generateResponse(200, {});
  }
  
  try {
    const headers = event.headers || {};
    const body = event.body;
    
    // Verify GitHub webhook signature
    const signature = headers['X-Hub-Signature-256'];
    const githubSecret = process.env.GITHUB_WEBHOOK_SECRET;
    
    if (!verifyGitHubSignature(body, signature, githubSecret)) {
      console.error('Invalid GitHub webhook signature');
      return generateResponse(401, { error: 'Invalid signature' });
    }
    
    // Parse GitHub event
    const githubEvent = JSON.parse(body);
    const eventType = headers['X-GitHub-Event'];
    
    console.log(`Received GitHub event: ${eventType}`);
    
    // Handle different event types
    switch (eventType) {
      case 'push':
        await handlePushEvent(githubEvent);
        break;
        
      case 'pull_request':
        await handlePullRequestEvent(githubEvent);
        break;
        
      case 'create':
        await handleCreateEvent(githubEvent);
        break;
        
      default:
        console.log(`Unhandled event type: ${eventType}`);
    }
    
    return generateResponse(200, { success: true });
    
  } catch (error) {
    console.error('GitHub webhook handler error:', error);
    return generateResponse(500, { error: 'Internal server error' });
  }
};

const handlePushEvent = async (event) => {
  const { repository, ref, commits } = event;
  const repoFullName = repository.full_name;
  const branch = ref.replace('refs/heads/', '');
  
  console.log(`Processing push event for ${repoFullName} branch ${branch}`);
  
  // Check if any OpenAPI specs were modified
  const openAPIFiles = [];
  
  for (const commit of commits) {
    for (const file of [...(commit.added || []), ...(commit.modified || [])]) {
      if (file.match(/\.(yaml|yml|json)$/) && 
          (file.includes('openapi') || file.includes('swagger') || file.includes('api'))) {
        openAPIFiles.push(file);
      }
    }
  }
  
  if (openAPIFiles.length === 0) {
    console.log('No OpenAPI files modified in this push');
    return;
  }
  
  // Process each modified OpenAPI file
  for (const filePath of openAPIFiles) {
    await processOpenAPISpecChange(repoFullName, branch, filePath, event.head_commit.id);
  }
};

const handlePullRequestEvent = async (event) => {
  const { action, pull_request, repository } = event;
  
  if (action !== 'opened' && action !== 'synchronize') {
    return; // Only process new PRs and updates
  }
  
  const repoFullName = repository.full_name;
  const branch = pull_request.head.ref;
  
  console.log(`Processing PR event for ${repoFullName} branch ${branch}`);
  
  // Check if PR contains OpenAPI spec changes
  const files = pull_request.files || [];
  const openAPIFiles = files.filter(file => 
    file.filename.match(/\.(yaml|yml|json)$/) && 
    (file.filename.includes('openapi') || file.filename.includes('swagger') || file.filename.includes('api'))
  );
  
  if (openAPIFiles.length === 0) {
    console.log('No OpenAPI files in this PR');
    return;
  }
  
  // Process each OpenAPI file in the PR
  for (const file of openAPIFiles) {
    await processOpenAPISpecChange(repoFullName, branch, file.filename, pull_request.head.sha);
  }
};

const handleCreateEvent = async (event) => {
  const { ref_type, ref, repository } = event;
  
  if (ref_type !== 'branch') {
    return; // Only process branch creation
  }
  
  const repoFullName = repository.full_name;
  const branch = ref;
  
  console.log(`Processing branch creation event for ${repoFullName} branch ${branch}`);
  
  // Check if the new branch contains OpenAPI specs
  // This would require additional API calls to GitHub to check the branch contents
  // For now, we'll just log the event
  console.log(`New branch ${branch} created in ${repoFullName}`);
}; 