# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # Static files and page-wide settings for the published site.
    module SiteAssets
      # Pinned exact version (design D7); loaded only by assets/architecture.js.
      MERMAID_URL = 'https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs'

      # Set on every page as a meta tag (design S6). No page has an inline script.
      CSP = "default-src 'none'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; " \
            "img-src 'self' data:; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'"

      NAV = [%w[index.html Home], %w[traceability.html Traceability], %w[api.html API],
             %w[architecture.html Architecture], %w[adr/index.html ADRs], %w[contracts.html Contracts],
             %w[slo.html SLOs]].freeze

      FILES = {
        'assets/architecture.js' => <<~JS,
          import mermaid from "#{MERMAID_URL}";
          mermaid.initialize({ startOnLoad: true, securityLevel: "strict" });
        JS
        'assets/site.css' => <<~CSS
          body { font-family: system-ui, sans-serif; margin: 0 auto; max-width: 72rem; padding: 0 1rem; }
          nav a { margin-right: 1rem; }
          table { border-collapse: collapse; margin: 1rem 0; }
          th, td { border: 1px solid #ccc; padding: 0.25rem 0.5rem; text-align: left; vertical-align: top; }
          [data-status="passed"] { color: #146c2e; }
          [data-status="failed"], [data-verdict="uncovered"] { color: #a40e26; }
          pre { background: #f6f8fa; overflow-x: auto; padding: 0.5rem; }
        CSS
      }.freeze
    end
  end
end
