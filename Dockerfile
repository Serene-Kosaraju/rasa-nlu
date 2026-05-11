FROM python:3.7-slim as base

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
    # required by psycopg2 at build and runtime
    libpq-dev \
     # required for health check
    curl \
 && apt-get autoremove -y

FROM base as builder

RUN apt-get update -qq && \
  apt-get install -y --no-install-recommends \
  build-essential \
  wget \
  openssh-client \
  graphviz-dev \
  pkg-config \
  git-core \
  openssl \
  libssl-dev \
  libffi-dev \
  libpng-dev
RUN apt-get update && apt-get install -y build-essential libpq-dev
# install poetry
# keep this in sync with the version in pyproject.toml and Dockerfile
ENV POETRY_VERSION 1.0.5
#RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python
#RUN curl -sSL https://install.python-poetry.org | python3
RUN pip3 install poetry --timeout 1000
# ENV PATH "/root/.poetry/bin:/opt/venv/bin:${PATH}"
ENV POETRY_HOME="/opt/poetry"
ENV PATH="$POETRY_HOME/bin:$PATH"

# copy files
COPY . /build/

# change working directory
WORKDIR /build

# install dependencies
RUN python -m venv /opt/venv && \
  . /opt/venv/bin/activate
RUN pip3 install --no-cache-dir -U 'pip<20' --timeout 1000 
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV POETRY_VIRTUALENVS_CREATE=false
RUN poetry config installer.max-workers 10
RUN poetry cache clear . --all --no-interaction
ENV POETRY_HTTP_TIMEOUT=120
ENV POETRY_VIRTUALENVS_IN_PROJECT=true
RUN poetry install --no-dev --no-root --no-interaction
RUN poetry build -f wheel -n 
RUN pip3 install --no-deps dist/*.whl --timeout 1000 
RUN rm -rf dist *.egg-info

# start a new build stage
FROM base as runner

# copy everything from /opt
COPY --from=builder /opt/venv /opt/venv

# make sure we use the virtualenv
ENV PATH="/opt/venv/bin:$PATH"

# update permissions & change user to not run as root
WORKDIR /app
RUN chgrp -R 0 /app && chmod -R g=u /app
USER 1001

# create a volume for temporary data
VOLUME /tmp

# change shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# the entry point
EXPOSE 5005
ENTRYPOINT ["rasa"]
CMD ["--help"]
