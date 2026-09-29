# FROM ghcr.io/joercat/digpvp:latest 
FROM lscr.io/linuxserver/webtop:debian-xfce

# Install sudo, standard VM utilities, Firefox ESR, and CPU management tools
RUN apt-get update && \
    apt-get install -y \
    sudo \
    firefox-esr \
    cpulimit \
    curl \
    wget \
    nano \
    htop \
    git \
    zip \
    unzip \
    procps \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Grant passwordless sudo to the default 'abc' user
RUN echo "abc ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abc && \
    chmod 0440 /etc/sudoers.d/abc

# Configure for HF Spaces, force X11, and set optimizations
ENV PUID=1000 \
    PGID=1000 \
    TZ=Etc/UTC \
    CUSTOM_PORT=7860 \
    TITLE="Debian 13, XFCE (Optimized X11)" \
    FRAMERATE=20 \
    JPEG_QUALITY=65 \
    PIXELFLUX_WAYLAND=false

# Create necessary directories
RUN mkdir -p /config/.config/autostart /config/custom-cont-init.d /config/bin

# Create XFCE optimization script (Disables window compositing to save CPU)
RUN echo '#!/bin/bash' > /config/custom-cont-init.d/optimize-xfce.sh && \
    echo '# Create autostart entry to disable XFCE compositing' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'mkdir -p /config/.config/autostart' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'cat > /config/.config/autostart/disable-compositing.desktop << "EOF"' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo '[Desktop Entry]' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'Type=Application' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'Name=Disable Compositing' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'Exec=xfconf-query -c xfwm4 -p /general/use_compositing -s false' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'Hidden=false' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'NoDisplay=false' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'X-GNOME-Autostart-enabled=true' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    echo 'EOF' >> /config/custom-cont-init.d/optimize-xfce.sh && \
    chmod +x /config/custom-cont-init.d/optimize-xfce.sh

# Create CPU limiting wrapper scripts
RUN echo '#!/bin/bash' > /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '# Firefox wrapper - limit to 80% CPU' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'cat > /config/bin/firefox-limited << "EOF"' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '#!/bin/bash' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'cpulimit -l 80 -e firefox-esr &' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'exec /usr/bin/firefox-esr "$@"' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'EOF' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'chmod +x /config/bin/firefox-limited' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '# Create desktop entry for limited Firefox' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'mkdir -p /config/.local/share/applications' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'cat > /config/.local/share/applications/firefox-limited.desktop << "EOF"' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '[Desktop Entry]' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'Name=Firefox (CPU Limited)' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'Exec=/config/bin/firefox-limited %u' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'Icon=firefox-esr' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'Type=Application' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'Categories=Network;WebBrowser;' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'EOF' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo '# Add /config/bin to PATH' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    echo 'echo "export PATH=/config/bin:\$PATH" >> /config/.bashrc' >> /config/custom-cont-init.d/cpu-limit-wrappers.sh && \
    chmod +x /config/custom-cont-init.d/cpu-limit-wrappers.sh

# Create a CPU monitor service script that runs in foreground
RUN echo '#!/bin/bash' > /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '# Create CPU monitor that runs as a service' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo 'cat > /usr/local/bin/cpu-monitor << "MONITOR_EOF"' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '#!/bin/bash' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo 'while true; do' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '    for pid in $(ps aux | awk '"'"'{if($3 > 90.0) print $2}'"'"'); do' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '        if ! pgrep -f "cpulimit.*$pid" > /dev/null 2>&1; then' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '            cpulimit -p $pid -l 80 -b 2>/dev/null || true' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '        fi' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '    done' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo '    sleep 5' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo 'done' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo 'MONITOR_EOF' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    echo 'chmod +x /usr/local/bin/cpu-monitor' >> /config/custom-cont-init.d/01-cpu-monitor.sh && \
    chmod +x /config/custom-cont-init.d/01-cpu-monitor.sh

EXPOSE 7860
