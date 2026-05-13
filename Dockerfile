FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="Automated LaTeX Paper Diff"
LABEL org.opencontainers.image.description="Table-aware latexdiff workflow for reviewer-facing marked manuscripts"
LABEL org.opencontainers.image.source="https://github.com/buaabarty/automated-latex-paper-diff"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
ENV TEXMFHOME=/tmp/empty-texmf
ENV TEXMFVAR=/tmp/texmf-var-clean

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    git \
    latexdiff \
    latexmk \
    make \
    perl \
    python3 \
    ripgrep \
    rsync \
    texlive-bibtex-extra \
    texlive-fonts-extra \
    texlive-fonts-recommended \
    texlive-latex-base \
    texlive-latex-extra \
    texlive-latex-recommended \
    texlive-plain-generic \
    texlive-publishers \
    texlive-science \
  && mkdir -p /tmp/empty-texmf /tmp/texmf-var-clean \
  && rm -rf /var/lib/apt/lists/*

COPY scripts/generate_marked_diff.sh /usr/local/bin/generate_marked_diff
COPY scripts/postprocess_marked_diff.py /usr/local/bin/postprocess_marked_diff.py
RUN chmod +x /usr/local/bin/generate_marked_diff

WORKDIR /work
ENTRYPOINT ["generate_marked_diff"]
CMD ["--help"]
