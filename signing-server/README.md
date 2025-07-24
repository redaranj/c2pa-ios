# C2PA Signing Server (Testing)

A Swift-based web service that provides certificate signing and C2PA manifest signing capabilities for testing purposes.

> **⚠️ Testing Only**: This server has no authentication and is intended for development and testing only. For production use, implement proper authentication and security measures.

## Features

- **Certificate Authority**: Built-in CA for signing Certificate Signing Requests (CSRs)
- **C2PA Manifest Signing**: Sign images with C2PA manifests using server-side certificates
- **Temporary Certificates**: Generate temporary certificates for testing
- **RESTful API**: Clean API design following REST principles
- **No Authentication**: Simplified for testing purposes

## API Endpoints

### Health & Status

#### Health Check
```
GET /health
```

#### Server Status
```
GET /
Response: {"status": "C2PA Signing Server is running", "version": "1.0.0", "mode": "testing"}
```

### Certificate Management

#### Sign Certificate Signing Request
```
POST /api/v1/certificates/csr
Content-Type: application/json

{
  "csr": "-----BEGIN CERTIFICATE REQUEST-----...",
  "metadata": {
    "deviceId": "optional-device-id",
    "appVersion": "1.0.0",
    "purpose": "content-signing"
  }
}
```

#### Get CA Certificates
```
GET /api/v1/certificates/ca
```

#### Get Certificate Info
```
GET /api/v1/certificates/{certificateId}
```

#### Revoke Certificate (No Auth Required)
```
DELETE /api/v1/certificates/{certificateId}
```

### C2PA Operations

#### Sign C2PA Manifest
```
POST /api/v1/c2pa/sign
Content-Type: multipart/form-data

Form fields:
- request: JSON with signing parameters
- image: Image file to sign

Request JSON structure:
{
  "manifestJSON": "{...}",
  "format": "image/jpeg"
}
```

#### Verify C2PA Manifest
```
POST /api/v1/c2pa/verify
Content-Type: multipart/form-data

Form fields:
- image: Image file to verify
- format: "image/jpeg"
```

## Quick Start

### Running the Server

From the project root directory:

1. Using the Makefile:
```bash
make server
```

2. Using Swift directly:
```bash
cd signing-server
swift run
```

The server will start on http://localhost:8080

### Other Commands

From the project root:
- `make setup-server` - Set up server dependencies
- `make clean-server` - Clean server build artifacts

## Testing Examples

### Test Certificate Signing
```bash
# Submit a CSR
curl -X POST http://localhost:8080/api/v1/certificates/csr \
  -H "Content-Type: application/json" \
  -d '{
    "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...\n-----END CERTIFICATE REQUEST-----",
    "metadata": {"deviceId": "test-device"}
  }'
```

### Test C2PA Signing with Temporary Certificate
```bash
# Sign an image with a temporary certificate
curl -X POST http://localhost:8080/api/v1/c2pa/sign \
  -F 'request={
    "manifestJSON":"{\"claim_generator\":\"Test/1.0\",\"title\":\"Test Image\"}",
    "format":"image/jpeg"
  }' \
  -F 'image=@test-image.jpg' \
  -o signed-image.jpg
```

### Test C2PA Verification
```bash
curl -X POST http://localhost:8080/api/v1/c2pa/verify \
  -F 'image=@signed-image.jpg' \
  -F 'format=image/jpeg'
```

### Get CA Certificates
```bash
curl http://localhost:8080/api/v1/certificates/ca
```


## Configuration

### Environment Variables

- `VAPOR_ENVIRONMENT`: Set to `production` or `development`
- `LOG_LEVEL`: Set logging level (debug, info, warning, error)
- `PORT`: Server port (default: 8080)

### Certificate Authority

The server automatically generates a test CA hierarchy on startup:
- Root CA (10-year validity)
- Intermediate CA (5-year validity)
- End-entity certificates (1-year validity)

## Integration with iOS App

The iOS app can use this server for testing certificate enrollment and signing:

```swift
// 1. Generate CSR on device
let csr = try CertificateManager.createCSRForWebService(
    keyTag: "secure-enclave-key",
    organization: "Your Company Name",
    organizationalUnit: "Content Authentication",
    country: "US",
    state: "CA",
    locality: "Your City"
)

// 2. Submit to test server (no auth required)
let request = URLRequest(url: URL(string: "http://localhost:8080/api/v1/certificates/csr")!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONEncoder().encode(["csr": csr])

let (data, _) = try await URLSession.shared.data(for: request)
let response = try JSONDecoder().decode(SignedCertificateResponse.self, from: data)

// 3. Use certificate for signing
let signer = try Signer(
    algorithm: .es256,
    certificateChainPEM: response.certificateChain,
    secureEnclaveConfig: config
)
```

## Adding Authentication for Production

While this test server has no authentication, the C2PA library supports adding authentication headers:

```swift
// Example: Adding Bearer token authentication
var request = URLRequest(url: URL(string: "https://production-server/api/v1/certificates/csr")!)
request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
```

For production deployment:
1. Implement proper authentication (OAuth2, API keys, etc.)
2. Use HTTPS with valid certificates
3. Add rate limiting and request validation
4. Store certificates in a database
5. Implement audit logging
6. Add monitoring and alerting

## License

This is part of the C2PA iOS project and follows the same licensing terms.