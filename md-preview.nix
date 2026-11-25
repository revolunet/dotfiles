# md-preview: styled Markdown preview for KDE Dolphin (middle-click / right-click).
# Renders .md into a themed PDF or HTML. Mermaid diagrams and KaTeX math work
# offline: the browser bundles are downloaded once at build time (pinned) and
# served from the Nix store — no runtime network, everything is MIT.
# Docs: https://github.com/BenXsha/md-preview
{ config, pkgs, ... }:

let
  # The upstream package is not on PyPI, so we build from the pinned GitHub
  # archive (tag v0.4.0, commit d385506f). It ships the default themes
  # (fallback.css / fallback-dark.css) as package data.
  mdPreview = pkgs.python3.pkgs.buildPythonApplication {
    pname = "md-preview-kde";
    version = "0.4.0";
    format = "pyproject";
    src = pkgs.fetchurl {
      url = "https://github.com/BenXsha/md-preview/archive/d385506f60b40d6beb2a57c285a013cf20056a11.tar.gz";
      sha256 = "sha256-wd8cVOXq2QFEeZj62P0YTxzx4HI9Qn4OmopFs93uAVU=";
    };
    # The pyproject build (`--no-isolation`) needs setuptools importable to
    # serve the setuptools.build_meta backend.
    nativeBuildInputs = with pkgs.python3Packages; [ setuptools ];
    propagatedBuildInputs = with pkgs.python3Packages; [
      markdown-it-py
      linkify-it-py
      mdit-py-plugins
      pygments
      pyyaml # YAML front matter (card display)
    ];
    meta = with pkgs.lib; {
      description = "Render Markdown into styled PDF/HTML, built for KDE Dolphin middle-click preview";
      homepage = "https://github.com/BenXsha/md-preview";
      license = licenses.mit;
      mainProgram = "md-preview";
    };
  };

  # KaTeX browser bundle (v0.16.11, the version md-preview pins upstream).
  # We extract only the files it references: the JS, the CSS and its relative fonts.
  katex = pkgs.stdenv.mkDerivation {
    pname = "mdp-katex";
    version = "0.16.11";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/katex/-/katex-0.16.11.tgz";
      sha256 = "sha256-jFSUxffY6L9z/z/mTUvQmjQOSHi37sm72e+Njz4kGT8=";
    };
    dontConfigure = true;
    dontBuild = true;
    sourceRoot = "package";
    installPhase = ''
      mkdir -p "$out/katex/fonts"
      cp dist/katex.min.js dist/katex.min.css "$out/katex/"
      cp dist/fonts/*.woff2 "$out/katex/fonts/"
    '';
  };

  # Mermaid browser bundle (v11.17.2, the version md-preview pins upstream).
  mermaid = pkgs.stdenv.mkDerivation {
    pname = "mdp-mermaid";
    version = "11.17.2";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/mermaid/-/mermaid-11.17.2.tgz";
      sha256 = "sha256-atL0LD/Ca7+eRcu20RiYlyVz6lKzOl9P9RlSiZ+VD/0=";
    };
    dontConfigure = true;
    dontBuild = true;
    sourceRoot = "package";
    installPhase = ''
      mkdir -p "$out/mermaid"
      cp dist/mermaid.min.js "$out/mermaid/"
    '';
  };

  # One read-only store directory, referenced from the config as assets_dir.
  # md-preview looks for <assets_dir>/katex and <assets_dir>/mermaid.
  assets = pkgs.runCommand "mdp-assets" { } ''
    mkdir -p "$out"
    cp -r "${katex}/katex" "$out/katex"
    cp -r "${mermaid}/mermaid" "$out/mermaid"
  '';
in
{
  home.packages = [ mdPreview ];

  # In Dolphin, middle-click opens the 2nd app for a MIME type and
  # Shift+middle-click the 3rd. Order: editor (double-click), then
  # md-preview (browser, opens the styled HTML in the default browser —
  # Firefox — via xdg-open), then md-preview (PDF, Chromium-only).
  # PDF generation is Chromium-only upstream (md-preview/_find_chromium), so
  # the middle-click default uses the browser route which works with Firefox.
  xdg.mimeApps = {
    enable = true;
    defaultApplications."text/markdown" = [ "org.kde.kate.desktop" ];
    defaultApplications."text/x-markdown" = [ "org.kde.kate.desktop" ];
    associations.added."text/markdown" = [
      "md-preview-browser.desktop"
      "md-preview.desktop"
    ];
    associations.added."text/x-markdown" = [
      "md-preview-browser.desktop"
      "md-preview.desktop"
    ];
  };

  xdg.configFile."md-preview/config".text = ''
    theme = default
    dark_theme = default-dark
    math = auto
    mermaid = auto
    assets_dir = ${assets}
    js_budget = 10000
    front_matter = card
  '';

  xdg.dataFile."applications/md-preview.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Markdown Preview
    Name[fr]=Aperçu Markdown
    Comment=Preview Markdown files as styled PDF
    Comment[fr]=Aperçu des fichiers Markdown en PDF stylé
    Exec=${mdPreview}/bin/md-preview %f
    Icon=text-markdown
    Terminal=false
    Categories=Office;Viewer;
    MimeType=text/markdown;text/x-markdown;
    InitialPreference=7
  '';

  xdg.dataFile."applications/md-preview-browser.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Markdown Preview (Browser)
    Name[fr]=Aperçu Markdown (navigateur)
    Comment=Preview Markdown files as styled HTML in the browser
    Comment[fr]=Aperçu des fichiers Markdown en HTML dans le navigateur
    Exec=${mdPreview}/bin/md-preview --html %f
    Icon=text-html
    Terminal=false
    Categories=Office;Viewer;
    MimeType=text/markdown;text/x-markdown;
    InitialPreference=7
  '';

  # Right-click → Markdown Preview (PDF) / (Browser). KIO user service menus
  # must be executable for Dolphin to trust them.
  xdg.dataFile."kio/servicemenus/md-preview-servicemenu.desktop" = {
    executable = true;
    text = ''
      [Desktop Entry]
      Type=Service
      ServiceTypes=KonqPopupMenu/Plugin
      MimeType=text/markdown;text/x-markdown;
      Actions=previewPdf;previewHtml;
      X-KDE-Priority=TopLevel

      [Desktop Action previewPdf]
      Name=Markdown Preview (PDF)
      Name[fr]=Aperçu Markdown (PDF)
      Icon=text-markdown
      Exec=${mdPreview}/bin/md-preview %f

      [Desktop Action previewHtml]
      Name=Markdown Preview (Browser)
      Name[fr]=Aperçu Markdown (navigateur)
      Icon=text-html
      Exec=${mdPreview}/bin/md-preview --html %f
    '';
  };

  # Refresh the KDE desktop-file cache so the new entries show up without a
  # full logout; it is a no-op when kbuildsycoca6 is not available.
  home.activation.mdPreviewKdeRefresh = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi
  '';
}
