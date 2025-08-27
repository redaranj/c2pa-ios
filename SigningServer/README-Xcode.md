# Running SigningServer from Xcode

The SigningServer Xcode scheme has been configured to allow you to run the server directly from Xcode using the Run button.

## Features

- **Automatic library download**: The scheme includes a pre-build action that automatically downloads the required macOS C2PA libraries
- **Proper environment setup**: DYLD_LIBRARY_PATH is configured to find the C2PA libraries
- **Correct working directory**: The working directory is set to the SigningServer folder
- **Debug configuration**: The server runs with debug logging enabled

## How to Run

1. Open `C2PA.xcworkspace` in Xcode
2. Select the `SigningServer` scheme from the scheme selector
3. Click the Run button (▶️) or press Cmd+R

The server will:
- Download C2PA libraries if needed (first run only)
- Build the SigningServer executable
- Start the server on http://localhost:8080

## Troubleshooting

If the server fails to start:

1. Check that the libraries were downloaded:
   ```bash
   ls SigningServer/libs/
   ```
   You should see `libc2pa_c.dylib`

2. Verify the server runs from command line:
   ```bash
   make signing-server
   make run-signing-server
   ```

3. Clean and rebuild:
   - Product → Clean Build Folder (Cmd+Shift+K)
   - Build again (Cmd+B)

## Server Endpoints

Once running, the server provides:
- `GET /` - Server status and version info
- `POST /sign` - Sign C2PA manifests

## Configuration

The server uses test certificates from the `SigningServer/Resources/` directory for signing operations.