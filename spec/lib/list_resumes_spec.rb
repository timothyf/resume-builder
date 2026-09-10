require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../scripts/list_resumes'

RSpec.describe ListResumes do
  def touch_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\n")
  end

  it 'returns both legacy and structured resumes for a user' do
    Dir.mktmpdir do |root|
      touch_file(File.join(root, 'data', 'person', 'resume_legacy.yml'))
      touch_file(File.join(root, 'data', 'person', 'resumes', 'resume_structured', 'resume.yml'))

      resumes = described_class.resumes_for_user(project_root: root, user: 'person')

      expect(resumes).to include(
        {
          name: 'resume_legacy',
          structure: 'legacy',
          path: 'data/person/resume_legacy.yml'
        }
      )
      expect(resumes).to include(
        {
          name: 'resume_structured',
          structure: 'structured',
          path: 'data/person/resumes/resume_structured/resume.yml'
        }
      )
    end
  end

  it 'returns an empty list when user data directory is missing' do
    Dir.mktmpdir do |root|
      resumes = described_class.resumes_for_user(project_root: root, user: 'missing')
      expect(resumes).to eq([])
    end
  end
end
