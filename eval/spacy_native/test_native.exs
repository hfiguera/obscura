ExUnit.start()

defmodule Obscura.SpacyNative.Test do
  use ExUnit.Case, async: false
  alias Obscura.SpacyNative.{Recognizer, Worker}

  test "UTF-8 offsets survive the real analyzer and structured spans take precedence" do
    {:ok, worker} = Worker.start_link()

    try do
      text = "José García lives in São Paulo. Email Alice at alice@example.com."

      {:ok, results} =
        Obscura.analyze(text,
          profile: :deterministic_plus,
          include_text: false,
          recognizers: [{Recognizer, worker: worker}]
        )

      person = Enum.find(results, &(&1.entity == :person and &1.byte_start == 0))

      assert binary_part(text, person.byte_start, person.byte_end - person.byte_start) ==
               "José García"

      email = Enum.find(results, &(&1.entity == :email))

      assert binary_part(text, email.byte_start, email.byte_end - email.byte_start) ==
               "alice@example.com"

      refute Enum.any?(results, fn r ->
               r.entity == :person and r.byte_start < email.byte_end and
                 email.byte_start < r.byte_end
             end)

      assert Worker.ready(worker)["python_runtime"] == false
    after
      GenServer.stop(worker)
    end
  end

  test "concurrent callers serialize safely through a single worker" do
    {:ok, worker} = Worker.start_link()

    try do
      rows = ["Alice Smith lives in London.", "José García lives in São Paulo.", ""]

      expected =
        Enum.map(rows, fn text ->
          {:ok, r} = Worker.predict(worker, text)
          r["predictions"]
        end)

      actual =
        rows
        |> Task.async_stream(fn text ->
          {:ok, r} = Worker.predict(worker, text)
          r["predictions"]
        end)
        |> Enum.map(fn {:ok, r} -> r end)

      assert actual == expected
    after
      GenServer.stop(worker)
    end
  end

  test "request limits fail and the worker remains usable" do
    {:ok, worker} = Worker.start_link()

    try do
      assert {:error, :native_input_limit} =
               Worker.predict(worker, String.duplicate("x", 1_048_577))

      assert {:ok, %{"predictions" => []}} = Worker.predict(worker, "")
    after
      GenServer.stop(worker)
    end
  end

  test "unavailable worker propagates an analyzer error" do
    {:ok, worker} = Worker.start_link()
    GenServer.stop(worker)

    assert {:error, _} =
             Obscura.analyze("Alice Smith lives in London.",
               profile: :deterministic_plus,
               recognizers: [{Recognizer, worker: worker}]
             )
  end
end
