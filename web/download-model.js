export async function onRequest(context) {
    const { request, env } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    const cache = caches.default;
    const cacheKey = new Request(urlObj.toString(), request);
    
    // 1. Check Cloudflare Edge CDN Cache first
    let cachedResponse = await cache.match(cacheKey);
    if (cachedResponse) {
        return cachedResponse;
    }
    
    // 2. Check for tokens in Cloudflare Environment
    const ghToken = env.GITHUB_PAT || env.GH_TOKEN;
    const hfToken = env.SUBHAN_ALLAH || env.HF_TOKEN || (('INJECT_TOKEN_HERE' !== 'INJECT_TOKEN_HERE') ? 'INJECT_TOKEN_HERE' : null);

    let targetUrl;
    const headers = { 
        'User-Agent': 'Cloudflare-Worker'
    };

    // If GITHUB_PAT is set, download from GitHub Release (models-latest)
    if (ghToken) {
        targetUrl = `https://github.com/Iam-Muslim/ReciteQuran-ElhamduleAllah/releases/download/models-latest/${modelParam}`;
        headers['Authorization'] = `Bearer ${ghToken}`;
        headers['Accept'] = 'application/octet-stream';
    } else {
        // Otherwise download from Hugging Face
        targetUrl = `https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3/resolve/main/${modelParam}`;
        headers['Accept'] = 'application/octet-stream';
        if (hfToken) {
            headers['Authorization'] = `Bearer ${hfToken}`;
        }
    }

    try {
        // Fetch with manual redirect handling to safely handle GitHub S3 redirects
        let fetchResponse = await fetch(targetUrl, { 
            headers, 
            redirect: 'manual' 
        });
        
        // Handle GitHub / HuggingFace redirect (e.g. 302 Found to AWS S3 / CloudFront)
        if (fetchResponse.status >= 300 && fetchResponse.status < 400 && fetchResponse.headers.has('location')) {
            const redirectUrl = fetchResponse.headers.get('location');
            // When following AWS S3 pre-signed URL, omit the Authorization header
            fetchResponse = await fetch(redirectUrl, {
                headers: { 'User-Agent': 'Cloudflare-Worker' }
            });
        }
        
        // If upstream returned an error (e.g. 401 / 404), return it without caching
        if (!fetchResponse.ok) {
            const errText = await fetchResponse.text();
            return new Response(`Upstream Error ${fetchResponse.status} from ${targetUrl}: ${errText}`, {
                status: fetchResponse.status,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'text/plain'
                }
            });
        }
        
        // Valid model stream: set CORS and Edge caching for 1 year
        const response = new Response(fetchResponse.body, fetchResponse);
        response.headers.set('Access-Control-Allow-Origin', '*');
        response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
        response.headers.set('Cache-Control', 'public, s-maxage=31536000, max-age=31536000, immutable');
        
        // Cache valid model on Cloudflare Edge CDN in background
        context.waitUntil(cache.put(cacheKey, response.clone()));
        
        return response;
    } catch (err) {
        return new Response(`Proxy Fetch Error: ${err.message}`, {
            status: 502,
            headers: { 'Access-Control-Allow-Origin': '*' }
        });
    }
}
