exclude =
  []
  |> then(fn exclude ->
    if System.get_env("OBSCURA_REAL_MODEL") == "1",
      do: exclude,
      else: [real_model: true] ++ exclude
  end)
  |> then(fn exclude ->
    if System.get_env("OBSCURA_GLINER_ORTEX") == "1",
      do: exclude,
      else: [gliner_ortex: true] ++ exclude
  end)
  |> then(fn exclude ->
    if System.get_env("OBSCURA_GLINER_URCHADE_MODEL_DIR"),
      do: exclude,
      else: [gliner_urchade: true] ++ exclude
  end)
  |> then(fn exclude ->
    if System.get_env("OBSCURA_GLINER_NVIDIA_MODEL_DIR"),
      do: exclude,
      else: [gliner_nvidia: true] ++ exclude
  end)
  |> then(fn exclude ->
    if System.get_env("OBSCURA_GLINER_NATIVE_MODEL_DIR"),
      do: exclude,
      else: [gliner_native: true] ++ exclude
  end)

ExUnit.start(exclude: exclude)
Code.require_file("support/soak_report_fixture.exs", __DIR__)
Code.require_file("support/diagnostic_report_fixture.exs", __DIR__)
Code.require_file("support/gliner_parity_assertions.exs", __DIR__)
