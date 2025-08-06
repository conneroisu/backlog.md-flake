{ lib
, stdenv
, fetchurl
, nodejs
, backlog-md-npm
, writeShellScript
, jq
}:

stdenv.mkDerivation rec {
  pname = "backlog-md";
  version = "1.7.1";
  
  src = backlog-md-npm;
  
  buildInputs = [ nodejs jq ];
  
  # NPM package configuration
  npmConfigHook = writeShellScript "npm-config" ''
    # Configure NPM for reproducible builds
    npm config set cache /tmp/npm-cache
    npm config set fund false
    npm config set audit false
    npm config set update-notifier false
  '';
  
  unpackPhase = ''
    runHook preUnpack
    
    # Copy the source directory
    cp -r $src ./source
    chmod -R u+w ./source
    cd ./source
    
    runHook postUnpack
  '';
  
  configurePhase = ''
    runHook preConfigure
    
    # Ensure reproducible builds
    export HOME=/tmp/home
    mkdir -p $HOME
    
    # Set up NPM environment
    ${npmConfigHook}
    
    # Verify package integrity
    if [ -f package.json ]; then
      echo "Verifying package.json integrity..."
      ${jq}/bin/jq -e '.name == "backlog.md"' package.json
      ${jq}/bin/jq -e '.version == "${version}"' package.json
    fi
    
    runHook postConfigure
  '';
  
  buildPhase = ''
    runHook preBuild
    
    # No build steps needed for this package
    echo "Package ready for installation"
    
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/{bin,lib,share}
    
    # Install the main package
    cp -r . $out/lib/backlog-md/
    
    # Create executable wrapper - backlog.md has "backlog": "cli.js" in bin
    cat > $out/bin/backlog-md << 'EOF'
#!/usr/bin/env bash
exec ${nodejs}/bin/node $out/lib/backlog-md/cli.js "$@"
EOF
    chmod +x $out/bin/backlog-md
    
    # Also create the 'backlog' alias
    ln -s $out/bin/backlog-md $out/bin/backlog
    
    # Install documentation
    find . -name "*.md" -exec cp {} $out/share/ \; 2>/dev/null || true
    
    runHook postInstall
  '';
  
  # Package metadata
  meta = with lib; {
    description = "A powerful markdown-based backlog management tool";
    homepage = "https://www.npmjs.com/package/backlog.md";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
    
    # Auto-update metadata
    updateScript = writeShellScript "update-backlog-md" ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      PACKAGE_NAME="backlog.md"
      CURRENT_VERSION="${version}"
      
      echo "Checking for updates to $PACKAGE_NAME..."
      
      # Get latest version from NPM registry
      LATEST_VERSION=$(curl -s "https://registry.npmjs.org/$PACKAGE_NAME/latest" | ${jq}/bin/jq -r .version)
      
      if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
        echo "New version available: $LATEST_VERSION (current: $CURRENT_VERSION)"
        
        # Update the hash
        NEW_HASH=$(nix-prefetch-url "https://registry.npmjs.org/$PACKAGE_NAME/-/$PACKAGE_NAME-$LATEST_VERSION.tgz")
        
        # Update flake inputs
        sed -i "s|backlog.md-[0-9.]*.tgz|backlog.md-$LATEST_VERSION.tgz|g" ../flake.nix
        
        echo "Updated to version $LATEST_VERSION with hash $NEW_HASH"
      else
        echo "Already at latest version: $CURRENT_VERSION"
      fi
    '';
  };
  
  # Development utilities
  passthru = {
    inherit version;
    updateScript = meta.updateScript;
    
    # Provide access to the source for development
    npmSource = src;
    
    # Container image configuration
    containerConfig = {
      name = "backlog-md";
      tag = version;
      contents = [ nodejs ];
      cmd = [ "${placeholder "out"}/bin/backlog-md" ];
    };
  };
}