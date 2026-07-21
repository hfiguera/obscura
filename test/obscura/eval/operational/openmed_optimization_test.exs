defmodule Obscura.Eval.Operational.OpenMedOptimizationTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Operational.OpenMedOptimization

  test "declares the controlled matrix and measured default buckets" do
    assert OpenMedOptimization.variants() == [
             :baseline,
             :bucketing,
             :raw_logits,
             :combined
           ]

    assert OpenMedOptimization.default_buckets() == [192, 256, 384, 512, 768]
    assert OpenMedOptimization.default_bucket_threshold() == 129
  end
end
