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

      expect(result.fetch(:resume)).to eq('data/person/resume_new_role.yml')
      expect(read_yaml(root, 'data/person/resume_new_role.yml')).to include(
        'name' => 'resume_new_role',
        'jobs_filename' => 'jobs_new_role',
        'summary' => { 'file' => 'summary_new_role' }
      )
      expect(read_yaml(root, 'data/person/jobs_new_role.yml')).to eq([])
      expect(read_yaml(root, 'data/person/summaries/summary_new_role.yml')).to eq(
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
        'summary' => { 'file' => 'summary_source' },
        'jobs_filename' => 'jobs_source',
        'jobs' => [{ 'id' => 'job-1', 'section' => 'experiences' }]
      })
      write_yaml(root, 'data/person/jobs_source.yml', [{ 'id' => 'job-1' }])
      write_yaml(root, 'data/person/summaries/summary_source.yml', {
        'summary' => { 'text' => 'Source summary.' }
      })

      described_class.new(project_root: root).create!(name: 'target', from: 'resume_source')

      expect(read_yaml(root, 'data/person/resume_target.yml')).to include(
        'name' => 'resume_target',
        'layout' => 'layout_ats',
        'summary' => { 'file' => 'summary_target' },
        'jobs_filename' => 'jobs_target'
      )
      expect(read_yaml(root, 'data/person/jobs_target.yml')).to eq([{ 'id' => 'job-1' }])
      expect(read_yaml(root, 'data/person/summaries/summary_target.yml')).to eq(
        'summary' => { 'text' => 'Source summary.' }
      )
    end
  end

  it 'refuses to overwrite generated files by default' do
    Dir.mktmpdir do |root|
      build_project(root)
      write_yaml(root, 'data/person/resume_existing.yml', {})

      expect do
        described_class.new(project_root: root).create!(name: 'existing')
      end.to raise_error(described_class::Error, /Refusing to overwrite/)
    end
  end
end
