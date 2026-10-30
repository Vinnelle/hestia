FROM mirror.vinnel.cloud/kiwigrid/k8s-sidecar:2.14.1@sha256:092dbe0c335fba9af414a27630ca68f34df6185784fa847d9954187e69dbfdd7
USER root
RUN apk upgrade --no-cache \
    && /app/.venv/bin/pip install --no-cache-dir certifi==2026.10.23 \
    && /app/.venv/bin/pip uninstall --yes pip \
    && rm -rf /usr/local/lib/python3.14/site-packages/pip /usr/local/lib/python3.14/site-packages/pip-*.dist-info /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.14
USER 65534:65534
