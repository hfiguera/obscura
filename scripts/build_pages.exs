defmodule Obscura.PagesBuilder do
  @moduledoc false

  @output_root "_site"
  @stylesheet_source "docs/blog/site.css"
  @site_url "https://hfiguera.github.io/obscura/"
  @analytics_token "f968ea7d6e614cc9a3e2d537ced91a10"
  @author_name "Humberto Figuera"
  @author_x_url "https://x.com/hfiguera"
  @author_github_url "https://github.com/hfiguera"
  @perplexity_published_on "2026-09-02"
  @perplexity_rss_date "Wed, 02 Sep 2026 00:00:00 GMT"
  @presidio_published_on "2026-08-21"
  @presidio_rss_date "Fri, 21 Aug 2026 00:00:00 GMT"
  @agent_published_on "2026-08-15"
  @agent_rss_date "Sat, 15 Aug 2026 00:00:00 GMT"
  @realtime_published_on "2026-08-12"
  @realtime_rss_date "Wed, 12 Aug 2026 00:00:00 GMT"
  @initial_published_on "2026-07-22"
  @initial_rss_date "Wed, 22 Jul 2026 00:00:00 GMT"
  @nvidia_published_on "2026-07-24"
  @nvidia_rss_date "Fri, 24 Jul 2026 00:00:00 GMT"
  @model_card_published_on "2026-07-29"
  @model_card_rss_date "Wed, 29 Jul 2026 00:00:00 GMT"
  @fast_published_on "2026-08-05"
  @fast_rss_date "Wed, 05 Aug 2026 00:00:00 GMT"
  @latest_published_on "2026-08-07"
  @latest_rss_date "Fri, 07 Aug 2026 00:00:00 GMT"
  @media_extensions [".gif", ".jpg", ".jpeg", ".mp4", ".png", ".webp"]

  @articles [
    %{
      slug: "an-ai-hybrid-improved-pii-detection-we-still-did-not-ship-it",
      title: "An AI Hybrid Improved PII Detection. We Still Did Not Ship It.",
      description:
        "An engineering case study about testing Perplexity's PII model, finding an apparent hybrid win, and using incremental error analysis to reject a new runtime dependency.",
      published_on: @perplexity_published_on,
      rss_date: @perplexity_rss_date,
      version: "0.1.3",
      og_image: "incremental-error-analysis-decision.png"
    },
    %{
      slug: "should-pii-detection-live-inside-the-beam",
      title: "Should PII Detection Live Inside the BEAM?",
      description:
        "A practical comparison of native Obscura integration and a separately operated Presidio privacy service for Elixir applications.",
      published_on: @presidio_published_on,
      rss_date: @presidio_rss_date,
      version: "0.1.3",
      og_image: "presidio-obscura-boundary-choice.png"
    },
    %{
      slug: "the-agent-needs-identity-the-model-does-not",
      title: "The Agent Needs Identity. The Model Does Not.",
      description:
        "An Elixir engineering case study about keeping customer identity inside a Phoenix application while Jido, OpenAI, and trusted tools operate on stable Obscura pseudonyms.",
      published_on: @agent_published_on,
      rss_date: @agent_rss_date,
      og_image: "obscura-jido-agent-boundary.png"
    },
    %{
      slug: "privacy-safe-phoenix-realtime-logging",
      title: "Privacy-Safe Phoenix Socket and Channel Logging Without Exposing Payloads",
      description:
        "An engineering case study about restoring Phoenix socket and channel visibility with omitted payloads, static labels, bounded redaction, and explicit correlation.",
      published_on: @realtime_published_on,
      rss_date: @realtime_rss_date,
      og_image: "phoenix-realtime-logging-boundary.png"
    },
    %{
      slug: "privacy-safe-phoenix-request-logging",
      title: "Privacy-Safe Phoenix Request Logging Without Changing Controller Params",
      description:
        "An engineering case study about closing the gap between redacted Phoenix assigns and default request logging without changing controller input.",
      published_on: @latest_published_on,
      rss_date: @latest_rss_date,
      og_image: "phoenix-safe-logging-boundary.png"
    },
    %{
      slug: "making-pii-detection-faster-without-keeping-input-alive",
      title: "Making PII Detection Faster Without Keeping the Input Alive",
      description:
        "An Elixir engineering case study about optimizing Obscura's fast profile while preserving output compatibility and proving BEAM binary ownership.",
      published_on: @fast_published_on,
      rss_date: @fast_rss_date,
      og_image: "fast-profile-binary-ownership.png"
    },
    %{
      slug: "model-card-is-not-a-license",
      title: "A Model Card Is Not a License: What We Learned Shipping Local NER in Obscura",
      description:
        "An engineering case study about base-model licenses, fine-tuning data agreements, checkpoint provenance, and the licensing changes shipped in Obscura 0.1.1.",
      published_on: @model_card_published_on,
      rss_date: @model_card_rss_date,
      og_image: "model-licensing-stack.jpg"
    },
    %{
      slug: "running-obscura-on-nvidia-exla",
      title: "Running Obscura on an NVIDIA GPU with Elixir, EXLA, and Lightning AI",
      description:
        "A reproducible field report for validating Obscura, Nx, and EXLA on a Linux NVIDIA Tesla T4 without owning the hardware.",
      published_on: @nvidia_published_on,
      rss_date: @nvidia_rss_date,
      og_image: "obscura-linux-nvidia-validation-path.png"
    },
    %{
      slug: "protecting-pii-in-elixir",
      title: "Protecting PII in Elixir Before It Reaches Logs, APIs, and LLMs",
      description:
        "A practical guide to detecting, redacting, and pseudonymizing PII at Elixir application boundaries with Obscura.",
      published_on: @initial_published_on,
      rss_date: @initial_rss_date,
      og_image: "obscura-workbench-fast-detection.jpg"
    }
  ]

  def run do
    start_highlighters()

    File.rm_rf!(@output_root)
    File.mkdir_p!(Path.join(@output_root, "assets"))

    Enum.each(@articles, &build_article/1)
    write_index()
    write_privacy()
    write_feed()
    write_sitemap()
    copy_shared_assets()

    File.write!(Path.join(@output_root, ".nojekyll"), "")
    IO.puts("Built #{length(@articles)} Obscura articles in #{@output_root}")
  end

  defp start_highlighters do
    {:ok, _applications} = Application.ensure_all_started(:makeup_elixir)

    Application.put_env(
      :makeup_syntect,
      :register_for_languages,
      ["bourne_again_shell_bash"]
    )

    {:ok, _applications} = Application.ensure_all_started(:makeup_syntect)

    bash_lexer = Makeup.Registry.fetch_lexer_by_name!("bourne_again_shell_bash")
    Makeup.Registry.register_lexer_with_name("bash", bash_lexer)
  end

  defp build_article(article) do
    article_output = article_output(article)
    File.mkdir_p!(article_output)

    markdown = File.read!(article_source(article))
    rendered_article = render_markdown(markdown, article)

    write_article(article, rendered_article)
    copy_article_media(article)
  end

  defp render_markdown(markdown, article) do
    ast = ExDoc.Markdown.Earmark.to_ast(markdown, file: article_source(article))

    ast
    |> ExDoc.DocAST.highlight(ExDoc.Language.Elixir)
    |> ExDoc.DocAST.to_html()
    |> rewrite_article_links()
    |> String.replace(
      "</h1>",
      """
      </h1>
      <p class="article-meta">Published #{article.published_on} · Obscura #{Map.get(article, :version, "0.1.x")}</p>
      <p class="article-author">By #{@author_name} · <a href="#{@author_x_url}">X @hfiguera</a> · <a href="#{@author_github_url}">GitHub @hfiguera</a></p>
      """
      |> String.trim(),
      global: false
    )
  end

  defp write_article(article, rendered_article) do
    canonical_url = canonical_url(article)
    og_image = canonical_url <> "media/#{article.slug}/#{article.og_image}"

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "TechArticle",
        "author" => %{
          "@type" => "Person",
          "name" => @author_name,
          "sameAs" => [@author_x_url, @author_github_url]
        },
        "dateModified" => article.published_on,
        "datePublished" => article.published_on,
        "description" => article.description,
        "headline" => article.title,
        "image" => [og_image],
        "mainEntityOfPage" => canonical_url,
        "publisher" => %{"@type" => "Organization", "name" => "Obscura"},
        "url" => canonical_url
      })

    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{article.title} · Obscura</title>
        <meta name="description" content="#{article.description}">
        <meta name="theme-color" content="#151c1a">
        <link rel="canonical" href="#{canonical_url}">
        <link rel="alternate" type="application/rss+xml" title="Obscura articles" href="#{@site_url}feed.xml">
        <link rel="stylesheet" href="../../assets/syntax.css">
        <link rel="stylesheet" href="../../assets/site.css">

        <meta property="og:type" content="article">
        <meta property="og:site_name" content="Obscura">
        <meta property="og:title" content="#{article.title}">
        <meta property="og:description" content="#{article.description}">
        <meta property="og:url" content="#{canonical_url}">
        <meta property="og:image" content="#{og_image}">
        <meta property="og:image:width" content="1440">
        <meta property="og:image:height" content="900">
        <meta property="article:published_time" content="#{article.published_on}">

        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:title" content="#{article.title}">
        <meta name="twitter:description" content="#{article.description}">
        <meta name="twitter:image" content="#{og_image}">

        <script type="application/ld+json">#{json_ld}</script>
      </head>
      <body>
        <a class="skip-link" href="#article">Skip to article</a>
        #{site_header("../../")}
        <main id="article" class="article-shell">
          <article>#{rendered_article}</article>
        </main>
        #{site_footer("../../")}
      </body>
    </html>
    """

    File.write!(Path.join(article_output(article), "index.html"), html)
  end

  defp write_index do
    entries =
      Enum.map_join(@articles, "\n", fn article ->
        """
        <article class="post-entry">
          <p class="post-date">#{article.published_on}</p>
          <h2><a href="blog/#{article.slug}/">#{article.title}</a></h2>
          <p>#{article.description}</p>
          <a class="read-link" href="blog/#{article.slug}/">Read article</a>
        </article>
        """
      end)

    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Obscura engineering articles</title>
        <meta name="description" content="Engineering notes about PII detection, anonymization, Elixir, Nx, and local model serving.">
        <meta name="theme-color" content="#151c1a">
        <link rel="canonical" href="#{@site_url}">
        <link rel="alternate" type="application/rss+xml" title="Obscura articles" href="#{@site_url}feed.xml">
        <link rel="stylesheet" href="assets/site.css">
      </head>
      <body>
        <a class="skip-link" href="#articles">Skip to articles</a>
        #{site_header("")}
        <main id="articles" class="index-shell">
          <header class="index-intro">
            <p class="index-eyebrow">Engineering notes</p>
            <h1>Building practical PII protection in Elixir</h1>
            <p>Implementation reports, measurements, and integration guides from the work behind Obscura.</p>
          </header>
          <section class="post-list" aria-label="Published articles">
            #{entries}
          </section>
        </main>
        #{site_footer("")}
      </body>
    </html>
    """

    File.write!(Path.join(@output_root, "index.html"), html)
  end

  defp write_privacy do
    output = Path.join(@output_root, "privacy")
    File.mkdir_p!(output)

    canonical_url = @site_url <> "privacy/"

    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Analytics privacy · Obscura</title>
        <meta name="description" content="How the Obscura engineering blog uses privacy-focused website analytics.">
        <meta name="theme-color" content="#151c1a">
        <link rel="canonical" href="#{canonical_url}">
        <link rel="alternate" type="application/rss+xml" title="Obscura articles" href="#{@site_url}feed.xml">
        <link rel="stylesheet" href="../assets/site.css">
      </head>
      <body>
        <a class="skip-link" href="#privacy">Skip to privacy information</a>
        <header class="site-header">
          <a class="brand" href="../" aria-label="Obscura home">
            <span class="brand-mark" aria-hidden="true">O</span>
            <span>
              <strong>Obscura</strong>
              <small>PII detection and anonymization for Elixir</small>
            </span>
          </a>
          <nav aria-label="Project links">
            <a href="https://hexdocs.pm/obscura/">Docs</a>
            <a href="https://github.com/hfiguera/obscura_examples">Workbench</a>
            <a href="https://github.com/hfiguera/obscura">GitHub</a>
          </nav>
        </header>
        <main id="privacy" class="article-shell">
          <article>
            <h1>Analytics privacy</h1>
            <p>
              This site uses Cloudflare Web Analytics to understand aggregate
              page visits, referring sites, and page performance.
            </p>
            <p>
              The analytics beacon does not use cookies or local storage, and
              Cloudflare Web Analytics does not log URL query strings or support
              custom tracking events. The browser sends measurements to
              Cloudflare when a page loads and when it is left.
            </p>
            <p>
              Blocking the analytics script does not change the content or
              functionality of this site. For implementation details, see
              <a href="https://developers.cloudflare.com/web-analytics/data-metrics/data-origin-and-collection/">Cloudflare's data collection documentation</a>.
            </p>
          </article>
        </main>
        <footer>
          <p>Obscura is a library-first toolkit for detecting and anonymizing PII in Elixir.</p>
          <p><a href="https://github.com/hfiguera/obscura">Source</a> · <a href="https://hex.pm/packages/obscura">Hex</a> · <a href="../feed.xml">RSS</a> · <a href="./">Analytics privacy</a></p>
        </footer>
        #{analytics_beacon()}
      </body>
    </html>
    """

    File.write!(Path.join(output, "index.html"), html)
  end

  defp write_feed do
    items =
      Enum.map_join(@articles, "\n", fn article ->
        """
        <item>
          <title>#{xml_escape(article.title)}</title>
          <link>#{canonical_url(article)}</link>
          <guid isPermaLink="true">#{canonical_url(article)}</guid>
          <pubDate>#{article.rss_date}</pubDate>
          <description>#{xml_escape(article.description)}</description>
        </item>
        """
      end)

    feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Obscura articles</title>
        <link>#{@site_url}</link>
        <description>Engineering notes about PII detection and anonymization in Elixir.</description>
        <language>en</language>
        <lastBuildDate>#{@perplexity_rss_date}</lastBuildDate>
        #{items}
      </channel>
    </rss>
    """

    File.write!(Path.join(@output_root, "feed.xml"), feed)
  end

  defp write_sitemap do
    article_urls =
      Enum.map_join(@articles, "\n", fn article ->
        """
        <url>
          <loc>#{canonical_url(article)}</loc>
          <lastmod>#{article.published_on}</lastmod>
        </url>
        """
      end)

    sitemap = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>#{@site_url}</loc>
        <lastmod>#{@perplexity_published_on}</lastmod>
      </url>
      <url>
        <loc>#{@site_url}privacy/</loc>
        <lastmod>#{@initial_published_on}</lastmod>
      </url>
      #{article_urls}
    </urlset>
    """

    File.write!(Path.join(@output_root, "sitemap.xml"), sitemap)
  end

  defp copy_shared_assets do
    File.cp!(@stylesheet_source, Path.join(@output_root, "assets/site.css"))

    File.write!(
      Path.join(@output_root, "assets/syntax.css"),
      Makeup.stylesheet(:one_dark_style, "makeup")
    )
  end

  defp copy_article_media(article) do
    media_output = Path.join(article_output(article), "media/#{article.slug}")
    File.mkdir_p!(media_output)

    article
    |> media_source()
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&(Path.extname(&1) in @media_extensions))
    |> Enum.each(&File.cp!(&1, Path.join(media_output, Path.basename(&1))))
  end

  defp article_source(article), do: "docs/blog/#{article.slug}.md"
  defp media_source(article), do: "docs/blog/media/#{article.slug}"
  defp article_output(article), do: Path.join([@output_root, "blog", article.slug])
  defp canonical_url(article), do: @site_url <> "blog/#{article.slug}/"

  defp rewrite_article_links(html) do
    Enum.reduce(@articles, html, fn article, rendered ->
      String.replace(
        rendered,
        ~s(href="#{article.slug}.md"),
        ~s(href="../#{article.slug}/")
      )
    end)
  end

  defp site_header(root) do
    """
    <header class="site-header">
      <a class="brand" href="#{root}" aria-label="Obscura articles">
        <span class="brand-mark" aria-hidden="true">O</span>
        <span>
          <strong>Obscura</strong>
          <small>PII detection and anonymization for Elixir</small>
        </span>
      </a>
      <nav aria-label="Project links">
        <a href="https://hexdocs.pm/obscura/">Docs</a>
        <a href="https://github.com/hfiguera/obscura_examples">Workbench</a>
        <a href="https://github.com/hfiguera/obscura">GitHub</a>
      </nav>
    </header>
    """
  end

  defp site_footer(root) do
    """
    <footer>
      <p>Obscura is a library-first toolkit for detecting and anonymizing PII in Elixir.</p>
      <p><a href="https://github.com/hfiguera/obscura">Source</a> · <a href="https://hex.pm/packages/obscura">Hex</a> · <a href="#{root}feed.xml">RSS</a> · <a href="#{root}privacy/">Analytics privacy</a></p>
    </footer>
    #{analytics_beacon()}
    """
  end

  defp analytics_beacon do
    """
    <!-- Cloudflare Web Analytics -->
    <script type="module" src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"#{@analytics_token}"}'></script>
    <!-- End Cloudflare Web Analytics -->
    """
  end

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end

Obscura.PagesBuilder.run()
