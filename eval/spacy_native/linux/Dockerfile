# Build with the repository root as context. The adjacent ignore file excludes
# local environments, checkpoints, datasets and host-compiled code.
FROM rust:1.90.0-slim-bookworm AS rust
FROM elixir:1.18.4-otp-27-slim
COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup
ARG ERL_FLAGS=""
ENV PATH="/usr/local/cargo/bin:${PATH}" \
    RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
    MIX_ENV=test OBSCURA_COMPATIBILITY_RUNTIME=1 ERL_FLAGS=${ERL_FLAGS}
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libopenblas-dev libpcre2-dev ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && mix local.hex --force && mix local.rebar --force \
    && rustup component add clippy rustfmt
WORKDIR /work
COPY mix.exs mix.lock .formatter.exs README.md ./
COPY priv/obscura ./priv/obscura
RUN mix deps.get --only test
COPY lib ./lib
COPY priv/tiktoken ./priv/tiktoken
COPY native/spacy_cpu ./native/spacy_cpu
COPY test ./test
COPY eval/authoritative ./eval/authoritative
COPY eval/spacy_native/profile_benchmark.exs ./eval/spacy_native/profile_benchmark.exs
COPY eval/spacy_native/results/comparison.json ./eval/spacy_native/results/comparison.json
COPY eval/spacy_native/linux/validate.sh ./eval/spacy_native/linux/validate.sh
RUN mix compile --warnings-as-errors && mix obscura.spacy.build \
    && cargo clippy --release --locked --offline --manifest-path native/spacy_cpu/Cargo.toml -- -D warnings
COPY eval/presidio_adapter/authoritative_protocol.json ./eval/presidio_adapter/authoritative_protocol.json
CMD ["sh", "eval/spacy_native/linux/validate.sh"]
