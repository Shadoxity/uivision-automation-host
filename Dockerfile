# Use minimal base image
FROM debian:bookworm-slim

# Build arguments for configuration
ARG DEF_VNC_SCREEN=0
ARG DEF_VNC_DISPLAY=0
ARG DEF_VNC_RESOLUTION=1280x720
ARG DEF_VNC_PASSWORD=money4band
ARG DEF_VNC_PORT=5900
ARG DEF_NOVNC_WEBSOCKIFY_PORT=6080
ARG DEF_STARTING_WEBSITE_URL=https://www.google.com
ARG DEF_LANG=en_US.UTF-8
ARG DEF_LC_ALL=C.UTF-8
ARG DEF_CUSTOMIZE=false
ARG DEF_CUSTOM_ENTRYPOINTS_DIR=/app/custom_entrypoints_scripts
ARG DEF_AUTO_START_BROWSER=true
ARG DEF_AUTO_START_XTERM=true
ARG DEF_DEBIAN_FRONTEND=noninteractive

# Set environment variables
ENV DISPLAY=:${DEF_VNC_DISPLAY}.${DEF_VNC_SCREEN} \
    VNC_SCREEN=${DEF_VNC_SCREEN} \
    VNC_DISPLAY=${DEF_VNC_DISPLAY} \
    VNC_RESOLUTION=${DEF_VNC_RESOLUTION} \
    VNC_PASSWORD=${DEF_VNC_PASSWORD} \
    VNC_PORT=${DEF_VNC_PORT} \
    NOVNC_WEBSOCKIFY_PORT=${DEF_NOVNC_WEBSOCKIFY_PORT} \
    STARTING_WEBSITE_URL=${DEF_STARTING_WEBSITE_URL} \
    LANG=${DEF_LANG} \
    LC_ALL=${DEF_LC_ALL} \
    CUSTOMIZE=${DEF_CUSTOMIZE} \
    CUSTOM_ENTRYPOINTS_DIR=${DEF_CUSTOM_ENTRYPOINTS_DIR} \
    AUTO_START_BROWSER=${DEF_AUTO_START_BROWSER} \
    AUTO_START_XTERM=${DEF_AUTO_START_XTERM} \
    DEBIAN_FRONTEND=${DEF_DEBIAN_FRONTEND}

# Update, full-upgrade, install required packages, and set up Node.js
RUN apt update && apt full-upgrade -qqy && \
    apt install -qqy --no-install-recommends \
    curl wget unzip tini supervisor bash xvfb x11vnc novnc websockify fluxbox xterm nano \
    firefox-esr libfuse2 && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt install -qqy --no-install-recommends nodejs && \
    apt autoremove --purge -y && apt clean && rm -rf /var/lib/apt/lists/*


# Copy xmodules and run installation script
COPY data/xmodules /opt/uivision/xmodules
RUN cd /opt/uivision/xmodules && chmod +x 1install.sh && ./1install.sh

# Set working directory
WORKDIR /usr/src/app

# Install Node.js dependencies
COPY package*.json ./
RUN npm install --production && npm cache clean --force

# Copy source code and data
COPY src ./src
COPY data ./data

# Setup Firefox profile
RUN mkdir -p /root/.mozilla/firefox && \
    cp /usr/src/app/data/profiles.ini /root/.mozilla/firefox/profiles.ini
COPY data/firefox_profile.zip /tmp/
RUN unzip /tmp/firefox_profile.zip -d /root/.mozilla/firefox/ && rm /tmp/firefox_profile.zip

# Make browser run scripts executable and ensure proper permissions
RUN chmod +x /usr/src/app/src/run-firefox.sh && \
    ls -la /usr/src/app/src/run-firefox.sh && \
    # Create a symlink to ensure the script is accessible from PATH
    ln -sf /usr/src/app/src/run-firefox.sh /usr/local/bin/run-firefox.sh

# Create custom entrypoint script to start the Node.js server
RUN mkdir -p ${CUSTOM_ENTRYPOINTS_DIR} && \
    echo '#!/bin/bash\necho "Starting Node.js API server on port $API_PORT..."\ncd /usr/src/app\nnode src/server.js 2>&1 | tee /var/log/node-server.log &\necho "Node.js API server started with PID $!"\n# Create a dummy file to keep container running\ntouch /tmp/keep-alive\ntail -f /tmp/keep-alive' > ${CUSTOM_ENTRYPOINTS_DIR}/01-start-node-server.sh && \
    chmod +x ${CUSTOM_ENTRYPOINTS_DIR}/01-start-node-server.sh

# Copy supervisor and entrypoint configuration files
COPY supervisord.conf /etc/supervisor.d/supervisord.conf
COPY data/conf.d/ /app/conf.d/
COPY base_entrypoint.sh customizable_entrypoint.sh /usr/local/bin/

# Make entrypoint scripts executable
RUN chmod +x /usr/local/bin/base_entrypoint.sh /usr/local/bin/customizable_entrypoint.sh

# Set environment variable to enable custom entrypoints
ENV CUSTOMIZE=true

# Expose VNC, noVNC, and Node.js API ports
EXPOSE ${VNC_PORT} ${NOVNC_WEBSOCKIFY_PORT} 3000

# Set environment variable for API port
ENV API_PORT=3000

# Set tini as entrypoint and run customizable entrypoint script
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/customizable_entrypoint.sh"] 