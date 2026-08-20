export async function onRequest(context) {
    const { request } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    const directUrl = `https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/${modelParam}`;
    
    // Fetch directly from github releases.
    const fetchResponse = await fetch(directUrl, {
        headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        }
    });

    const headers = new Headers();
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    headers.set('Access-Control-Allow-Headers', '*');
    headers.set('Content-Type', 'application/octet-stream');
    
    const contentLength = fetchResponse.headers.get('content-length');
    if (contentLength) {
        headers.set('Content-Length', contentLength);
    }
    
    // Enforce no-caching on Cloudflare
    headers.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');

    return new Response(fetchResponse.body, {
        status: fetchResponse.status,
        headers: headers
    });
}
