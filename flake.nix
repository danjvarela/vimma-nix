{
  description = "Vimma, the keyboard-driven Firefox fork, packaged from its upstream release tarball";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      version = "0.1.25"; # Vimma 0.1.25 - Firefox 161.0

      src = pkgs.fetchurl {
        url = "https://github.com/vimma-browser/vimma/releases/download/v${version}/vimma-${version}-linux-x86_64.tar.xz";
        # == sha256 from the release's SHA256SUMS:
        # 7b7d6edc2fd68e4bbcd777f9a81e72fb0ddcc15f2111e384714edaddac897647
        hash = "sha256-e31u3C/Wjku813f5qB5y+w3cwV8hEeOEcU7a3ayJdkc=";
      };

      dist = pkgs.runCommand "vimma-dist-${version}" { } ''
        mkdir -p $out
        tar -xf ${src} -C $out --strip-components=1
      '';

      # Firefox-ish runtime closure. The tarball is a stock Gecko dist dir, so
      # rather than patchelf'ing ~15 .so files we just hand it an FHS sandbox.
      runtimeDeps = p: with p; [
        alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus dbus-glib expat
        ffmpeg fontconfig freetype gdk-pixbuf glib gtk3 libdrm libGL libglvnd
        libnotify libpulseaudio libva libxkbcommon mesa nspr nss pango
        pciutils pipewire wayland zlib
        libkrb5 systemd
        libx11 libxscrnsaver libxcomposite libxcursor
        libxdamage libxext libxfixes libxi libxrandr
        libxrender libxtst libxcb
        # fonts/icons so pages and chrome don't render as tofu.
        # The Stylix set (modules/features/stylix.nix) is here too, because the
        # FHS sandbox builds its own fontconfig and won't see the host's fonts.
        dejavu_fonts liberation_ttf noto-fonts noto-fonts-color-emoji
        nerd-fonts.comic-shanns-mono
        hicolor-icon-theme adwaita-icon-theme gruvbox-plus-icons
      ];

      mkFhs = name: exe: pkgs.buildFHSEnv {
        inherit name;
        targetPkgs = runtimeDeps;
        runScript = pkgs.writeShellScript "${name}-run" ''
          exec ${dist}/${exe} "$@"
        '';
      };

      vimma = mkFhs "vimma" "vimma";

      # vimma-ctl is a static musl binary, no sandbox needed.
      vimma-ctl = pkgs.runCommand "vimma-ctl-${version}" { } ''
        mkdir -p $out/bin
        ln -s ${dist}/vimma-ctl $out/bin/vimma-ctl
      '';
      # Home-manager module: `vimma`, `vimma-ctl` on PATH, and (opt-in) PWA
      # support via firefoxpwa. Vimma's libxul.so hardcodes the unbranded
      # "~/.mozilla" path for native messaging hosts (confirmed by grepping
      # the tarball: "/usr/lib/mozilla", bare ".mozilla" — not vendor-scoped,
      # same lookup Firefox/Thunderbird/Librewolf share), and home-manager's
      # own mozilla-messaging-hosts.nix already symlinks into exactly that
      # directory from the internal `mozilla.firefoxNativeMessagingHosts`
      # list — so setting that list wires PWAs into Vimma (and real Firefox,
      # if also enabled) with no Vimma-specific plumbing needed.
      #
      # Not covered: the actual PWAsForFirefox WebExtension has to go into
      # Vimma's profile some other way (about:addons, by hand) -- there's no
      # home-manager target for Vimma's own profile tree the way there is
      # `programs.firefox.profiles.<name>.extensions` for real Firefox.
      homeModule =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.vimma;
        in
        {
          options.programs.vimma = {
            enable = lib.mkEnableOption "the Vimma browser";
            package = lib.mkOption {
              type = lib.types.package;
              default = vimma;
              description = "The Vimma package (the FHS-wrapped binary) to install.";
            };
            firefoxpwa.enable = lib.mkEnableOption ''
              PWAsForFirefox native-messaging-host wiring for Vimma, via
              `mozilla.firefoxNativeMessagingHosts` (~/.mozilla/native-messaging-hosts).
              Still requires installing the PWAsForFirefox extension into Vimma by hand.
            '';
          };

          config = lib.mkIf cfg.enable (lib.mkMerge [
            {
              home.packages = [ cfg.package vimma-ctl ];
            }
            (lib.mkIf cfg.firefoxpwa.enable {
              home.packages = [ pkgs.firefoxpwa ];
              mozilla.firefoxNativeMessagingHosts = [ pkgs.firefoxpwa ];
            })
          ]);
        };
    in
    {
      packages.${system} = {
        default = vimma;
        inherit vimma vimma-ctl dist;
      };

      apps.${system} = {
        default = { type = "app"; program = "${vimma}/bin/vimma"; };
        vimma-ctl = { type = "app"; program = "${vimma-ctl}/bin/vimma-ctl"; };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ vimma vimma-ctl ];
      };

      homeManagerModules.default = homeModule;
      homeModules.default = homeModule; # newer home-manager alias
    };
}
