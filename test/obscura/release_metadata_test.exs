defmodule Obscura.ReleaseMetadataTest do
  use ExUnit.Case, async: true

  @source_url "https://github.com/hfiguera/obscura"
  @security_url "#{@source_url}/security/advisories/new"

  test "project and package metadata point to the canonical repository" do
    project = Mix.Project.config()
    package = Keyword.fetch!(project, :package)

    assert project[:version] == "0.1.1"
    assert project[:source_url] == @source_url
    assert project[:homepage_url] == @source_url
    assert package[:links]["GitHub"] == @source_url
    assert package[:links]["Security"] == @security_url
    assert package[:licenses] == ["MIT"]
  end

  test "package files include legal and security notices without repository-only assets" do
    files = Mix.Project.config() |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)

    for required <- ~w(CHANGELOG.md LICENSE SECURITY.md THIRD_PARTY_NOTICES.md) do
      assert required in files
    end

    refute "eval" in files
    refute "fixtures" in files
    refute "vendor" in files
  end
end
