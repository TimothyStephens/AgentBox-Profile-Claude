# Personal tool layer on top of the current agentbox-claude image.
# Rules enforced by `./build.sh check`:
#   - first instruction is `ARG BASE`, second is `FROM ${BASE}` (ab passes the current tag)
#   - no USER, ENTRYPOINT or CMD
#   - every download is checksum-verified
# This is a template: add tools the same way, one checksum-verified RUN each.

ARG BASE
FROM ${BASE}

# neovim 0.10.4
RUN set -eux; \
    curl -fsSL -o /tmp/nvim.tar.gz \
      https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-x86_64.tar.gz; \
    echo "95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f  /tmp/nvim.tar.gz" \
      | sha256sum -c -; \
    tar -xzf /tmp/nvim.tar.gz -C /opt; \
    mv /opt/nvim-linux-x86_64 /opt/nvim; \
    ln -s /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    rm -f /tmp/nvim.tar.gz; \
    nvim --version

ENV EDITOR=nvim
