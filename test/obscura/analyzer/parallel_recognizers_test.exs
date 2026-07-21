defmodule Obscura.Analyzer.ParallelRecognizersTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Options
  alias Obscura.Analyzer.Result

  defmodule BlockingPersonRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :blocking_person

    @impl true
    def supported_entities, do: [:person]

    @impl true
    def analyze(_text, opts) do
      wait_for_continue(opts, :person)

      [
        %Result{
          entity: :person,
          start: 0,
          end: 5,
          byte_start: 0,
          byte_end: 5,
          score: 1.0,
          text: "Alice",
          source_entity: "PERSON",
          recognizer: :blocking_person
        }
      ]
    end

    @impl true
    def analyze_many(texts, opts) do
      wait_for_continue(opts, :person)
      Enum.map(texts, fn _text -> analyze_many_result(:person) end)
    end

    defp wait_for_continue(opts, entity) do
      parent = Keyword.fetch!(opts, :test_parent)
      ref = Keyword.fetch!(opts, :test_ref)
      send(parent, {ref, :started, entity, self()})

      receive do
        {^ref, :continue} -> :ok
      after
        5_000 -> raise "parallel recognizer test timed out"
      end
    end

    defp analyze_many_result(:person) do
      [
        %Result{
          entity: :person,
          start: 0,
          end: 5,
          byte_start: 0,
          byte_end: 5,
          score: 1.0,
          text: "Alice",
          source_entity: "PERSON",
          recognizer: :blocking_person
        }
      ]
    end
  end

  defmodule BlockingLocationRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :blocking_location

    @impl true
    def supported_entities, do: [:location]

    @impl true
    def analyze(_text, opts) do
      wait_for_continue(opts, :location)

      [
        %Result{
          entity: :location,
          start: 6,
          end: 12,
          byte_start: 6,
          byte_end: 12,
          score: 1.0,
          text: "Denver",
          source_entity: "LOCATION",
          recognizer: :blocking_location
        }
      ]
    end

    @impl true
    def analyze_many(texts, opts) do
      wait_for_continue(opts, :location)
      Enum.map(texts, fn _text -> analyze_many_result(:location) end)
    end

    defp wait_for_continue(opts, entity) do
      parent = Keyword.fetch!(opts, :test_parent)
      ref = Keyword.fetch!(opts, :test_ref)
      send(parent, {ref, :started, entity, self()})

      receive do
        {^ref, :continue} -> :ok
      after
        5_000 -> raise "parallel recognizer test timed out"
      end
    end

    defp analyze_many_result(:location) do
      [
        %Result{
          entity: :location,
          start: 6,
          end: 12,
          byte_start: 6,
          byte_end: 12,
          score: 1.0,
          text: "Denver",
          source_entity: "LOCATION",
          recognizer: :blocking_location
        }
      ]
    end
  end

  test "parallel_recognizers option defaults to false and validates booleans" do
    assert {:ok, %{parallel_recognizers: false}} = Options.new([])
    assert {:ok, %{parallel_recognizers: true}} = Options.new(parallel_recognizers: true)

    assert {:error, {:invalid_boolean, :parallel_recognizers}} =
             Options.new(parallel_recognizers: :yes)
  end

  test "analyze starts recognizers concurrently when parallel_recognizers is enabled" do
    ref = make_ref()
    parent = self()

    task =
      Task.async(fn ->
        Obscura.analyze("Alice Denver",
          entities: [:person, :location],
          recognizers: recognizers(parent, ref),
          parallel_recognizers: true,
          recognizer_timeout: 2_000
        )
      end)

    started = receive_started(ref, 2)
    Enum.each(started, fn {_entity, pid} -> send(pid, {ref, :continue}) end)

    assert {:ok, results} = Task.await(task)
    assert Enum.map(results, & &1.entity) == [:person, :location]
  end

  test "analyze_many starts recognizers concurrently when parallel_recognizers is enabled" do
    ref = make_ref()
    parent = self()

    task =
      Task.async(fn ->
        Obscura.analyze_many(["Alice Denver", "Alice Denver"],
          entities: [:person, :location],
          recognizers: recognizers(parent, ref),
          parallel_recognizers: true,
          recognizer_timeout: 2_000
        )
      end)

    started = receive_started(ref, 2)
    Enum.each(started, fn {_entity, pid} -> send(pid, {ref, :continue}) end)

    assert {:ok, [first, second]} = Task.await(task)
    assert Enum.map(first, & &1.entity) == [:person, :location]
    assert Enum.map(second, & &1.entity) == [:person, :location]
  end

  defp recognizers(parent, ref) do
    [
      {BlockingPersonRecognizer, test_parent: parent, test_ref: ref},
      {BlockingLocationRecognizer, test_parent: parent, test_ref: ref}
    ]
  end

  defp receive_started(ref, count) do
    Enum.map(1..count, fn _index ->
      receive do
        {^ref, :started, entity, pid} -> {entity, pid}
      after
        2_000 -> flunk("expected #{count} recognizers to start")
      end
    end)
  end
end
