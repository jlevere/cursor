{
  description = "Cursor - The AI Code Editor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Load versions from JSON file
      versionsData = builtins.fromJSON (builtins.readFile ./versions.json);
      
      # Get version info (default to latest)
      getVersionInfo = versionNum: 
        let
          version = if versionNum == null then versionsData.latest else versionNum;
          versionData = builtins.head (builtins.filter (v: v.version == version) versionsData.versions);
        in versionData;
      
      # Build Cursor from AppImage
      buildCursor = pkgs: { version, url, sha256 }: 
        let
          src = pkgs.fetchurl { inherit url sha256; };
          
          contents = pkgs.appimageTools.extract {
            inherit version src;
            pname = "cursor";
          };
        in
        pkgs.appimageTools.wrapType2 {
          inherit version src;
          pname = "cursor";
          
          # appimageTools.wrapType2 already includes most libraries via defaultFhsEnvArgs
          # Only add extras if needed for specific functionality
          extraPkgs = pkgs: [ ];
          
          extraInstallCommands = ''
            # Desktop file
            install -Dm644 ${contents}/cursor.desktop $out/share/applications/cursor.desktop
            substituteInPlace $out/share/applications/cursor.desktop \
              --replace-fail 'Exec=cursor' 'Exec=${placeholder "out"}/bin/cursor' \
              --replace-fail 'Icon=co.anysphere.cursor' 'Icon=cursor'
            
            # Icons
            for size in 22 24 32 48 64 128 256 512; do
              install -Dm644 ${contents}/usr/share/icons/hicolor/''${size}x''${size}/apps/cursor.png \
                $out/share/icons/hicolor/''${size}x''${size}/apps/cursor.png
            done
            
            # Pixmap
            install -Dm644 ${contents}/usr/share/pixmaps/co.anysphere.cursor.png \
              $out/share/pixmaps/cursor.png
          '';
          
          meta = with pkgs.lib; {
            description = "AI-powered code editor built on VSCode";
            homepage = "https://cursor.com";
            changelog = "https://cursor.com/changelog";
            license = licenses.unfree;
            sourceProvenance = with sourceTypes; [ binaryNativeCode ];
            maintainers = [ ];
            mainProgram = "cursor";
            platforms = [ "x86_64-linux" "aarch64-linux" ];
            # Note: macOS .dmg packaging not supported, Linux AppImage only
          };
        };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        latestVersionInfo = getVersionInfo null;
      in
      {
        packages = {
          default = self.packages.${system}.cursor;
          
          cursor = buildCursor pkgs {
            version = latestVersionInfo.version;
            url = latestVersionInfo.url;
            sha256 = latestVersionInfo.sha256;
          };
        };
        
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.cursor}/bin/cursor";
        };
        
        # Expose update script
        apps.update = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-cursor" ''
            exec ${./update.sh}
          '');
        };
      }
    ) // {
      # Helper to build specific versions
      lib.buildVersion = system: versionNum: 
        let 
          pkgs = import nixpkgs { inherit system; };
          versionInfo = getVersionInfo versionNum;
        in buildCursor pkgs {
          version = versionInfo.version;
          url = versionInfo.url;
          sha256 = versionInfo.sha256;
        };

      # Overlay
      overlays.default = final: prev: {
        cursor = self.packages.${prev.system}.cursor;
      };
    };
}
