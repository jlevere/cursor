# cursor-nix

Nix flake for [Cursor](https://cursor.com) - tracks latest releases automatically.

**Linux only** (x86_64, aarch64) - wraps official AppImage releases.

## Install

```bash
nix profile install github:you/cursor-nix
```

## Run

```bash
nix run github:you/cursor-nix
```

## Use in Configuration

### Flake (Latest)

```nix
{
  inputs.cursor.url = "github:you/cursor-nix";
  
  outputs = { cursor, ... }: {
    environment.systemPackages = [ cursor.packages.x86_64-linux.cursor ];
  };
}
```

### Pin to Specific Version

```nix
{
  inputs.cursor.url = "github:you/cursor-nix";
  
  outputs = { cursor, nixpkgs, ... }: {
    environment.systemPackages = [
      (cursor.lib.buildVersion "x86_64-linux" "1.7.52")
    ];
  };
}
```

### Overlay

```nix
nixpkgs.overlays = [ inputs.cursor.overlays.default ];
```

## Update

Automatically updates every 6 hours via GitHub Actions. New versions are added to `versions.json`, old versions are kept for pinning.

Manual: `./update.sh`

List versions: `jq '.versions[].version' versions.json`

## API

Uses `https://api2.cursor.sh/updates/api/download/stable/linux-x64/cursor`


