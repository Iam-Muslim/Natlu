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
    
    // 2. Determine Token (from Cloudflare Environment Variable or CI build injection)
    const token = env.SUBHAN_ALLAH || env.HF_TOKEN || 'INJECT_TOKEN_HERE';
    
    const targetUrl = `https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3/resolve/main/${modelParam}`;
    const headers = { 
        'User-Agent': 'Cloudflare-Worker',
        'Accept': 'application/octet-stream'
    };
    
    if (token && token !== 'INJECT_TOKEN_HERE') {
        headers['Authorization'] = `Bearer ${token}`;
    }

    try {
        const fetchResponse = await fetch(targetUrl, { 
            headers,
            redirect: 'follow'
        });
        
        // If HF returned an error (e.g. 401 / 404), return the error status directly and DO NOT cache
        if (!fetchResponse.ok) {
            const errBody = await fetchResponse.text();
            return new Response(`HF Error ${fetchResponse.status}: ${errBody}`, {
                status: fetchResponse.status,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Content-Type': 'text/plain'
                }
            });
        }
        
        // Valid model stream: set CORS and Edge caching
        const response = new Response(fetchResponse.body, fetchResponse);
        response.headers.set('Access-Control-Allow-Origin', '*');
        response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
        response.headers.set('Cache-Control', 'public, s-maxage=31536000, max-age=31536000, immutable');
        
        // Cache valid model on Cloudflare Edge CDN
        context.waitUntil(cache.put(cacheKey, response.clone()));
        
        return response;
    } catch (err) {
        return new Response(`Proxy Fetch Error: ${err.message}`, {
            status: 502,
            headers: { 'Access-Control-Allow-Origin': '*' }
        });
    }
}
