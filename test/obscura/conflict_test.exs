defmodule Obscura.ConflictTest do
  use ExUnit.Case, async: true

  alias Obscura.Conflict

  test "default resolver removes exact duplicates and contained lower-score same entity spans" do
    spans = [
      span(:email, 0, 20, 0.8),
      span(:email, 0, 20, 0.6),
      span(:email, 2, 10, 0.7)
    ]

    assert [kept] = Conflict.resolve(spans, :default)
    assert kept.start == 0
    assert kept.end == 20
    assert kept.score == 0.8
    assert kept.metadata.conflict_policy == :presidio_like
    assert kept.metadata.conflict_dropped_count == 2
    assert kept.metadata.conflict_reason == :exact_duplicate_contained_or_structured_precedence
  end

  test "default resolver lets deterministic structured PII beat overlapping broad model spans" do
    spans = [
      span(:email, 10, 26, 0.95),
      span(:organization, 10, 26, 0.99, %{model_label: "B-ORG"})
    ]

    assert [kept] = Conflict.resolve(spans, :default)
    assert kept.entity == :email
    assert kept.metadata.conflict_policy == :presidio_like
    assert kept.metadata.conflict_dropped_count == 1
    assert kept.metadata.conflict_reason == :exact_duplicate_contained_or_structured_precedence
  end

  test "default resolver lets deterministic structured PII beat overlapping structured model spans" do
    spans = [
      span(:phone, 10, 22, 0.9),
      span(:phone, 10, 22, 0.99, %{model_label: "phone number", source: :gliner_ortex})
    ]

    assert [kept] = Conflict.resolve(spans, :default)
    assert kept.entity == :phone
    refute Map.has_key?(kept.metadata, :model_label)
    assert kept.metadata.conflict_policy == :presidio_like
  end

  test "default resolver keeps nested different-entity spans" do
    spans = [
      span(:url, 0, 24, 0.7),
      span(:domain, 8, 19, 0.9)
    ]

    assert [:url, :domain] = spans |> Conflict.resolve(:default) |> Enum.map(& &1.entity)
  end

  test "aggressive resolver preserves old non-overlapping behavior" do
    spans = [
      span(:url, 0, 24, 0.7),
      span(:domain, 8, 19, 0.9)
    ]

    assert [kept] = Conflict.resolve(spans, :aggressive)
    assert kept.entity == :url
    assert kept.metadata.conflict_policy == :prefer_longer
  end

  defp span(entity, start, end_offset, score, metadata \\ %{}) do
    %{
      entity: entity,
      start: start,
      end: end_offset,
      byte_start: start,
      byte_end: end_offset,
      score: score,
      metadata: metadata
    }
  end
end
