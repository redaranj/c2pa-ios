#!/usr/bin/env ruby

require 'xcodeproj'
require 'securerandom'

# Open the SigningServer project
project_path = '../SigningServer/SigningServer.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if C2PAC target already exists
existing_target = project.targets.find { |t| t.name == 'C2PAC' }
if existing_target
  puts "C2PAC target already exists, removing it first..."
  project.targets.delete(existing_target)
end

# Create new C2PAC framework target for macOS
c2pac_target = project.new_target(:framework, 'C2PAC', :osx, '11.0')
c2pac_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'C2PAC'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['DYLIB_INSTALL_NAME_BASE'] = '@rpath'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'macosx'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
  
  # Important: This is a framework that contains a dynamic library
  config.build_settings['MACH_O_TYPE'] = 'mh_dylib'
  
  # Generate Info.plist automatically
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CODE_SIGN_IDENTITY'] = '-'
end

# Add build phase for downloading C2PA libraries
download_phase = c2pac_target.new_shell_script_build_phase('Download and Setup C2PA Libraries for macOS')
download_phase.shell_script = <<-SCRIPT
#!/bin/bash
set -e

echo "C2PAC Framework Builder for macOS"
echo "================================="

# Use configuration values from Base.xcconfig
GITHUB_ORG="${GITHUB_ORG:-contentauth}"
C2PA_VERSION="${C2PA_VERSION:-v0.58.0}"

echo "Version: ${C2PA_VERSION}"
echo "GitHub Org: ${GITHUB_ORG}"
echo "Platform: macOS"
echo "Target Build Dir: ${TARGET_BUILD_DIR}"

# Setup directories
FRAMEWORK_DIR="${TARGET_BUILD_DIR}/${PRODUCT_NAME}.framework"
DOWNLOAD_DIR="${TEMP_DIR}/C2PAC-Downloads"
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${FRAMEWORK_DIR}"

# Download macOS universal binary
echo "Downloading macOS universal library..."
curl -sL "https://github.com/${GITHUB_ORG}/c2pa-rs/releases/download/c2pa-${C2PA_VERSION}/c2pa-${C2PA_VERSION}-universal-apple-darwin.zip" \\
    -o "${DOWNLOAD_DIR}/macos-universal.zip"

mkdir -p "${DOWNLOAD_DIR}/macos-universal"
cd "${DOWNLOAD_DIR}/macos-universal"
unzip -q -o "${DOWNLOAD_DIR}/macos-universal.zip"

# Copy the dynamic library as the framework binary
cp "${DOWNLOAD_DIR}/macos-universal/lib/libc2pa_c.dylib" "${FRAMEWORK_DIR}/C2PAC"

# Copy and patch header
mkdir -p "${FRAMEWORK_DIR}/Headers"
sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \\
    "${DOWNLOAD_DIR}/macos-universal/include/c2pa.h" > "${FRAMEWORK_DIR}/Headers/c2pa.h"

# Create module map
mkdir -p "${FRAMEWORK_DIR}/Modules"
cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" << EOF
framework module C2PAC {
    header "c2pa.h"
    export *
}
EOF

# Create Info.plist
cat > "${FRAMEWORK_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>org.contentauth.C2PAC</string>
    <key>CFBundleName</key>
    <string>C2PAC</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
</dict>
</plist>
PLIST

# Create stamp file for build system
touch "${FRAMEWORK_DIR}/.stamp"

echo "✓ C2PAC framework built successfully at ${FRAMEWORK_DIR}"
SCRIPT

download_phase.output_paths = ['$(TARGET_BUILD_DIR)/$(PRODUCT_NAME).framework/.stamp']
download_phase.always_out_of_date = '1'

# Make SigningServer depend on C2PAC
signing_server_target = project.targets.find { |t| t.name == 'SigningServer' }
if signing_server_target
  # Remove the old "Download C2PA Libraries" phase from SigningServer
  old_phase = signing_server_target.build_phases.find { |p| p.display_name == 'Download C2PA Libraries' }
  if old_phase
    signing_server_target.build_phases.delete(old_phase)
  end
  
  # Remove any existing C2PAC references in frameworks phase
  frameworks_phase = signing_server_target.frameworks_build_phase
  frameworks_phase.files.delete_if { |f| f.display_name == 'C2PAC.framework' }
  
  # Add dependency
  signing_server_target.add_dependency(c2pac_target)
  
  # Add C2PAC framework to SigningServer's frameworks build phase
  framework_ref = c2pac_target.product_reference
  frameworks_phase.add_file_reference(framework_ref)
  
  puts "✓ Added C2PAC dependency to SigningServer target"
else
  puts "⚠️  SigningServer target not found"
end

# Save the project
project.save
puts "✓ Project saved successfully"