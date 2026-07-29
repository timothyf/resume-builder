require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'resume_creator'

RSpec.describe ResumeCreator do
  def write_yaml(root, relative_path, value)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(value))
  end

  def read_yaml(root, relative_path)
    YAML.safe_load_file(File.join(root, relative_path), aliases: true)
  end

  def build_project(root)
    write_yaml(root, 'data/active_resume.yml', {
      'user' => 'person',
      'name' => 'resume_current'
    })
    write_yaml(root, 'data/resume_support.yml', {
      'supported' => [{ 'user' => 'person', 'name' => 'resume_current' }],
      'archived' => []
    })
  end

  it 'creates a new resume and registers it as supported' do
    Dir.mktmpdir do |root|
      build_project(root)

      result = described_class.new(project_root: root).create!(name: 'new_role')

      expect(result.fetch(:resume)).to eq('data/person/resumes/resume_new_role/resume.yml')
      expect(read_yaml(root, 'data/person/resumes/resume_new_role/resume.yml')).to include(
        'name' => 'resume_new_role',
        'jobs_filename' => 'jobs',
        'summary' => { 'file' => 'summary' }
      )
      expect(read_yaml(root, 'data/person/resumes/resume_new_role/jobs.yml')).to eq([])
      expect(read_yaml(root, 'data/person/resumes/resume_new_role/summary.yml')).to eq(
        'summary' => { 'text' => 'Add a focused summary for this resume.' }
      )
      expect(read_yaml(root, 'data/resume_support.yml').fetch('supported')).to include(
        'user' => 'person',
        'name' => 'resume_new_role'
      )
    end
  end

  it 'duplicates an existing resume component set' do
    Dir.mktmpdir do |root|
      build_project(root)
      write_yaml(root, 'data/person/resume_source.yml', {
        'name' => 'resume_source',
        'layout' => 'layout_ats',
        'pdf' => {
          'filename' => 'pdf/resume_master',
          'source' => 'resume_master.pdf'
        },
        'summary' => { 'file' => 'summary_source' },
        'jobs_filename' => 'jobs_source',
        'jobs' => [{ 'id' => 'job-1', 'section' => 'experiences' }]
      })
      write_yaml(root, 'data/person/jobs_source.yml', [{ 'id' => 'job-1' }])
      write_yaml(root, 'data/person/summaries/summary_source.yml', {
        'summary' => { 'text' => 'Source summary.' }
      })

      described_class.new(project_root: root).create!(name: 'target', from: 'resume_source')

      expect(read_yaml(root, 'data/person/resumes/resume_target/resume.yml')).to include(
        'name' => 'resume_target',
        'layout' => 'layout_ats',
        'pdf' => {
          'filename' => 'pdf/resume_target',
          'source' => 'resume_target.pdf'
        },
        'summary' => { 'file' => 'summary' },
        'jobs_filename' => 'jobs'
      )
      expect(read_yaml(root, 'data/person/resumes/resume_target/jobs.yml')).to eq([{ 'id' => 'job-1' }])
      expect(read_yaml(root, 'data/person/resumes/resume_target/summary.yml')).to eq(
        'summary' => { 'text' => 'Source summary.' }
      )
    end
  end

  it 'refuses to overwrite generated files by default' do
    Dir.mktmpdir do |root|
      build_project(root)
      write_yaml(root, 'data/person/resumes/resume_existing/resume.yml', {})

      expect do
        described_class.new(project_root: root).create!(name: 'existing')
      end.to raise_error(described_class::Error, /Refusing to overwrite/)
    end
  end
end
