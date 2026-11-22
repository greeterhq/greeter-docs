# frozen_string_literal: true

# In-memory only: every model here is built from domain objects, with no files,
# network or clock.
RSpec.describe 'GreeterDocs::Domain::CoverageRule' do
  subject(:rule) { GreeterDocs::Domain::CoverageRule.new }

  def violated_slugs(docs_model)
    rule.violations(docs_model).map(&:requirement)
  end

  let(:greeting_tags) do
    {
      'a-channel-greets-a-valid-guest' => 'greeting-happy',
      'a-channel-rejects-an-invalid-name' => 'greeting-invalid',
      'a-counting-channel-records-the-greeting-count' => 'greeting-count',
      'a-counting-channel-increments-the-count-for-a-returning-guest' => 'greeting-returning',
      'an-idempotent-replay-does-not-double-count' => 'greeting-idempotent'
    }
  end

  let(:acceptance) do
    repo('greeter-acceptance',
         greeting_tags.keys.map { |slug| requirement(slug, capability: 'greeting') },
         requirement_tags: greeting_tags)
  end

  context 'when a requirement has a trace result',
          requirement: 'a-requirement-passes-when-a-trace-result-for-it-passed' do
    context 'with status passed', scenario: 'a-passed-result-covers-the-requirement' do
      it 'returns no violation for it' do
        core = repo('greeter-core', [requirement('greet-a-guest')])
        docs_model = model(repos: [core],
                           traces: [trace('greeter-core', [result('greet-a-guest', 'scenario-one', 'passed')])])

        expect(violated_slugs(docs_model)).to be_empty
      end
    end

    context 'with only skipped and failed results',
            scenario: 'only-skipped-or-failed-results-do-not-cover-the-requirement' do
      it 'returns a violation for it' do
        http = repo('greeter-http', [requirement('deployed-stage-exposes-version-headers',
                                                 capability: 'version-headers')])
        results = [result('deployed-stage-exposes-version-headers', 'smoke', 'skipped'),
                   result('deployed-stage-exposes-version-headers', 'smoke', 'failed', location: 'spec/y_spec.rb:2')]
        docs_model = model(repos: [http], traces: [trace('greeter-http', results)])

        violation = only_item(rule.violations(docs_model))
        expect([violation.repo, violation.capability, violation.requirement, violation.spec_path])
          .to eq(['greeter-http', 'version-headers', 'deployed-stage-exposes-version-headers',
                  'openspec/specs/version-headers/spec.md'])
      end
    end

    context 'when the repo has no trace', scenario: 'a-repo-with-no-trace-leaves-its-requirements-uncovered' do
      it 'returns a violation for each requirement' do
        cli = repo('greeter-cli', [requirement('first-requirement'), requirement('second-requirement')])

        expect(violated_slugs(model(repos: [cli]))).to contain_exactly('first-requirement', 'second-requirement')
      end
    end
  end

  context 'with tag-mapped requirements', requirement: 'tag-mapped-requirements-are-covered-by-the-prod-ledger' do
    let(:all_passed) { greeting_tags.values.to_h { |key| [key, { 'cli' => 'passed', 'http' => 'passed' }] } }

    context 'when a prod channel passed',
            scenario: 'a-passed-channel-in-the-prod-ledger-covers-a-mapped-requirement' do
      it 'returns no violation, and ignores the repo trace for mapped requirements' do
        docs_model = model(repos: [acceptance], traces: [trace('greeter-acceptance', [])],
                           ledgers: [ledger('prod', all_passed), not_recorded('stage')])

        expect(violated_slugs(docs_model)).to be_empty
      end
    end

    context 'when a key is only not_applicable or absent',
            scenario: 'not-applicable-alone-does-not-cover-a-mapped-requirement' do
      it 'returns a violation for each' do
        requirements = all_passed.merge('greeting-count' => { 'cli' => 'not_applicable', 'http' => 'not_applicable' })
        requirements.delete('greeting-returning')
        docs_model = model(repos: [acceptance], ledgers: [ledger('prod', requirements)])

        expect(violated_slugs(docs_model)).to contain_exactly(
          'a-counting-channel-records-the-greeting-count',
          'a-counting-channel-increments-the-count-for-a-returning-guest'
        )
      end
    end

    context 'when only stage passed', scenario: 'stage-results-do-not-cover-a-mapped-requirement' do
      it 'returns a violation' do
        prod = all_passed.merge('greeting-happy' => { 'cli' => 'failed', 'http' => 'failed' })
        stage = all_passed.merge('greeting-happy' => { 'cli' => 'passed' })
        docs_model = model(repos: [acceptance], ledgers: [ledger('prod', prod), ledger('stage', stage)])

        expect(violated_slugs(docs_model)).to eq(['a-channel-greets-a-valid-guest'])
      end
    end

    context 'when the prod ledger is not yet recorded',
            scenario: 'a-missing-prod-ledger-leaves-mapped-requirements-unjudged' do
      it 'returns no violation and reports all five as not yet recorded' do
        docs_model = model(repos: [acceptance], ledgers: [not_recorded('prod'), not_recorded('stage')])

        expect(violated_slugs(docs_model)).to be_empty
        expect(rule.not_yet_recorded(docs_model).map(&:requirement)).to match_array(greeting_tags.keys)
      end
    end
  end

  describe 'ordering and summary' do
    it 'sorts violations by repo, capability and requirement and formats one line each' do
      repos = [repo('greeter-http', [requirement('zeta', capability: 'b'), requirement('alpha', capability: 'a')]),
               repo('greeter-cli', [requirement('beta', capability: 'a')])]

      lines = rule.violations(model(repos: repos)).map(&:to_s)

      expect(lines).to eq(['greeter-cli a beta openspec/specs/a/spec.md',
                           'greeter-http a alpha openspec/specs/a/spec.md',
                           'greeter-http b zeta openspec/specs/b/spec.md'])
    end

    it 'summarises covered, uncovered and not yet recorded counts' do
      core = repo('greeter-core', [requirement('covered'), requirement('uncovered')])
      docs_model = model(repos: [core, acceptance],
                         traces: [trace('greeter-core', [result('covered', 'scenario-one', 'passed')])],
                         ledgers: [not_recorded('prod')])

      expect(rule.summary(docs_model)).to eq(covered: 1, uncovered: 1, not_yet_recorded: 5)
    end
  end
end
