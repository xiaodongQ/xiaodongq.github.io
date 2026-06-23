# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Repository Overview

Personal technical blog of xiaodongQ, built with Jekyll and the [jekyll-theme-chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) gem (v7.2+), deployed to GitHub Pages at https://xiaodongq.github.io. Post content is primarily in Chinese; site UI is in English (`lang: en` in `_config.yml`).

## Common Commands

Dependencies are Ruby-based (no `package.json` at repo root). Install with `bundle install`.

- **Run dev server (with live reload):** `bash tools/run.sh`
  - Binds to `127.0.0.1` by default. Use `-H <host>` to change host, `-p` for production mode.
  - Underlying command: `bundle exec jekyll s -l`
- **Build + test (production):** `bash tools/test.sh`
  - Builds with `JEKYLL_ENV=production` into `_site/`, then runs `htmlproofer` (internal links only, external/https checks disabled).
  - Accepts `-c "<config_a[,config_b...]>"` to override config files.
- **Direct Jekyll build:** `bundle exec jekyll b` (dev) or `JEKYLL_ENV=production bundle exec jekyll b` (prod)
- **VS Code tasks** (`.vscode/tasks.json`): "Run Jekyll Server" → `tools/run.sh`; "Build Jekyll Site" → `tools/test.sh`.

Deployment is automatic via `.github/workflows/pages-deploy.yml` on push to `main`/`master` (Ruby 3.3, builds, htmlproofer test, then publishes to GitHub Pages). Manual dispatch is also available.

## Architecture

### Theme: gem-based, not vendored source
The theme is imported via `theme: jekyll-theme-chirpy` in `_config.yml` and declared in `Gemfile`. Layouts, includes, and assets ship from the gem — they are **not** in this repo. To override theme behavior, drop a same-named file into `_includes/` (e.g. `_includes/footer.html` already overrides the theme footer to add 不蒜子 visitor stats via `footer-busuanzi.html`).

### Content structure
- **`_posts/`** — published posts (~166 files). Filename format is strict: `YYYY-MM-DD-title-slug.md`. Front matter uses `title`, `description`, `categories: [Parent, Child]`, `tags: [...]`. Categories drive `/categories/:name/` archive pages; tags drive `/tags/:name/`.
- **`_drafts/`** — unpublished drafts (standard Jekyll directory). Drafts are excluded from production builds and have comments disabled by config (`defaults` scope for path `_drafts`).
- **`_tabs/`** — Jekyll collection (`output: true, sort_by: order`) producing the sidebar navigation pages: Archives, Categories, Tags, About. Each has `icon:` (FontAwesome) and `order:` front matter.
- **`index.html`** — minimal, just `layout: home`.
- **`images/`** — 370+ post images at repo root (referenced as `/images/...`).
- **`_data/`** — `contact.yml`, `share.yml`, `locales/` (UI translations per language), `origin/` (CORS config).

### Permalink scheme (important — do not change casually)
Posts use date-based permalinks:
```
permalink: /:year/:month/:day/:title/
```
e.g. `https://xiaodongq.github.io/2025/03/20/memory-management/`. `_config.yml` has a comment warning that changing this requires updating all existing post links. Tab pages use `permalink: /:title/`.

### Custom plugin: git-based lastmod
`_plugins/posts-lastmod-hook.rb` registers a `:post_init` hook that sets `last_modified_at` from `git log` for any post touched by more than one commit. This requires git history to be present (the deploy workflow uses `fetch-depth: 0` for this reason).

### Custom styles
`assets/css/jekyll-theme-chirpy.scss` is the entry point — it `@use`s the theme's `main` stylesheet (or `main.bundle` in production) and appends overrides. It also `@import`s `colorbox.scss`, which defines the `.box-info`, `.box-tip`, `.box-warning`, `.box-danger` callout styles referenced in posts via `{: .prompt-info }` / `{: .prompt-tip }` etc. Append custom SCSS here, not in the gem.

### Comments / analytics / PWA
- **Comments:** Giscus (`comments.provider: giscus`), tied to repo `xiaodongQ/xiaodongq.github.io`, category `Announcements`.
- **Analytics:** GoatCounter (`pageviews.provider: goatcounter`, id `xiaodongq`).
- **PWA:** enabled with offline caching (`pwa.enabled: true`, `pwa.cache.enabled: true`).
- **HTML compression:** enabled in production via `compress_html` (disabled in `development` env).

### Submodule
`assets/lib` is a git submodule pointing to `cotes2020/chirpy-static-assets` (see `.gitmodules`). The deploy workflow currently has `submodules: true` commented out — uncomment if these self-hosted assets are needed at build time.

## Conventions

- **Editor config (`.editorconfig`):** UTF-8, 2-space indent, LF line endings, trim trailing whitespace (except in `*.md`).
- **SCSS/JS:** single quotes; **YAML:** double quotes.
- **Posts:** begin with `## 1. 引言` (Introduction) section convention; use numbered headings (`## 1.`, `## 2.`) for top-level sections.
- **Callouts:** use Chirpy's `{: .prompt-info }`, `{: .prompt-tip }`, `{: .prompt-warning }`, `{: .prompt-danger }` blockquote suffixes.
- **Excluded from build:** `*.gem`, `*.gemspec`, `docs`, `tools`, `README.md`, `LICENSE`, `purgecss.js`, `rollup.config.js`, `package*.json` (see `exclude:` in `_config.yml`).

## Dev environment

A Dev Container is defined in `.devcontainer/` (Jekyll image, Ruby + zsh + OMZ plugins, shfmt). `post-create.sh` runs `npm install && npm run build` only if a `package.json` exists — currently there is none at root, so Ruby/Bundler is all that's needed.
