require 'spec_helper'

RSpec.describe ResumeSelection do
  ActiveResume = Struct.new(:user, :name, :generate_brief, keyword_init: true)
  ResumePayload = Struct.new(:layout, :jobs_filename, :theme, keyword_init: true)
  UserData = Struct.new(:resume_dev_refined, :override_resume, :resumes, keyword_init: true)
  DataRoot = Struct.new(:timothyfisher, :override_user, keyword_init: true)
  StructuredResumeScope = Struct.new(:resume, keyword_init: true)
  StructuredResumes = Struct.new(:resume_structured, keyword_init: true)

  let(:active_resume) do
    ActiveResume.new(user: 'timothyfisher', name: 'resume_dev_refined', generate_brief: false)
  end

  let(:resume_payload) { ResumePayload.new(layout: 'layout', jobs_filename: 'jobs', theme: nil) }
  let(:override_resume_payload) { ResumePayload.new(layout: 'layout', jobs_filename: 'jobs', theme: 'theme-fern') }
  let(:user_data) { UserData.new(resume_dev_refined: resume_payload, override_resume: override_resume_payload) }
  let(:override_user_data) { UserData.new(resume_dev_refined: resume_payload, override_resume: override_resume_payload) }
  let(:data_root) { DataRoot.new(timothyfisher: user_data, override_user: override_user_data) }

  describe '.active_resume_identifiers' do
    it 'uses active resume values when env overrides are absent' do
      result = described_class.active_resume_identifiers(active_resume)
      expect(result).to eq(user: 'timothyfisher', name: 'resume_dev_refined')
    end

    it 'uses environment overrides when present' do
      ENV['ACTIVE_RESUME_USER'] = 'override_user'
      ENV['ACTIVE_RESUME_NAME'] = 'override_resume'

      result = described_class.active_resume_identifiers(active_resume)
      expect(result).to eq(user: 'override_user', name: 'override_resume')
    end
  end

  describe '.selection_context' do
    it 'resolves selected data and defaults brief from active resume file' do
      result = described_class.selection_context(active_resume, data_root)

      expect(result[:user]).to eq('timothyfisher')
      expect(result[:name]).to eq('resume_dev_refined')
      expect(result[:resume]).to eq(resume_payload)
      expect(result[:generate_brief]).to be(false)
      expect(result[:theme]).to eq('theme-default')
    end

    it 'allows brief override via env var' do
      ENV['ACTIVE_RESUME_GENERATE_BRIEF'] = 'true'

      result = described_class.selection_context(active_resume, data_root)
      expect(result[:generate_brief]).to be(true)
    end

    it 'uses resume theme when present' do
      ENV['ACTIVE_RESUME_USER'] = 'override_user'
      ENV['ACTIVE_RESUME_NAME'] = 'override_resume'

      result = described_class.selection_context(active_resume, data_root)
      expect(result[:theme]).to eq('theme-fern')
    end

    it 'uses env theme override when present' do
      ENV['ACTIVE_RESUME_THEME'] = 'theme-orange'

      result = described_class.selection_context(active_resume, data_root)
      expect(result[:theme]).to eq('theme-orange')
    end

    it 'resolves structured resume payloads when not present at user root' do
      structured_payload = ResumePayload.new(layout: 'layout', jobs_filename: 'jobs', theme: nil)
      structured_scope = StructuredResumeScope.new(resume: structured_payload)
      structured_user_data = UserData.new(
        override_resume: override_resume_payload,
        resumes: StructuredResumes.new(resume_structured: structured_scope)
      )
      structured_root = DataRoot.new(timothyfisher: structured_user_data, override_user: override_user_data)
      structured_active = ActiveResume.new(user: 'timothyfisher', name: 'resume_structured', generate_brief: true)

      result = described_class.selection_context(structured_active, structured_root)
      expect(result[:resume]).to eq(structured_payload)
      expect(result[:resume_scope]).to eq(structured_scope)
    end

    it 'raises on unsupported theme values' do
      ENV['ACTIVE_RESUME_THEME'] = 'theme-neon'

      expect { described_class.selection_context(active_resume, data_root) }
        .to raise_error(ArgumentError, /Invalid ACTIVE_RESUME_THEME/)
    end

    it 'raises for invalid brief override values' do
      ENV['ACTIVE_RESUME_GENERATE_BRIEF'] = 'maybe'

      expect { described_class.selection_context(active_resume, data_root) }
        .to raise_error(ArgumentError, /ACTIVE_RESUME_GENERATE_BRIEF/)
    end
  end
end
