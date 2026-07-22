defmodule Obscura.PagesVerifier do
  @moduledoc false

  @root "_site"
  @slug "protecting-pii-in-elixir"
  @article_dir Path.join([@root, "blog", @slug])
  @article Path.join(@article_dir, "index.html")
  @canonical "https://hfiguera.github.io/obscura/blog/#{@slug}/"

  def run do
    article = File.read!(@article)

    assert_contains(article, ~s(<link rel="canonical" href="#{@canonical}">))
    assert_contains(article, ~s(<meta property="og:image"))
    assert_contains(article, ~s(<meta name="twitter:card" content="summary_large_image">))
    assert_contains(article, ~s(<script type="application/ld+json">))
    assert_contains(article, ~s(<article>))
    assert_contains(article, ~s(<code class="makeup elixir" translate="no">))
    assert_contains(article, ~s(<span class="kd">def</span>))
    assert_contains(article, "obscura-pii-boundary-workflow.gif")
    assert_contains(article, "obscura-pii-boundary-workflow.mp4")
    refute_contains(article, "TODO(media)")
    refute_contains(article, "localhost")

    assert_file("assets/site.css")
    assert_file("assets/syntax.css")
    assert_file("feed.xml")
    assert_file("sitemap.xml")
    assert_file(".nojekyll")

    media_dir = Path.join(@article_dir, "media/#{@slug}")
    assert_magic(Path.join(media_dir, "obscura-workbench-fast-detection.jpg"), <<0xFF, 0xD8>>)
    assert_magic(Path.join(media_dir, "obscura-workbench-vault-llm.jpg"), <<0xFF, 0xD8>>)
    assert_magic(Path.join(media_dir, "obscura-pii-boundary-workflow.gif"), "GIF89a")
    assert_ftyp(Path.join(media_dir, "obscura-pii-boundary-workflow.mp4"))

    assert_local_references_exist(article)
    IO.puts("Verified #{@canonical}")
  end

  defp assert_local_references_exist(article) do
    ~r/(?:href|src)="([^"]+)"/
    |> Regex.scan(article, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&external_or_special?/1)
    |> Enum.each(fn reference ->
      reference = reference |> String.split("#", parts: 2) |> hd()
      path = Path.expand(reference, @article_dir)

      unless File.exists?(path) do
        raise "missing local page reference #{reference} (resolved to #{path})"
      end
    end)
  end

  defp external_or_special?(reference) do
    String.starts_with?(reference, ["http://", "https://", "#", "mailto:"])
  end

  defp assert_file(relative) do
    path = Path.join(@root, relative)
    unless File.exists?(path), do: raise("missing generated file #{path}")
  end

  defp assert_magic(path, expected) do
    actual = path |> File.read!() |> binary_part(0, byte_size(expected))
    unless actual == expected, do: raise("unexpected file signature for #{path}")
  end

  defp assert_ftyp(path) do
    <<_size::binary-size(4), "ftyp", _rest::binary>> = File.read!(path)
  rescue
    MatchError -> raise "unexpected MP4 signature for #{path}"
  end

  defp assert_contains(content, expected) do
    unless String.contains?(content, expected), do: raise("missing #{inspect(expected)}")
  end

  defp refute_contains(content, unexpected) do
    if String.contains?(content, unexpected), do: raise("unexpected #{inspect(unexpected)}")
  end
end

Obscura.PagesVerifier.run()
