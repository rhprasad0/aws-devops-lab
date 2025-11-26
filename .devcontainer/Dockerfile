# Secure Development Container for AWS DevOps Lab
# Hardened for AI coding agent use - prevents prompt injection escalation

FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Metadata
LABEL maintainer="aws-devops-lab"
LABEL description="Secure dev container for Cursor AI agent sandboxing"

# Install additional development tools
# Note: AWS CLI, Terraform, kubectl installed via devcontainer features
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python for scripting
    python3 \
    python3-pip \
    python3-venv \
    # Git (already installed, but ensure latest)
    git \
    # Useful utilities
    jq \
    make \
    unzip \
    less \
    vim-tiny \
    ca-certificates \
    curl \
    # Clean up to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor) - not available in apt
RUN curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install uv (fast Python package manager) - required for MCP servers
# uvx is used to run awslabs MCP servers: terraform, aws-api, documentation, eks
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && chmod +x /usr/local/bin/uv /usr/local/bin/uvx

# Install Python packages for AWS development
# Note: botocore[crt] is required for MCP servers when using 'aws login' credential provider
RUN pip3 install --no-cache-dir \
    boto3 \
    "botocore[crt]" \
    awscli-local \
    checkov

# SECURITY: Ensure vscode user exists and has proper permissions
# The base image creates this user, but we ensure correct setup
RUN if ! id -u vscode > /dev/null 2>&1; then \
        useradd -m -s /bin/bash vscode; \
    fi

# SECURITY: Create AWS config directory for SSO
RUN mkdir -p /home/vscode/.aws \
    && chown -R vscode:vscode /home/vscode/.aws \
    && chmod 700 /home/vscode/.aws

# SECURITY: Set restrictive umask for new files
RUN echo "umask 027" >> /home/vscode/.bashrc

# SECURITY: Configure git safe.directory for the workspace
RUN git config --system --add safe.directory /workspaces/aws-devops-lab

# SECURITY: Add reminder about SSO login to bash prompt
RUN echo 'echo "🔒 Secure container. AWS credentials: run aws sso login"' >> /home/vscode/.bashrc

# Switch to non-root user
USER vscode
WORKDIR /home/vscode

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD [ "true" ]

