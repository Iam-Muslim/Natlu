export async function onRequest(context) {
    const { request } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    // Direct public GitHub release asset download URL from Natlu repository
    const directUrl = `https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/${modelParam}`;
    
    try {
        const fetchResponse = await fetch(directUrl, {
            headers: {
                'User-Agent': 'Cloudflare-Worker'
            }
        });

        if (!fetchResponse.ok) {
            return new Response(`Failed to fetch model from GitHub release: ${fetchResponse.status} ${fetchResponse.statusText}`, { 
                status: fetchResponse.status 
            });
        }

        const response = new Response(fetchResponse.body, fetchResponse);
        response.headers.set('Access-Control-Allow-Origin', '*');
        response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
        response.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
        
        return response;
    } catch (err) {
        return new Response(`Proxy Error: ${err.message}`, { status: 500 });
    }
}
