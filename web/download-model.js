export async function onRequest(context) {
    const { request } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    const directUrl = `https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/${modelParam}`;
    
    // Fetch directly from github releases.
    // GitHub releases stream their response, and passing the body to new Response() streams it to the client.
    const fetchResponse = await fetch(directUrl, {
        headers: {
            'User-Agent': 'Cloudflare-Worker'
        }
    });

    const response = new Response(fetchResponse.body, fetchResponse);
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    // Important: Prevent Cloudflare from caching the model
    response.headers.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    
    return response;
}
