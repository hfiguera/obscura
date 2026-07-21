defmodule Obscura.Fixtures.FixtureLoaderTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.Loader

  test "loads all fixture suites" do
    assert {:ok, all} = Loader.load_all()
    assert {:ok, analyzer} = Loader.load_all(suite: :analyzer)
    assert {:ok, operator} = Loader.load_all(suite: :operator)
    assert {:ok, structured} = Loader.load_all(suite: :structured)
    assert {:ok, context} = Loader.load_all(suite: :context)
    assert {:ok, vault} = Loader.load_all(suite: :vault)
    assert {:ok, llm} = Loader.load_all(suite: :llm)
    assert {:ok, stream} = Loader.load_all(suite: :stream)
    assert {:ok, nlp} = Loader.load_all(suite: :nlp)
    assert {:ok, ner} = Loader.load_all(suite: :ner)
    assert {:ok, accuracy} = Loader.load_all(suite: :accuracy)

    assert length(all) ==
             length(analyzer) + length(operator) + length(structured) + length(context) +
               length(vault) + length(llm) + length(stream) + length(nlp) + length(ner)

    assert Enum.all?(analyzer, &(&1.kind == :analyzer))
    assert Enum.all?(operator, &(&1.kind == :operator))
    assert Enum.all?(structured, &(&1.kind == :structured))
    assert Enum.all?(context, &(&1.kind == :context))
    assert Enum.all?(vault, &(&1.kind == :vault))
    assert Enum.all?(llm, &(&1.kind == :llm))
    assert Enum.all?(stream, &(&1.kind == :stream))
    assert Enum.all?(nlp, &(&1.kind == :nlp))
    assert Enum.all?(ner, &(&1.kind == :ner))
    assert Enum.all?(accuracy, &(&1.profile == :deterministic_plus))
    assert Enum.all?(accuracy, &(&1.kind == :analyzer))
  end

  test "fixture files are sorted and suite-filtered" do
    analyzer_files = Loader.fixture_files(suite: :analyzer)
    operator_files = Loader.fixture_files(suite: :operator)
    structured_files = Loader.fixture_files(suite: :structured)
    context_files = Loader.fixture_files(suite: :context)
    vault_files = Loader.fixture_files(suite: :vault)
    llm_files = Loader.fixture_files(suite: :llm)
    stream_files = Loader.fixture_files(suite: :stream)
    nlp_files = Loader.fixture_files(suite: :nlp)
    ner_files = Loader.fixture_files(suite: :ner)
    accuracy_files = Loader.fixture_files(suite: :accuracy)

    assert analyzer_files == Enum.sort(analyzer_files)
    assert operator_files == Enum.sort(operator_files)
    assert structured_files == Enum.sort(structured_files)
    assert context_files == Enum.sort(context_files)
    assert vault_files == Enum.sort(vault_files)
    assert llm_files == Enum.sort(llm_files)
    assert stream_files == Enum.sort(stream_files)
    assert nlp_files == Enum.sort(nlp_files)
    assert ner_files == Enum.sort(ner_files)
    assert accuracy_files == Enum.sort(accuracy_files)
    assert Enum.all?(analyzer_files, &String.contains?(&1, "fixtures/analyzer/"))
    assert Enum.all?(operator_files, &String.contains?(&1, "fixtures/operator/"))
    assert Enum.all?(structured_files, &String.contains?(&1, "fixtures/structured/"))
    assert Enum.all?(context_files, &String.contains?(&1, "fixtures/context/"))
    assert Enum.all?(vault_files, &String.contains?(&1, "fixtures/vault/"))
    assert Enum.all?(llm_files, &String.contains?(&1, "fixtures/llm/"))
    assert Enum.all?(stream_files, &String.contains?(&1, "fixtures/stream/"))
    assert Enum.all?(nlp_files, &String.contains?(&1, "fixtures/nlp/"))
    assert Enum.all?(ner_files, &String.contains?(&1, "fixtures/ner/"))
    assert Enum.all?(accuracy_files, &String.contains?(&1, "fixtures/accuracy/"))
    refute Enum.any?(Loader.fixture_files(), &String.contains?(&1, "fixtures/accuracy/"))
  end
end
