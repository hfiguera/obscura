defmodule Obscura.Operator.Hash do
  @moduledoc """
  Versioned salted hashing for anonymizer replacements.

  Secure mode uses a fresh random salt for every replacement. Deterministic
  mode requires an explicit salt of at least 16 bytes. Both modes use the
  encoded format `$obscura$v1$hash$ALGORITHM$MODE$SALT$DIGEST`.
  """

  alias Obscura.Anonymizer.Error

  @algorithms [:sha256, :sha512]
  @modes [:secure, :deterministic]
  @allowed_options [:type, :algorithm, :mode, :salt]
  @minimum_salt_bytes 16
  @version 1

  @doc false
  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(config) when is_map(config) do
    with :ok <- validate_options(config),
         :ok <- validate_algorithm(Map.get(config, :algorithm, :sha256)),
         :ok <- validate_mode(Map.get(config, :mode, :secure)) do
      validate_salt(config, Map.get(config, :mode, :secure))
    end
  end

  def validate(_config), do: {:error, Error.new(:invalid_operator_config, operator: :hash)}

  @doc false
  @spec apply(String.t(), map()) :: {:ok, String.t(), map()} | {:error, Error.t()}
  def apply(value, config) when is_binary(value) and is_map(config) do
    with :ok <- validate(config) do
      algorithm = Map.get(config, :algorithm, :sha256)
      mode = Map.get(config, :mode, :secure)
      salt = salt(config, mode)
      encoded_salt = Base.url_encode64(salt, padding: false)
      digest = digest(algorithm, salt, value)

      replacement =
        Enum.join(
          [
            "$obscura",
            "v#{@version}",
            "hash",
            Atom.to_string(algorithm),
            Atom.to_string(mode),
            encoded_salt,
            Base.encode16(digest, case: :lower)
          ],
          "$"
        )

      {:ok, replacement,
       %{
         algorithm: algorithm,
         deterministic: mode == :deterministic,
         mode: mode,
         salt: encoded_salt,
         version: @version
       }}
    end
  end

  def apply(_value, _config),
    do:
      {:error,
       Error.new(:invalid_operator_option,
         operator: :hash,
         field: :source,
         reason: :expected_binary
       )}

  @doc """
  Verifies a value against a versioned Obscura hash replacement.

  Returns `false` for malformed or unsupported encoded replacements.
  """
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(value, replacement) when is_binary(value) and is_binary(replacement) do
    case decode(replacement) do
      {:ok, algorithm, salt, expected_digest} ->
        :crypto.hash_equals(digest(algorithm, salt, value), expected_digest)

      _error ->
        false
    end
  end

  def verify(_value, _replacement), do: false

  defp decode(replacement) do
    case String.split(replacement, "$", trim: false) do
      ["", "obscura", "v1", "hash", algorithm, mode, salt, digest] ->
        with {:ok, algorithm} <- decode_algorithm(algorithm),
             true <- mode in Enum.map(@modes, &Atom.to_string/1),
             {:ok, salt} <- Base.url_decode64(salt, padding: false),
             true <- byte_size(salt) >= @minimum_salt_bytes,
             {:ok, digest} <- Base.decode16(digest, case: :mixed),
             true <- byte_size(digest) == digest_size(algorithm) do
          {:ok, algorithm, salt, digest}
        else
          _invalid -> :error
        end

      _other ->
        :error
    end
  end

  defp validate_options(config) do
    case Map.keys(config) -- @allowed_options do
      [] ->
        :ok

      _unknown ->
        {:error,
         Error.new(:unknown_operator_option,
           operator: :hash,
           metadata: %{allowed_options: @allowed_options}
         )}
    end
  end

  defp validate_algorithm(algorithm) when algorithm in @algorithms, do: :ok

  defp validate_algorithm(_algorithm) do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :hash,
       field: :algorithm,
       reason: :unsupported_algorithm
     )}
  end

  defp validate_mode(mode) when mode in @modes, do: :ok

  defp validate_mode(_mode) do
    {:error,
     Error.new(:invalid_operator_option,
       operator: :hash,
       field: :mode,
       reason: :unsupported_mode
     )}
  end

  defp validate_salt(config, :secure) do
    if Map.has_key?(config, :salt) do
      {:error,
       Error.new(:invalid_operator_option,
         operator: :hash,
         field: :salt,
         reason: :secure_mode_generates_salt
       )}
    else
      :ok
    end
  end

  defp validate_salt(config, :deterministic) do
    case Map.fetch(config, :salt) do
      :error ->
        {:error,
         Error.new(:missing_operator_option,
           operator: :hash,
           field: :salt,
           reason: :required_for_deterministic_mode,
           metadata: %{minimum_bytes: @minimum_salt_bytes}
         )}

      {:ok, salt} when is_binary(salt) and byte_size(salt) >= @minimum_salt_bytes ->
        :ok

      {:ok, _salt} ->
        {:error,
         Error.new(:invalid_operator_option,
           operator: :hash,
           field: :salt,
           reason: :salt_too_short,
           metadata: %{minimum_bytes: @minimum_salt_bytes}
         )}
    end
  end

  defp validate_salt(_config, _mode), do: :ok

  defp salt(_config, :secure), do: :crypto.strong_rand_bytes(@minimum_salt_bytes)
  defp salt(config, :deterministic), do: Map.fetch!(config, :salt)

  defp digest(algorithm, salt, value), do: :crypto.hash(algorithm, [salt, value])

  defp decode_algorithm("sha256"), do: {:ok, :sha256}
  defp decode_algorithm("sha512"), do: {:ok, :sha512}
  defp decode_algorithm(_algorithm), do: :error

  defp digest_size(:sha256), do: 32
  defp digest_size(:sha512), do: 64
end
