defmodule Obscura.PagesBuilder do
  @moduledoc false

  @article_slug "protecting-pii-in-elixir"
  @article_source "docs/blog/#{@article_slug}.md"
  @media_source "docs/blog/media/#{@article_slug}"
  @stylesheet_source "docs/blog/site.css"
  @output_root "_site"
  @article_output Path.join([@output_root, "blog", @article_slug])
  @canonical_url "https://hfiguera.github.io/obscura/blog/#{@article_slug}/"
  @site_url "https://hfiguera.github.io/obscura/"
  @analytics_token "f968ea7d6e614cc9a3e2d537ced91a10"
  @title "Protecting PII in Elixir Before It Reaches Logs, APIs, and LLMs"
  @description "A practical guide to detecting, redacting, and pseudonymizing PII at Elixir application boundaries with Obscura."
  @published_on "2026-07-22"
  @og_image @canonical_url <> "media/#{@article_slug}/obscura-workbench-fast-detection.jpg"

  def run do
    {:ok, _applications} = Application.ensure_all_started(:makeup_elixir)

    File.rm_rf!(@output_root)
    File.mkdir_p!(@article_output)
    File.mkdir_p!(Path.join(@output_root, "assets"))

    markdown = File.read!(@article_source)
    article = render_markdown(markdown)

    write_article(article)
    write_root_redirect()
    write_privacy()
    write_feed()
    write_sitemap()
    copy_assets()

    File.write!(Path.join(@output_root, ".nojekyll"), "")
    IO.puts("Built #{@canonical_url} in #{@output_root}")
  end

  defp render_markdown(markdown) do
    ast = ExDoc.Markdown.Earmark.to_ast(markdown, file: @article_source)

    ast
    |> ExDoc.DocAST.highlight(ExDoc.Language.Elixir)
    |> ExDoc.DocAST.to_html()
    |> String.replace(
      "</h1>",
      "</h1>\n<p class=\"article-meta\">Published #{@published_on} · Obscura 0.1.x</p>",
      global: false
    )
  end

  defp write_article(article) do
    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "TechArticle",
        "dateModified" => @published_on,
        "datePublished" => @published_on,
        "description" => @description,
        "headline" => @title,
        "image" => [@og_image],
        "mainEntityOfPage" => @canonical_url,
        "publisher" => %{"@type" => "Organization", "name" => "Obscura"},
        "url" => @canonical_url
      })

    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{@title} · Obscura</title>
        <meta name="description" content="#{@description}">
        <meta name="theme-color" content="#151c1a">
        <link rel="canonical" href="#{@canonical_url}">
        <link rel="alternate" type="application/rss+xml" title="Obscura articles" href="#{@site_url}feed.xml">
        <link rel="stylesheet" href="../../assets/syntax.css">
        <link rel="stylesheet" href="../../assets/site.css">

        <meta property="og:type" content="article">
        <meta property="og:site_name" content="Obscura">
        <meta property="og:title" content="#{@title}">
        <meta property="og:description" content="#{@description}">
        <meta property="og:url" content="#{@canonical_url}">
        <meta property="og:image" content="#{@og_image}">
        <meta property="og:image:width" content="1440">
        <meta property="og:image:height" content="900">
        <meta property="article:published_time" content="#{@published_on}">

        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:title" content="#{@title}">
        <meta name="twitter:description" content="#{@description}">
        <meta name="twitter:image" content="#{@og_image}">

        <script type="application/ld+json">#{json_ld}</script>
      </head>
      <body>
        <a class="skip-link" href="#article">Skip to article</a>
        <header class="site-header">
          <a class="brand" href="../../" aria-label="Obscura home">
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
        <main id="article" class="article-shell">
          <article>#{article}</article>
        </main>
        <footer>
          <p>Obscura is a library-first toolkit for detecting and anonymizing PII in Elixir.</p>
          <p><a href="https://github.com/hfiguera/obscura">Source</a> · <a href="https://hex.pm/packages/obscura">Hex</a> · <a href="../../feed.xml">RSS</a> · <a href="../../privacy/">Analytics privacy</a></p>
        </footer>
        #{analytics_beacon()}
      </body>
    </html>
    """

    File.write!(Path.join(@article_output, "index.html"), html)
  end

  defp write_root_redirect do
    html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="0; url=blog/#{@article_slug}/">
        <link rel="canonical" href="#{@canonical_url}">
        <title>Obscura articles</title>
      </head>
      <body>
        <p><a href="blog/#{@article_slug}/">Read #{@title}</a></p>
        #{analytics_beacon()}
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
    feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Obscura articles</title>
        <link>#{@site_url}</link>
        <description>Engineering notes about PII detection and anonymization in Elixir.</description>
        <language>en</language>
        <lastBuildDate>Wed, 22 Jul 2026 00:00:00 GMT</lastBuildDate>
        <item>
          <title>#{xml_escape(@title)}</title>
          <link>#{@canonical_url}</link>
          <guid isPermaLink="true">#{@canonical_url}</guid>
          <pubDate>Wed, 22 Jul 2026 00:00:00 GMT</pubDate>
          <description>#{xml_escape(@description)}</description>
        </item>
      </channel>
    </rss>
    """

    File.write!(Path.join(@output_root, "feed.xml"), feed)
  end

  defp write_sitemap do
    sitemap = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>#{@canonical_url}</loc>
        <lastmod>#{@published_on}</lastmod>
      </url>
      <url>
        <loc>#{@site_url}privacy/</loc>
        <lastmod>#{@published_on}</lastmod>
      </url>
    </urlset>
    """

    File.write!(Path.join(@output_root, "sitemap.xml"), sitemap)
  end

  defp copy_assets do
    File.cp!(@stylesheet_source, Path.join(@output_root, "assets/site.css"))

    File.write!(
      Path.join(@output_root, "assets/syntax.css"),
      Makeup.stylesheet(:one_dark_style, "makeup")
    )

    media_output = Path.join(@article_output, "media/#{@article_slug}")
    File.mkdir_p!(media_output)

    @media_source
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&(Path.extname(&1) in [".gif", ".jpg", ".mp4"]))
    |> Enum.each(&File.cp!(&1, Path.join(media_output, Path.basename(&1))))
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
