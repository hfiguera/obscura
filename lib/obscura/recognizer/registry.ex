defmodule Obscura.Recognizer.Registry do
  @moduledoc """
  Static Phase 1 recognizer registry.
  """

  alias Obscura.Recognizer.DenyList
  alias Obscura.Recognizer.PatternDefinition

  @recognizers %{
    email: Obscura.Recognizer.Email,
    phone: Obscura.Recognizer.Phone,
    credit_card: Obscura.Recognizer.CreditCard,
    us_ssn: Obscura.Recognizer.USSSN,
    iban: Obscura.Recognizer.IBAN,
    ip_address: Obscura.Recognizer.IPAddress,
    url: Obscura.Recognizer.URL,
    domain: Obscura.Recognizer.Domain,
    date_time: Obscura.Recognizer.DateTime,
    person: Obscura.Recognizer.PersonName,
    location: Obscura.Recognizer.Location,
    street_address: Obscura.Recognizer.Address,
    title: Obscura.Recognizer.Title
  }

  @special_recognizers %{
    gliner: Obscura.Recognizer.GLiNER,
    ner: Obscura.Recognizer.NER,
    privacy_filter_native: Obscura.Recognizer.PrivacyFilter.Native
  }

  @doc """
  Returns recognizer modules for the requested entities.
  """
  @spec fetch([atom()], keyword()) :: {:ok, [module() | struct() | tuple()]} | {:error, term()}
  def fetch(entities, opts \\ []) when is_list(entities) do
    custom = Keyword.get(opts, :recognizers, [])
    deny_lists = Keyword.get(opts, :deny_lists, [])
    built_ins? = Keyword.get(opts, :built_ins, true)

    with {:ok, custom_recognizers} <- normalize_custom_recognizers(custom) do
      recognizers =
        built_ins_for_entities(entities, built_ins?) ++
          custom_recognizers ++ deny_recognizers(deny_lists)

      supported = Enum.flat_map(recognizers, &supported_entities/1)
      unsupported = Enum.reject(entities, &(&1 in supported))

      if unsupported == [] do
        {:ok, recognizers |> filter_by_entities(entities) |> Enum.uniq_by(&dedupe_key/1)}
      else
        {:error, {:unsupported_entities, unsupported}}
      end
    end
  end

  @doc """
  Returns built-in recognizer modules.
  """
  @spec built_ins() :: [module()]
  def built_ins do
    @recognizers
    |> Enum.sort_by(fn {entity, _module} -> entity end)
    |> Enum.map(fn {_entity, module} -> module end)
  end

  @doc """
  Lists Phase 1 supported entities.
  """
  @spec entities() :: [atom()]
  def entities do
    @recognizers
    |> Enum.map(fn {entity, _recognizer} -> entity end)
    |> Enum.sort()
  end

  @doc """
  Normalizes per-call recognizer specs.
  """
  @spec normalize_recognizers([atom() | module() | struct() | tuple()]) :: [
          module() | struct() | tuple()
        ]
  def normalize_recognizers(recognizers) when is_list(recognizers) do
    case normalize_custom_recognizers(recognizers) do
      {:ok, recognizers} -> recognizers
      {:error, _reason} -> []
    end
  end

  @doc """
  Returns supported entities for a recognizer module or data-backed recognizer.
  """
  @spec supported_entities(module() | struct() | tuple()) :: [atom()]
  def supported_entities(%PatternDefinition{} = definition) do
    PatternDefinition.supported_entities(definition)
  end

  def supported_entities({:deny_list, deny_lists}) do
    DenyList.supported_entities(deny_lists)
  end

  def supported_entities({module, _opts}) when is_atom(module) do
    supported_entities(module)
  end

  def supported_entities(module) when is_atom(module) do
    Code.ensure_loaded(module)

    cond do
      function_exported?(module, :supported_entities, 0) -> module.supported_entities()
      function_exported?(module, :entity, 0) -> [module.entity()]
      true -> []
    end
  end

  defp built_ins_for_entities(_entities, false), do: []

  defp built_ins_for_entities(entities, true) do
    entities
    |> Enum.filter(&Map.has_key?(@recognizers, &1))
    |> Enum.uniq()
    |> Enum.map(&Map.fetch!(@recognizers, &1))
  end

  defp expand_default_recognizers(recognizers) do
    if :default in recognizers do
      recognizers
      |> Enum.reject(&(&1 == :default))
      |> Kernel.++(built_ins())
    else
      recognizers
    end
  end

  defp normalize_recognizer({name, opts}) when is_atom(name) and is_list(opts) do
    case Map.fetch(@special_recognizers, name) do
      {:ok, module} -> [{module, opts}]
      :error -> [{name, opts}]
    end
  end

  defp normalize_recognizer(name) when is_atom(name) do
    case Map.fetch(@special_recognizers, name) do
      {:ok, module} -> [module]
      :error -> [name]
    end
  end

  defp normalize_recognizer(recognizer), do: [recognizer]

  defp normalize_custom_recognizers(recognizers) do
    recognizers
    |> expand_default_recognizers()
    |> Enum.flat_map(&normalize_recognizer/1)
    |> Enum.reduce_while({:ok, []}, fn recognizer, {:ok, acc} ->
      if valid_recognizer?(recognizer) do
        {:cont, {:ok, acc ++ [recognizer]}}
      else
        {:halt, {:error, {:unknown_recognizer, recognizer}}}
      end
    end)
  end

  defp deny_recognizers([]), do: []
  defp deny_recognizers(deny_lists), do: [{:deny_list, deny_lists}]

  defp filter_by_entities(recognizers, entities) do
    Enum.filter(recognizers, fn recognizer ->
      Enum.any?(supported_entities(recognizer), &(&1 in entities))
    end)
  end

  defp valid_recognizer?(%PatternDefinition{}), do: true

  defp valid_recognizer?({module, opts}) when is_atom(module) and is_list(opts) do
    valid_recognizer?(module)
  end

  defp valid_recognizer?(module) when is_atom(module) do
    Code.ensure_loaded(module)
    function_exported?(module, :analyze, 2)
  end

  defp valid_recognizer?(_recognizer), do: false

  defp dedupe_key(%PatternDefinition{name: name}),
    do: {:pattern_definition, name}

  defp dedupe_key({:deny_list, _deny_lists}), do: :deny_list
  defp dedupe_key({module, _opts}), do: module
  defp dedupe_key(module), do: module
end
