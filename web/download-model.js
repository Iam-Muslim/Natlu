export async function onRequest(context) {
    const { request } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    const cache = caches.default;
    // Cloudflare requires the cache key to be a Request object with a valid HTTP URL
    const cacheKey = new Request(urlObj.toString(), request);
    
    // Check if Cloudflare's Edge CDN already has the model cached
    let cachedResponse = await cache.match(cacheKey);
    if (cachedResponse) {
        return cachedResponse;
    }
    
    // If not cached, fetch it from Hugging Face using your token
    const targetUrl = `https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3/resolve/main/${modelParam}`;
    const headers = { 
        'User-Agent': 'Cloudflare-Worker',
        'Accept': 'application/octet-stream',
        'Authorization': `Bearer INJECT_TOKEN_HERE`
    };

    const fetchResponse = await fetch(targetUrl, { headers });
    
    let finalResponse;
    if (fetchResponse.status >= 300 && fetchResponse.status < 400 && fetchResponse.headers.has('location')) {
        const redirectUrl = fetchResponse.headers.get('location');
        finalResponse = await fetch(redirectUrl); 
    } else {
        finalResponse = fetchResponse;
    }
    
    // Create a new response to modify headers
    const response = new Response(finalResponse.body, finalResponse);
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    // Instruct Cloudflare CDN to cache this file for 1 year
    response.headers.set('Cache-Control', 'public, s-maxage=31536000, max-age=31536000, immutable');
    
    // Save to Cloudflare's global edge cache in the background!
    context.waitUntil(cache.put(cacheKey, response.clone()));
    
    return response;
}
