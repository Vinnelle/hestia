FROM mirror.vinnel.cloud/kiwigrid/k8s-sidecar:2.14.3@sha256:52d311dcedd587421a236c4d6c621f05614c40a51386e955e0699dca97ec0880
USER root
RUN apk upgrade --no-cache \
    && /app/.venv/bin/pip install --no-cache-dir certifi==2026.10.23 \
    && /app/.venv/bin/pip uninstall --yes pip \
    && rm -rf /usr/local/lib/python3.14/site-packages/pip /usr/local/lib/python3.14/site-packages/pip-*.dist-info /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.14
USER 65534:65534
