import Vapor

struct C2PAController {
    
    // POST /api/v1/c2pa/sign
    func signManifest(req: Request) async throws -> Response {
        // Check content type for multipart
        guard let contentType = req.headers.contentType,
              contentType.type == "multipart",
              contentType.subType == "form-data" else {
            throw Abort(.badRequest, reason: "Content-Type must be multipart/form-data")
        }
        
        // Decode multipart data
        let data = try req.content.decode(C2PASignMultipart.self)
        
        guard let imageData = data.image.data.getData(at: 0, length: data.image.data.readableBytes) else {
            throw Abort(.badRequest, reason: "Failed to read image data")
        }
        
        // Parse signing request from JSON field
        let signingRequest = try JSONDecoder().decode(
            C2PASigningRequest.self,
            from: data.request.data
        )
        
        // Sign the manifest
        let response = try await req.application.c2paService.signManifest(
            manifestJSON: signingRequest.manifestJSON,
            imageData: imageData,
            format: signingRequest.format
        )
        
        // Return the signed image with manifest embedded
        let res = Response(status: .ok)
        res.headers.contentType = HTTPMediaType(type: contentType.type, subType: contentType.subType)
        res.body = .init(data: response.manifestStore)
        return res
    }
}

// MARK: - Multipart Models

struct C2PASignMultipart: Content {
    var request: File  // JSON with signing parameters
    var image: File    // Image data to sign
}

