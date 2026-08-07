defmodule Obscura.PagesVerifier do
  @moduledoc false

  @root "_site"
  @site_url "https://hfiguera.github.io/obscura/"
  @articles [
    %{
      slug: "privacy-safe-phoenix-request-logging",
      expected_media: ["phoenix-safe-logging-boundary.png"]
    },
    %{
      slug: "making-pii-detection-faster-without-keeping-input-alive",
      expected_media: ["fast-profile-binary-ownership.png"]
    },
    %{
      slug: "model-card-is-not-a-license",
      expected_media: ["model-licensing-stack.jpg"]
    },
    %{
      slug: "running-obscura-on-nvidia-exla",
      expected_media: [
        "obscura-linux-nvidia-validation-path.png",
        "obscura-exla-cuda-proof.png",
        "obscura-t4-warm-latency.png"
      ]
    },
    %{
      slug: "protecting-pii-in-elixir",
      expected_media: [
        "obscura-workbench-fast-detection.jpg",
        "obscura-workbench-vault-llm.jpg",
        "obscura-pii-boundary-workflow.gif",
        "obscura-pii-boundary-workflow.mp4"
      ]
    }
  ]

  def run do
    Enum.each(@articles, &verify_article/1)
    verify_index()
    verify_feed_and_sitemap()
    verify_privacy()

    assert_file("assets/site.css")
    assert_file("assets/syntax.css")
    assert_file("feed.xml")
    assert_file("sitemap.xml")
    assert_file(".nojekyll")

    IO.puts("Verified #{length(@articles)} Obscura articles and the blog index")
  end

  defp verify_article(article) do
    article_dir = article_dir(article)
    html = File.read!(Path.join(article_dir, "index.html"))
    canonical = canonical_url(article)

    assert_contains(html, ~s(<link rel="canonical" href="#{canonical}">))
    assert_contains(html, ~s(<meta property="og:image"))
    assert_contains(html, ~s(<meta name="twitter:card" content="summary_large_image">))
    assert_contains(html, ~s(<script type="application/ld+json">))
    assert_contains(html, ~s(<article>))
    assert_contains(html, "By Humberto Figuera")
    assert_contains(html, ~s(href="https://x.com/hfiguera"))
    assert_contains(html, ~s(href="https://github.com/hfiguera"))
    refute_contains(html, "TODO(media)")
    refute_contains(html, "localhost")
    refute_contains(html, "cloudspaces.litng.ai")
    assert_analytics_beacon(html)

    Enum.each(article.expected_media, fn filename ->
      media_path = Path.join([article_dir, "media", article.slug, filename])
      assert_media_signature(media_path)
      assert_contains(html, filename)
    end)

    case article.slug do
      "privacy-safe-phoenix-request-logging" ->
        assert_contains(html, ~s(<code class="makeup elixir" translate="no">))
        assert_contains(html, "Obscura.Phoenix.Logger")
        assert_contains(html, "[FILTERED METHOD]")
        assert_contains(html, "phoenix-safe-logging-boundary.png")

      "protecting-pii-in-elixir" ->
        assert_contains(html, ~s(<code class="makeup elixir" translate="no">))
        assert_contains(html, ~s(<span class="kd">def</span>))
        assert_contains(html, "obscura-pii-boundary-workflow.gif")
        assert_contains(html, "obscura-pii-boundary-workflow.mp4")

      "running-obscura-on-nvidia-exla" ->
        assert_contains(html, ~s(<code class="makeup bash" translate="no">))
        assert_contains(html, ~s(<span class="kd">export</span>))

      "model-card-is-not-a-license" ->
        assert_contains(html, ~s(<code class="makeup elixir" translate="no">))
        assert_contains(html, "requires_ldc_for_profit_membership")
        assert_contains(html, "model-licensing-stack.jpg")

      "making-pii-detection-faster-without-keeping-input-alive" ->
        assert_contains(html, ~s(<code class="makeup elixir" translate="no">))
        assert_contains(html, "referenced_byte_size")
        assert_contains(html, "fast-profile-binary-ownership.png")
    end

    assert_local_references_exist(html, article_dir)
    IO.puts("Verified #{canonical}")
  end

  defp verify_index do
    index = File.read!(Path.join(@root, "index.html"))

    assert_contains(index, ~s(<link rel="canonical" href="#{@site_url}">))
    assert_contains(index, "Building practical PII protection in Elixir")
    refute_contains(index, ~s(http-equiv="refresh"))

    Enum.each(@articles, fn article ->
      assert_contains(index, "blog/#{article.slug}/")
    end)

    assert_analytics_beacon(index)
    assert_local_references_exist(index, @root)
  end

  defp verify_feed_and_sitemap do
    feed = File.read!(Path.join(@root, "feed.xml"))
    sitemap = File.read!(Path.join(@root, "sitemap.xml"))

    Enum.each(@articles, fn article ->
      canonical = canonical_url(article)
      assert_contains(feed, canonical)
      assert_contains(sitemap, canonical)
    end)

    assert_contains(sitemap, "#{@site_url}privacy/")
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

  defp assert_media_signature(path) do
    case Path.extname(path) do
      extension when extension in [".jpg", ".jpeg"] -> assert_magic(path, <<0xFF, 0xD8>>)
      ".png" -> assert_magic(path, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>)
      ".gif" -> assert_magic(path, "GIF89a")
      ".mp4" -> assert_ftyp(path)
      extension -> raise "unsupported media extension #{extension} for #{path}"
    end
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

  defp article_dir(article), do: Path.join([@root, "blog", article.slug])
  defp canonical_url(article), do: @site_url <> "blog/#{article.slug}/"
end

Obscura.PagesVerifier.run()
