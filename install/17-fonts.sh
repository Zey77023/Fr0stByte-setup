#!/bin/bash

debug_msg "Starting font installation and configuration stage"

status_msg "Installing fonts to target system..."
FONT_LIST="$INSTALLER_ROOT/font-packages"
FONTCONFIG_FILE="$TARGET_MNT/etc/fonts/local.conf"

if gum confirm "Install fonts and configure font settings?" --default=no; then
    status_msg "Installing fonts"
    install_packages_from_list_in_chroot "$FONT_LIST"
    success_msg "Fonts installed"

    status_msg "Configuring font settings..."
    [[-f "$FONTCONFIG_FILE" ]] || : >"$FONTCONFIG_FILE"
    cat >>"$FONTCONFIG_FILE" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>

    <!-- Sans-serif fallback chain -->
    <alias>
        <family>sans-serif</family>
        <prefer>
            <family>Noto Sans</family>
            <family>Roboto</family>
            <family>Open Sans</family>
            <family>Cantarell</family>
            <family>Liberation Sans</family>
            <family>DejaVu Sans</family>
            <family>Noto Sans CJK JP</family>
            <family>Noto Sans CJK SC</family>
            <family>Noto Sans CJK TC</family>
            <family>Noto Sans CJK HK</family>
            <family>Noto Sans CJK KR</family>
            <family>Noto Color Emoji</family>
            <family>Noto Emoji</family>
        </prefer>
    </alias>

    <!-- Serif fallback chain -->
    <alias>
        <family>serif</family>
        <prefer>
            <family>Noto Serif</family>
            <family>Liberation Serif</family>
            <family>DejaVu Serif</family>
            <family>Noto Serif CJK JP</family>
            <family>Noto Serif CJK SC</family>
            <family>Noto Serif CJK TC</family>
            <family>Noto Serif CJK HK</family>
            <family>Noto Serif CJK KR</family>
            <family>Noto Color Emoji</family>
            <family>Noto Emoji</family>
        </prefer>
    </alias>

    <!-- Monospace fallback chain -->
    <alias>
        <family>monospace</family>
        <prefer>
            <family>Noto Sans Mono</family>
            <family>MesloLGS NF</family>
            <family>Liberation Mono</family>
            <family>DejaVu Sans Mono</family>
            <family>Noto Sans CJK JP</family>
            <family>Noto Sans CJK SC</family>
            <family>Noto Sans CJK KR</family>
            <family>Symbola</family>
            <family>Noto Color Emoji</family>
            <family>Noto Emoji</family>
        </prefer>
    </alias>

    <!-- Rendering & LCD subpixel anti-aliasing optimizations -->
    <match target="font">
        <edit name="antialias" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hinting" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hintstyle" mode="assign">
            <const>hintslight</const>
        </edit>
        <edit name="rgba" mode="assign">
            <const>rgb</const>
        </edit>
        <edit name="lcdfilter" mode="assign">
            <const>lcddefault</const>
        </edit>
    </match>

    <!-- Map standard proprietary fonts to installed open alternatives -->
    <alias>
        <family>Arial</family>
        <prefer><family>Liberation Sans</family></prefer>
    </alias>
    <alias>
        <family>Helvetica</family>
        <prefer><family>Liberation Sans</family></prefer>
    </alias>
    <alias>
        <family>Times New Roman</family>
        <prefer><family>Liberation Serif</family></prefer>
    </alias>
    <alias>
        <family>Courier New</family>
        <prefer><family>Liberation Mono</family></prefer>
    </alias>

</fontconfig>
EOF
    success_msg "Font settings configured"

    status_msg "Regenerating font cache..."
    chroot_exec fc-cache -fv
    success_msg "Font cache regenerated"
else
    status_msg "Font installation skipped"
fi

success_msg "Font installation and configuration complete"
