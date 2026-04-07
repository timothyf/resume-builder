require 'spec_helper'

RSpec.describe ResumeSelection do
  ActiveResume = Struct.new(:user, :name, :generate_brief, keyword_init: true)
  ResumePayload = Struct.new(:layout, :jobs_filename, :theme, keyword_init: true)
  UserData = Struct.new(:resume_dev_refined, :override_resume, keyword_init: true)
  DataRoot = Struct.new(:timothyfisher, :override_user, keyword_init: true)

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
