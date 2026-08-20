export async function onRequest(context) {
    const { env, request } = context;
    const injectedToken = 'INJECT_TOKEN_HERE' !== 'INJECT_TOKEN_HERE' ? 'INJECT_TOKEN_HERE' : null;
    const ghToken = env.GITHUB_PAT || env.GH_TOKEN || env.HF_TOKEN || injectedToken;
    
    if (!ghToken) {
        return new Response("Missing GITHUB_PAT environment variable for private repo access.", { status: 501 });
    }

    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    // 1. Fetch the release by tag to get the asset ID
    const releaseUrl = 'https://api.github.com/repos/Iam-Muslim/ReciteQuran-ElhamduleAllah/releases/tags/models-latest';
    const apiHeaders = {
        'User-Agent': 'Cloudflare-Worker',
        'Authorization': `Bearer ${ghToken}`,
        'Accept': 'application/vnd.github.v3+json'
    };

    let releaseResponse = await fetch(releaseUrl, { headers: apiHeaders });
    if (!releaseResponse.ok) {
        return new Response(`Failed to fetch release info: ${releaseResponse.status}`, { status: releaseResponse.status });
    }

    const releaseData = await releaseResponse.json();
    const asset = releaseData.assets.find(a => a.name === modelParam);
    if (!asset) {
        return new Response(`Asset ${modelParam} not found in release models-latest.`, { status: 404 });
    }

    // 2. Fetch the asset using the GitHub API
    // We must handle redirects manually because passing the Authorization header to AWS S3 causes a signature mismatch error.
    const assetUrl = asset.url; // This is the API URL for the asset
    const binaryHeaders = new Headers();
    binaryHeaders.set('User-Agent', 'Cloudflare-Worker');
    binaryHeaders.set('Authorization', `Bearer ${ghToken}`);
    binaryHeaders.set('Accept', 'application/octet-stream');

    let fetchResponse = await fetch(assetUrl, { headers: binaryHeaders, redirect: 'manual' });
    
    // Check if GitHub returned JSON instead of the expected 302 Redirect
    if (fetchResponse.status === 200) {
        const contentType = fetchResponse.headers.get('content-type') || '';
        if (contentType.includes('application/json')) {
            const errText = await fetchResponse.text();
            return new Response(`GitHub API returned JSON! Accept header ignored? Response: ${errText}`, { status: 502 });
        }
        
        // Failsafe: if the response is 200 OK but it's not JSON, let's check if it's suspiciously small.
        const contentLength = fetchResponse.headers.get('content-length');
        if (contentLength && parseInt(contentLength, 10) < 5000) {
            const clone = fetchResponse.clone();
            const text = await clone.text();
            return new Response(`Proxy intercepted a small response from GitHub API. This is not the model! Contents: ${text}`, { status: 502 });
        }
    }

    if (fetchResponse.status >= 300 && fetchResponse.status < 400 && fetchResponse.headers.has('location')) {
        const redirectUrl = fetchResponse.headers.get('location');
        fetchResponse = await fetch(redirectUrl, {
            headers: { 'User-Agent': 'Cloudflare-Worker' } // No Auth header here!
        });
    }

    if (!fetchResponse.ok) {
        const errText = await fetchResponse.text();
        return new Response(`Upstream Error: ${fetchResponse.status} - ${errText}`, { status: fetchResponse.status });
    }

    const response = new Response(fetchResponse.body, fetchResponse);
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    
    return response;
}
