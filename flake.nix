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
      
      # Build Cursor from AppImage using vscode-generic (like nixpkgs)
      # This avoids FHS sandboxing issues (no_new_privs) and properly handles native modules
      buildCursor = pkgs: { version, url, sha256 }: 
        let
          src = pkgs.fetchurl { inherit url sha256; };
          
          extracted = pkgs.appimageTools.extract {
            inherit version src;
            pname = "cursor";
          };
        in
        pkgs.callPackage "${pkgs.path}/pkgs/applications/editors/vscode/generic.nix" rec {
          inherit version;
          pname = "cursor";
          executableName = "cursor";
          longName = "Cursor";
          shortName = "cursor";
          
          # Extract VSCode version from product.json if available, or use a reasonable default
          vscodeVersion = "1.96.2";
          
          src = extracted;
          sourceRoot = "usr/share/cursor";
          
          commandLineArgs = "--update=false";
          useVSCodeRipgrep = false;
          
          # We manage updates via our own update.sh script
          updateScript = null;
          
          meta = with pkgs.lib; {
            description = "AI-powered code editor built on VSCode";
            homepage = "https://cursor.com";
            changelog = "https://cursor.com/changelog";
            sourceProvenance = with sourceTypes; [ binaryNativeCode ];
            maintainers = [ ];
            mainProgram = "cursor";
            platforms = [ "x86_64-linux" "aarch64-linux" ];
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
