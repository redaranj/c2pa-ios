# Signing Server Setup for Remote Testing

## Quick Setup

### 1. Start the Signing Server
```bash
cd ../signing-server
make run
```

### 2. Expose via Tailscale (for testing on physical devices)
```bash
tailscale serve --bg --https 8081 http://localhost:8080
```

This will make your signing server available at a URL like:
`https://your-machine-name.your-tailnet.ts.net:8081/`

**Note:** Tailscale automatically provides HTTPS with valid certificates, which is required by iOS App Transport Security.

### 3. Update the Configuration

Edit `C2PAExample/Configuration.swift` and update the `signingServerBaseURL`:

```swift
// For local testing (simulator only)
static let signingServerBaseURL = "http://127.0.0.1:8080"

// For Tailscale testing (physical devices on same tailnet) - HTTPS required!
static let signingServerBaseURL = "https://your-machine-name.your-tailnet.ts.net:8081"
```

### 4. Run Tests on Physical Device

1. Connect your iPhone/iPad to your Mac
2. Select your device as the build target in Xcode
3. Run the app and execute tests

## Troubleshooting

### Check Tailscale Status
```bash
tailscale serve status
```

### Disable Tailscale Serve
```bash
tailscale serve --https=8081 off
```

### Test Server Connectivity
```bash
# From your Mac
curl http://localhost:8080/health

# From another device on your tailnet
curl https://your-machine-name.your-tailnet.ts.net:8081/health
```

## Security Note

The signing server uses test certificates and is intended for development only. Do not expose it to the public internet.