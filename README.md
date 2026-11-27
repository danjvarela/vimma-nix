# vimma-nix

[Vimma](https://vimma.dev) packaged for Nix — a keyboard-driven Firefox fork
with tmux-style panes and workspaces.

Upstream ships distro packages (Arch/Debian/Fedora/openSUSE), a macOS cask and
a ~35 GB source build, none of which suit NixOS. This flake takes the generic
`linux-x86_64` release tarball instead.

## Use

```sh
nix run github:danjvarela/vimma-nix          # the browser
nix run github:danjvarela/vimma-nix#vimma-ctl -- --help
```

As a home-manager module:

```nix
# flake.nix
inputs.vimma-nix = {
  url = "github:danjvarela/vimma-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# home-manager config
imports = [ inputs.vimma-nix.homeModules.default ];

programs.vimma = {
  enable = true;
  firefoxpwa.enable = true;  # optional, see below
};
```

`nixpkgs.follows` matters more than usual here: the module's default package is
built from this flake's own nixpkgs, so without it you pull a second nixpkgs
evaluation and a duplicate store closure for the FHS dependencies.

## How it is built

The tarball is a stock Gecko dist dir — `libxul.so`, `omni.ja`, a `vimma`
launcher and ~15 bundled `.so` files, all dynamically linked against an FHS
layout that NixOS does not have.

Rather than patchelf every library, the launcher runs inside a
`buildFHSEnv` (bubblewrap) sandbox carrying the Firefox runtime closure. This
keeps the whole thing self-contained in the flake, with nothing to configure
system-wide. `nix-ld` is the alternative if you ever hit something the sandbox
cannot pass through, at the cost of a standing system-level change.

`vimma-ctl` is a statically linked musl binary, so it skips the sandbox
entirely and is symlinked straight out of the dist dir.

The FHS environment also carries its own fonts: it builds a private
fontconfig and cannot see the host's, so a font named in `config.toml` has to
be in `runtimeDeps` or it silently falls back.

## PWAs

`programs.vimma.firefoxpwa.enable` wires
[PWAsForFirefox](https://github.com/filips123/PWAsForFirefox) in via
home-manager's `mozilla.firefoxNativeMessagingHosts`.

This works because Vimma's `libxul.so` hardcodes the **unbranded**
`~/.mozilla/native-messaging-hosts` path for native messaging host lookup —
the same directory Firefox, Thunderbird and other Gecko forks share — rather
than anything under its own `~/.config/vimma` profile tree. So the existing
home-manager plumbing reaches Vimma with no Vimma-specific wiring.

**Not automated:** the PWAsForFirefox *extension* still has to be installed
into Vimma by hand from `about:addons`. There is no home-manager target for
Vimma's profile tree the way `programs.firefox.profiles.<name>.extensions`
exists for Firefox.

## Theming

Theming is **not** managed by this flake, deliberately: Vimma live-reloads
`~/.config/vimma/config.toml` within 2 s and `:config` opens it for editing, so
making it a read-only store symlink would trade away the feature that makes it
pleasant.

If you hand-write a theme, note that **the upstream docs are wrong about
`[theme.colors]`**. They say it accepts "any key of Omarchy's `colors.toml`";
it does not. That vocabulary (`cursor`, `selection_background`,
`color0`..`color15`) applies only to an actual Omarchy `colors.toml` read via
`source = "omarchy"`. The keys `[theme.colors]` itself validates against are
`THEME_COLOR_KEYS` in `browser/omni.ja:chrome/browser/content/browser/vimma/core/theme.mjs`:

```
mode  accent  selection  muted
background  dark_background  darker_background  lighter_background
foreground  dark_foreground  light_foreground  bright_foreground
red  yellow  orange  green  cyan  blue  magenta  brown
bright_red  bright_yellow  bright_green  bright_cyan  bright_blue  bright_magenta
split_1 .. split_9
```

Anything else is rejected with `unknown colour key "<key>"`, the file is not
applied, and the previous working theme stays live. `about:vimma` lists every
error.

With `source = "file"`, unset keys fall back to Vimma's own built-in palette
rather than erroring — so a partial override mixes two themes. Set every key
to fully replace it. A base16 scheme maps on cleanly except for
`dark_background`/`darker_background`, which have no base16 equivalent (there
is only one dark background slot) and need picking by hand.

## Updating

```sh
./update.sh
```

Queries the latest release, re-pins `version` and `hash` from its
`SHA256SUMS`, prints the diff and stops. Review, `nix build .#vimma`, then
commit. It never commits, pushes or rebuilds.

Vimma is alpha and releases often, so expect to run this regularly.

## Licensing

This packaging is MIT (see `LICENSE`). Vimma itself is MPL-2.0 and is **not**
redistributed here — the flake fetches the upstream release tarball at build
time, verified against the sha256 published in that release's `SHA256SUMS`.
The sigstore bundles upstream also publishes are not checked.
