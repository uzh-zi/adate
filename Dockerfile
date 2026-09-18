# syntax=docker/dockerfile:1

# ---- build: resolve dependencies into a venv --------------------------------
#
# The CI tier builds the production image. That is what makes "anything in the
# productive image is in the CI image in an identical version" true rather than
# aspirational: both stages below come from the same lineage, so the interpreter
# here and the interpreter that ships are the same binary.
FROM acrcentralregprod.azurecr.io/uzh/zi/python-ci:3.11 AS build
WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

# uv.lock is committed, so two builds of the same commit produce the same
# dependency set -- including the exact appkit commit. `--locked` fails the build
# if the lockfile has drifted from pyproject.toml rather than quietly resolving
# something else; re-run `uv lock` after changing a dependency.
#
# .python-version is copied deliberately: with UV_PYTHON_DOWNLOADS=never, a
# version the base image did not pre-warm fails the build loudly here instead of
# silently shipping a different interpreter than the one CI tested.
COPY pyproject.toml uv.lock README.md .python-version ./
COPY app ./app
RUN uv sync --locked --no-dev

# ---- runtime: slim image, non-root, managed identity ------------------------
#
# The runtime tier carries no agent, no Node and no gh. git is absent too, which
# is why the venv is copied in rather than resolved here.
FROM acrcentralregprod.azurecr.io/uzh/zi/python-runtime:3.11 AS runtime
WORKDIR /app

# Both tiers run as the same uid, so the venv arrives with workable ownership,
# and the interpreter it points at lives at the same path in both images.
COPY --from=build /app/.venv /app/.venv
COPY app ./app

# APPKIT_AUTH=easyauth declares "a trusted proxy terminates the login in front
# of me, so the X-MS-CLIENT-PRINCIPAL headers can be believed". That is only
# true if the Container App has authentication enabled AND set to *reject*
# unauthenticated requests — otherwise a caller reaching the container by
# another route can set those headers by hand and pick their own roles.
# See the auth section of README.md before changing this.
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    APPKIT_BACKEND=azure \
    APPKIT_AUTH=easyauth

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/health').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
