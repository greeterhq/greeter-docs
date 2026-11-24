# frozen_string_literal: true

require 'fileutils'

module GreeterDocs
  module Adapters
    # Writes the static site from templates/*.erb. Every sourced value goes
    # through ErbView#h (CGI.escapeHTML). Values used in URLs, ids or data
    # attributes must also match a fixed pattern (design S5).
    class ErbHtmlPublisher
      include Ports::Publisher

      FILE_NAME = /\A[\w-][\w.-]*\z/
      DIGITS = /\A\d+\z/

      def initialize(templates_dir:, output_dir:)
        @templates_dir = templates_dir
        @output_dir = output_dir
      end

      def publish(model)
        @model = model
        @rule = Domain::CoverageRule.new
        SiteAssets::FILES.each { |path, content| write(path, content) }
        publish_index
        model.repos.each { |repo| publish_repo(repo) }
        publish_traceability
        publish_api
        publish_adrs
        publish_architecture_and_placeholders
      end

      # A CI run link for greeter-acceptance, only for an all-digit run ID.
      def ledger_run_url(run_id)
        run_url('greeter-acceptance', run_id)
      end

      private

      def publish_index
        repos = @model.repos.select { |repo| safe_name?(repo.name) }
        page('index.html', 'index', 'greeterHQ live docs', repos: repos, summary: @rule.summary(@model))
      end

      def publish_repo(repo)
        return unless safe_name?(repo.name)

        page("repos/#{repo.name}.html", 'repo', repo.name, **repo_locals(repo))
      end

      def repo_locals(repo)
        trace = @model.traces[repo.name]
        { repo: repo, trace: trace, run_url: run_url(repo.name, trace&.run_id),
          capabilities: repo.requirements.group_by(&:capability),
          verdicts: repo.requirements.to_h { |req| [req.slug, @rule.verdict(@model, repo, req)] },
          statuses: scenario_statuses(trace), **smoke_locals(repo.name) }
      end

      # The prod smoke trace's scenario statuses and run link (design D12).
      def smoke_locals(repo_name)
        smoke = @model.deployed_traces[repo_name]
        { smoke_statuses: scenario_statuses(smoke), smoke_run_url: run_url(repo_name, smoke&.run_id) }
      end

      def publish_traceability
        labels = Hash.new { |hash, key| hash[key] = [] }
        @model.repos.each { |repo| repo.requirement_tags.each { |slug, key| labels[key] << slug } }
        ledgers = %w[prod stage].map { |env| @model.ledgers[env] || Domain::LedgerView.not_recorded(env) }
        page('traceability.html', 'traceability', 'Traceability', ledgers: ledgers, labels: labels)
      end

      def publish_api
        api = @model.api
        write('openapi.yaml', api.raw) if api
        page('api.html', 'api', 'API', api: api)
      end

      def publish_adrs
        adrs = @model.adrs.select { |adr| safe_name?(adr.repo) && FILE_NAME.match?(adr.slug) }
        page('adr/index.html', 'adr_index', 'Architecture decision records', adrs: adrs)
        adrs.each do |adr|
          page("adr/#{adr.repo}/#{adr.slug}.html", 'adr', adr.title, adr: adr, body: Markdown.render(adr.body))
        end
      end

      def publish_architecture_and_placeholders
        page('architecture.html', 'architecture', 'Architecture',
             scripts: ['assets/architecture.js'], diagrams: @model.diagrams)
        page('contracts.html', 'placeholder', 'Contracts', subject: 'Contract tests', state: @model.contracts)
        page('slo.html', 'placeholder', 'SLOs', subject: 'Service level objectives', state: @model.slos)
      end

      # Per [requirement, scenario]: failed if any result failed, passed if any
      # passed, otherwise the first status recorded.
      def scenario_statuses(trace)
        return {} unless trace

        trace.results.group_by { |result| [result.requirement, result.scenario] }.transform_values do |results|
          statuses = results.map(&:status)
          %w[failed passed].find { |status| statuses.include?(status) } || statuses.first
        end
      end

      def run_url(repo, run_id)
        return nil unless safe_name?(repo) && run_id.is_a?(String) && DIGITS.match?(run_id)

        "https://github.com/greeterhq/#{repo}/actions/runs/#{run_id}"
      end

      def safe_name?(name)
        Domain::Slug.slug?(name)
      end

      def page(path, template, title, scripts: [], **locals)
        common = { title: title, root: '../' * path.count('/'), built_at: built_at }
        content = ErbView.new(locals.merge(common, publisher: self)).render(template_source(template))
        layout = ErbView.new(common.merge(scripts: scripts, content: content, csp: SiteAssets::CSP,
                                          nav: SiteAssets::NAV))
        write(path, layout.render(template_source('layout')))
      end

      def built_at
        @model.built_at.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      end

      def template_source(name)
        File.read(File.join(@templates_dir, "#{name}.erb"))
      end

      def write(path, content)
        target = File.join(@output_dir, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, content)
      end
    end
  end
end
