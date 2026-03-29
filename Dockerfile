# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────────────────────
# Tool versions — edit these ARG lines to pin or bump a specific tool.
# Use "latest" to resolve the current release automatically at build time.
#
# Release pages:
#   AWS CLI v2:     https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst
#   SSM Plugin:     https://docs.aws.amazon.com/systems-manager/latest/userguide/plugin-version-history.html
#   okta-aws-cli:   https://github.com/okta/okta-aws-cli/releases
# ─────────────────────────────────────────────────────────────────────────────
ARG AWS_CLI_VERSION=latest
ARG SSM_PLUGIN_VERSION=latest
ARG OKTA_AWS_CLI_VERSION=latest

FROM debian:bookworm-slim

ARG AWS_CLI_VERSION
ARG SSM_PLUGIN_VERSION
ARG OKTA_AWS_CLI_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# ── Detect CPU architecture at runtime using uname ───────────────────────────
# uname -m reflects what is actually running inside the container, which is
# more reliable than TARGETARCH when using Colima or other VM-based runtimes
# where the build platform and runtime platform can report differently.
RUN case "$(uname -m)" in \
      aarch64|arm64) \
        echo "aarch64"      > /tmp/aws_arch && \
        echo "ubuntu_arm64" > /tmp/ssm_arch && \
        echo "arm64"        > /tmp/okta_arch ;; \
      *) \
        echo "x86_64"       > /tmp/aws_arch && \
        echo "ubuntu_64bit" > /tmp/ssm_arch && \
        echo "amd64"        > /tmp/okta_arch ;; \
    esac

# ── Runtime packages ──────────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        unzip \
        nano \
        ca-certificates \
        less \
        openssh-client \
        netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# ── AWS CLI v2 ────────────────────────────────────────────────────────────────
# "latest" uses AWS's official permanent latest URL.
# A pinned version constructs a versioned URL.
RUN AWS_ARCH=$(cat /tmp/aws_arch) && \
    if [ "$AWS_CLI_VERSION" = "latest" ]; then \
      URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"; \
    else \
      URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWS_CLI_VERSION}.zip"; \
    fi && \
    curl -fsSL "$URL" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install --bin-dir /usr/bin --install-dir /usr/lib/aws-cli && \
    rm -rf /tmp/awscliv2.zip /tmp/aws \
        /usr/lib/aws-cli/v2/*/dist/aws_completer \
        /usr/lib/aws-cli/v2/*/dist/awscli/data/ac.index \
        /usr/lib/aws-cli/v2/*/dist/awscli/examples

# ── AWS Session Manager Plugin ────────────────────────────────────────────────
# "latest" uses AWS's official permanent latest URL.
# A pinned version constructs a versioned URL.
RUN SSM_ARCH=$(cat /tmp/ssm_arch) && \
    if [ "$SSM_PLUGIN_VERSION" = "latest" ]; then \
      URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${SSM_ARCH}/session-manager-plugin.deb"; \
    else \
      URL="https://s3.amazonaws.com/session-manager-downloads/plugin/${SSM_PLUGIN_VERSION}/${SSM_ARCH}/session-manager-plugin.deb"; \
    fi && \
    curl -fsSL "$URL" -o /tmp/session-manager-plugin.deb && \
    dpkg -i /tmp/session-manager-plugin.deb && \
    rm /tmp/session-manager-plugin.deb

# ── okta-aws-cli ──────────────────────────────────────────────────────────────
# "latest" queries the GitHub API to resolve the current version number first,
# since GitHub release URLs require an explicit version in the path.
RUN OKTA_ARCH=$(cat /tmp/okta_arch) && \
    if [ "$OKTA_AWS_CLI_VERSION" = "latest" ]; then \
      OKTA_AWS_CLI_VERSION=$(curl -fsSL \
        "https://api.github.com/repos/okta/okta-aws-cli/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"v([^"]+)".*/\1/'); \
    fi && \
    curl -fsSL "https://github.com/okta/okta-aws-cli/releases/download/v${OKTA_AWS_CLI_VERSION}/okta-aws-cli_${OKTA_AWS_CLI_VERSION}_linux_${OKTA_ARCH}.tar.gz" \
        -o /tmp/okta-aws-cli.tar.gz && \
    tar -xzf /tmp/okta-aws-cli.tar.gz -C /usr/bin okta-aws-cli && \
    rm /tmp/okta-aws-cli.tar.gz

# ── Verify all tools installed correctly ─────────────────────────────────────
RUN aws --version && \
    session-manager-plugin --version && \
    okta-aws-cli --version

# ── Helper scripts ────────────────────────────────────────────────────────────
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/ssm-proxy.sh /usr/local/bin/entrypoint.sh

# ── Cleanup arch hint files ───────────────────────────────────────────────────
RUN rm /tmp/aws_arch /tmp/ssm_arch /tmp/okta_arch

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
