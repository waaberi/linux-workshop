FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes && \
    apt-get update && apt-get install --reinstall -y \
    bash \
    coreutils \
    nano \
    less \
    curl \
    iputils-ping \
    iproute2 \
    dnsutils \
    python3 \
    procps \
    findutils \
    grep \
    man-db \
    manpages \
    xxd \
    sudo \
    && if [ "$(dpkg-divert --truename /usr/bin/man)" = "/usr/bin/man.REAL" ]; then rm -f /usr/bin/man && dpkg-divert --quiet --remove --rename /usr/bin/man; fi \
    && mandb -q \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV LESSCHARSET=utf-8

# Create ieee user
RUN useradd -m -s /bin/bash ieee

# Sudo: ieee can ONLY run the verifier helpers and fixed challenge emitters as root
RUN echo "ieee ALL=(root) NOPASSWD: /opt/verifier.sh, /opt/cmdlog.sh, /opt/pipes-step1.sh, /opt/pipes-noisy.sh" > /etc/sudoers.d/ieee && \
    chmod 440 /etc/sudoers.d/ieee

# Copy all files into /opt/ (root-owned)
COPY setup.sh /opt/setup.sh
COPY verifier.sh /opt/verifier.sh
COPY cmdlog.sh /opt/cmdlog.sh
COPY entrypoint.sh /opt/entrypoint.sh
COPY challenges.txt /opt/challenges.txt
COPY challenges.sh /usr/local/bin/challenges
COPY welcome.sh /usr/local/bin/welcome
COPY services/flag-server.py /opt/flag-server.py

# Permissions:
#   verifier.sh, setup.sh, entrypoint.sh — root only (contain answers)
#   challenges.txt, flag-server.py     — world-readable (no secrets)
#   challenges command, verifier wrapper, welcome — world-executable
RUN chmod 700 /opt/verifier.sh /opt/setup.sh /opt/entrypoint.sh /opt/cmdlog.sh && \
    chmod 644 /opt/challenges.txt /opt/flag-server.py && \
    chmod +x /usr/local/bin/challenges /usr/local/bin/welcome && \
    ln -s /usr/local/bin/challenges /usr/local/bin/challenge

# Create wrappers (readable, but just sudo calls — no answers)
RUN printf '#!/bin/bash\nset -e\nname=$(basename "$0")\ncase "$name" in\n    verify|reset|status) exec sudo /opt/verifier.sh "$name" "$@" ;;\n    verifier) exec sudo /opt/verifier.sh "$@" ;;\n    *) echo "Unknown verifier entrypoint: $name" >&2; exit 1 ;;\nesac\n' > /usr/local/bin/verifier && \
    printf '#!/bin/bash\nsudo /opt/cmdlog.sh "$@"\n' > /usr/local/bin/cmdlog && \
    chmod +x /usr/local/bin/verifier /usr/local/bin/cmdlog && \
    ln -s /usr/local/bin/verifier /usr/local/bin/verify && \
    ln -s /usr/local/bin/verifier /usr/local/bin/reset && \
    ln -s /usr/local/bin/verifier /usr/local/bin/status

# Run setup to create all challenge files and directories
RUN /opt/setup.sh

# Keep a clean baseline for challenge 7.3 resets.
RUN cp /home/ieee/.bashrc /opt/.bashrc.baseline && chmod 644 /opt/.bashrc.baseline

# Add transparent command logging outside the student's ~/.bashrc so challenge 7.3
# cannot break later verifier checks by accident.
RUN printf '%s\n' \
    'export LANG=C.UTF-8' \
    'export LESSCHARSET=utf-8' \
    '_workshop_log_cmd() {' \
    '    local c' \
    '    c=$(history 1 | sed "s/^[[:space:]]*[0-9]*[[:space:]]*//")' \
    '    [ -n "$c" ] && cmdlog "$c"' \
    '}' \
    'case ";${PROMPT_COMMAND:-};" in' \
    '    *";_workshop_log_cmd;"*) ;;' \
    '    "") PROMPT_COMMAND="_workshop_log_cmd" ;;' \
    '    *) PROMPT_COMMAND="_workshop_log_cmd;${PROMPT_COMMAND}" ;;' \
    'esac' \
    > /etc/profile.d/workshop-shell.sh && \
    chmod 644 /etc/profile.d/workshop-shell.sh

# Entrypoint runs as root (starts services, then drops to ieee)
WORKDIR /home/ieee
ENTRYPOINT ["/opt/entrypoint.sh"]
