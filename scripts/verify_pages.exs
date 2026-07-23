defmodule Obscura.PagesVerifier do
  @moduledoc false

  @root "_site"
  @slug "protecting-pii-in-elixir"
  @article_dir Path.join([@root, "blog", @slug])
  @article Path.join(@article_dir, "index.html")
  @canonical "https://hfiguera.github.io/obscura/blog/#{@slug}/"
  @site_url "https://hfiguera.github.io/obscura/"

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
    assert_analytics_beacon(article)

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

    assert_local_references_exist(article, @article_dir)
    verify_root_redirect()
    verify_privacy()
    verify_sitemap()

    IO.puts("Verified #{@canonical}")
  end

  defp verify_root_redirect do
    index = File.read!(Path.join(@root, "index.html"))

    assert_contains(index, ~s(http-equiv="refresh"))
    assert_analytics_beacon(index)
    assert_local_references_exist(index, @root)
  end

  defp verify_privacy do
    privacy_dir = Path.join(@root, "privacy")
    html = File.read!(Path.join(privacy_dir, "index.html"))

    assert_contains(html, ~s(<link rel="canonical" href="#{@site_url}privacy/">))
    assert_contains(html, "Analytics privacy")
    assert_contains(html, "does not use cookies or local storage")
    assert_contains(html, "does not log URL query strings")
    assert_analytics_beacon(html)
    assert_local_references_exist(html, privacy_dir)
  end

  defp verify_sitemap do
    sitemap = File.read!(Path.join(@root, "sitemap.xml"))
    assert_contains(sitemap, "#{@site_url}privacy/")
  end

  defp assert_analytics_beacon(html) do
    beacon = "https://static.cloudflareinsights.com/beacon.min.js"
    token = ~s("token":"f968ea7d6e614cc9a3e2d537ced91a10")

    assert_contains(html, beacon)
    assert_contains(html, token)

    if length(:binary.matches(html, beacon)) != 1 do
      raise "expected exactly one Cloudflare Web Analytics beacon"
    end
  end

  defp assert_local_references_exist(html, base_dir) do
    ~r/(?:href|src)="([^"]+)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&external_or_special?/1)
    |> Enum.each(fn reference ->
      reference = reference |> String.split("#", parts: 2) |> hd()
      path = Path.expand(reference, base_dir)

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
