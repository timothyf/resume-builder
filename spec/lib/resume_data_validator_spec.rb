require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'resume_data_validator'

RSpec.describe ResumeDataValidator do
  def write_yaml(root, relative_path, value)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(value))
  end

  def read_yaml(root, relative_path)
    YAML.safe_load_file(File.join(root, relative_path), aliases: true)
  end

  def build_valid_project(root)
    write_yaml(root, 'data/active_resume.yml', {
      'user' => 'person',
      'name' => 'resume'
    })
    write_yaml(root, 'data/person/resume.yml', {
      'layout' => 'layout',
      'pdf' => {
        'filename' => 'pdf/Resume',
        'source' => 'Resume.pdf'
      },
      'contact_info' => {
        'name' => 'Person Example',
        'email' => 'person@example.com',
        'address' => {
          'street' => '123 Main Street',
          'city' => 'Detroit',
          'state' => 'MI',
          'postal_code' => '48201'
        }
      },
      'summary' => { 'file' => 'summary' },
      'skills' => [{ 'name' => 'Development', 'skills' => [1] }],
      'jobs_filename' => 'jobs',
      'jobs' => [{ 'id' => 'job-1', 'section' => 'experiences' }],
      'education' => [{
        'name' => 'Example University',
        'degree' => 'B.S.',
        'dates' => { 'start' => '2000', 'end' => '2004' }
      }]
    })
    write_yaml(root, 'data/person/layouts/layout.yml', {
      'content' => {
        'center' => [
          { 'template' => 'summary' },
          { 'template' => 'experiences' }
        ],
        'right' => %w[profile contact skills education download].map do |template|
          { 'template' => template }
        end
      }
    })
    write_yaml(root, 'data/person/summaries/summary.yml', {
      'summary' => { 'text' => 'Experienced developer.' }
    })
    write_yaml(root, 'data/person/skills.yml', [
      { 'id' => 1, 'label' => 'Ruby' }
    ])
    write_yaml(root, 'data/person/jobs.yml', [
      {
        'id' => 'job-1',
        'title' => 'Developer',
        'company' => 'Example Company',
        'location' => { 'city' => 'Detroit', 'state' => 'MI' },
        'dates' => { 'start' => '2020', 'end' => 'Present' },
        'desc' => 'Built software.'
      }
    ])
    File.binwrite(File.join(root, 'Resume.pdf'), '%PDF-fixture')

    %w[summary experiences profile contact skills education download].each do |template|
      path = File.join(root, 'source', 'templates', "_#{template}.erb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "<%# #{template} %>\n")
    end
  end

  it 'validates the repository active resume' do
    validator = described_class.new(project_root: File.expand_path('../..', __dir__))

    expect(validator.validate!).to be(true)
  end

  it 'accepts a complete resume data graph' do
    Dir.mktmpdir do |root|
      build_valid_project(root)

      expect(described_class.new(project_root: root).validate!).to be(true)
    end
  end

  it 'aggregates missing references, templates, and nested values' do
    Dir.mktmpdir do |root|
      build_valid_project(root)
      resume = read_yaml(root, 'data/person/resume.yml')
      resume['jobs'][0]['id'] = 'missing-job'
      resume['jobs'] << { 'id' => 'job-1', 'section' => 'experiences' }
      resume['skills'][0]['skills'] << 999
      write_yaml(root, 'data/person/resume.yml', resume)

      layout = read_yaml(root, 'data/person/layouts/layout.yml')
      layout['content']['center'] << { 'template' => 'missing_section' }
      write_yaml(root, 'data/person/layouts/layout.yml', layout)

      jobs = read_yaml(root, 'data/person/jobs.yml')
      jobs[0]['location'].delete('state')
      write_yaml(root, 'data/person/jobs.yml', jobs)

      expect do
        described_class.new(project_root: root).validate!
      end.to raise_error(ResumeDataValidator::ValidationError) { |error|
        expect(error.message).to include("references missing job 'missing-job'")
        expect(error.message).to include("references missing skill '999'")
        expect(error.message).to include("references missing template 'source/templates/_missing_section.erb'")
        expect(error.message).to include("job 'job-1'.location.state is required")
      }
    end
  end

  it 'reports malformed YAML with its file and location' do
    Dir.mktmpdir do |root|
      build_valid_project(root)
      File.write(File.join(root, 'data', 'person', 'resume.yml'), "layout: [unterminated\n")

      expect do
        described_class.new(project_root: root).validate!
      end.to raise_error(ResumeDataValidator::ValidationError, /resume.yml contains invalid YAML at line/)
    end
  end

  it 'uses active resume environment overrides' do
    Dir.mktmpdir do |root|
      build_valid_project(root)
      FileUtils.cp(
        File.join(root, 'data', 'person', 'resume.yml'),
        File.join(root, 'data', 'person', 'alternate.yml')
      )
      validator = described_class.new(
        project_root: root,
        env: {
          'ACTIVE_RESUME_USER' => 'person',
          'ACTIVE_RESUME_NAME' => 'alternate'
        }
      )

      expect(validator.validate!).to be(true)
      expect(validator.resume_name).to eq('alternate')
    end
  end
end
