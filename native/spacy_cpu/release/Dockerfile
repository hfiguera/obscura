# Build with the repository root as context. The adjacent ignore file excludes
# local environments, checkpoints, datasets and host-compiled code.
FROM rust:1.90.0-slim-bookworm@sha256:64232e656c058f4468e8d024e990acff04f0fd5a5c0a88a574dc37773d7325c9 AS rust
FROM elixir:1.18.4-otp-27-slim@sha256:b0200debd7d9652c62bf77eef9d66c40afb2aac0dd1a4e28ea007770e637a67d
COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup
COPY --from=rust /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ARG ERL_FLAGS=""
ENV PATH="/usr/local/cargo/bin:${PATH}" \
    RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
    MIX_ENV=test OBSCURA_COMPATIBILITY_RUNTIME=1 ERL_FLAGS=${ERL_FLAGS}
RUN rm -f /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260904T000000Z bookworm main' \
      'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/20260904T000000Z bookworm-security main' > /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
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
COPY eval/efficient ./eval/efficient
RUN mix compile --warnings-as-errors && mix obscura.spacy.build \
    && cargo clippy --release --locked --offline --manifest-path native/spacy_cpu/Cargo.toml -- -D warnings
COPY eval/presidio_adapter/authoritative_protocol.json ./eval/presidio_adapter/authoritative_protocol.json
CMD ["mix", "run", "--no-start", "eval/efficient/workload.exs"]
