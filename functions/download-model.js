export async function onRequest(context) {
    const { request } = context;
    const urlObj = new URL(request.url);
    const modelParam = urlObj.searchParams.get('model') || 'zipformer_p_arabic_v3.int8.onnx';
    
    // Redirect browser directly to the public GitHub release download URL to avoid worker proxy throttling
    const directUrl = `https://github.com/Iam-Muslim/Natlu/releases/download/models-latest/${modelParam}`;
    return Response.redirect(directUrl, 302);
}
