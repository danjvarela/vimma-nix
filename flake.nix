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

      # vimma-open is not in the tarball: upstream's packaging script emits it
      # into each distro package. Rather than vendor a copy that goes stale,
      # take it from the release's own PKGBUILD, pinned to the same version as
      # the tarball so the two can never disagree.
      pkgbuild = pkgs.fetchurl {
        url = "https://github.com/vimma-browser/vimma/releases/download/v${version}/PKGBUILD";
        # == sha256 from the release's SHA256SUMS:
        # 0f6a4174257e18b6bb5e4873d7a7df8fb23b0dd0d92e8a2e7ee5346762f2e7a8
        hash = "sha256-D2pBdCV+GLa7Xkhz16ffj7I7DdDZLooufuU0Z2Ly56g=";
      };

      # The script sits in a quoted heredoc, so the span between the
      # delimiters is already verbatim. The shebang check is the guard: if
      # upstream renames the heredoc the span comes out empty or wrong, and
      # the build fails here rather than at launch time.
      vimma-open-src = pkgs.runCommand "vimma-open-${version}.sh" { } ''
        sed -n "/<<'VIMMA_OPEN_EOF'/,/^VIMMA_OPEN_EOF$/p" ${pkgbuild} \
          | sed '1d;$d' > $out
        head -1 $out | grep -qx '#!/bin/sh'
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

      # The tarball ships no .desktop file; upstream's own packages generate
      # one. This mirrors the entry in the release's PKGBUILD.
      # StartupWMClass is the load-bearing field: Gecko sets WM_CLASS from
      # application.ini's RemotingName (vimma-vimma), and without the match a
      # launcher tracks the running browser as a second, iconless window.
      desktopEntry = pkgs.writeText "vimma.desktop" ''
        [Desktop Entry]
        Version=1.5
        Type=Application
        Name=Vimma
        GenericName=Web Browser
        Comment=Browse the web from the keyboard
        Exec=@out@/bin/vimma-open %u
        Icon=vimma
        Terminal=false
        StartupNotify=true
        StartupWMClass=vimma-vimma
        Categories=Network;WebBrowser;
        MimeType=application/json;application/pdf;application/rdf+xml;application/rss+xml;application/x-xpinstall;application/xhtml+xml;application/xml;audio/flac;audio/ogg;audio/webm;image/avif;image/gif;image/jpeg;image/png;image/svg+xml;image/webp;text/html;text/xml;video/ogg;video/webm;x-scheme-handler/http;x-scheme-handler/https;
        Keywords=Internet;WWW;Browser;Web;Explorer;vim;
        Actions=new-window;new-private-window;open-profile-manager;

        [Desktop Action new-window]
        Name=New Window
        Exec=@out@/bin/vimma --new-window %U

        [Desktop Action new-private-window]
        Name=New Private Window
        Exec=@out@/bin/vimma --private-window %U

        [Desktop Action open-profile-manager]
        Name=Open the Profile Manager
        Exec=@out@/bin/vimma --ProfileManager
      '';

      vimma = pkgs.buildFHSEnv {
        name = "vimma";
        targetPkgs = runtimeDeps;
        runScript = pkgs.writeShellScript "vimma-run" ''
          exec ${dist}/vimma "$@"
        '';

        # Exec points at the FHS wrapper, not the dist binary, so a launcher
        # starts the browser through the same sandbox the shell does.
        extraInstallCommands = ''
          # Installed beside bin/vimma on purpose: the script resolves the
          # browser as "the vimma next to this script", so sitting here makes
          # it find the FHS wrapper with no further wiring.
          install -Dm755 ${vimma-open-src} $out/bin/vimma-open

          install -d $out/share/applications
          substitute ${desktopEntry} $out/share/applications/vimma.desktop \
            --subst-var out

          for size in 16 32 48 64 128; do
            install -Dm644 \
              ${dist}/browser/chrome/icons/default/default$size.png \
              $out/share/icons/hicolor/''${size}x''${size}/apps/vimma.png
          done
        '';
      };

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
