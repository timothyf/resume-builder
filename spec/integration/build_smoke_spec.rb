require 'spec_helper'

RSpec.describe 'Build smoke test', :integration do
  it 'builds successfully and emits key artifacts', :integration do
    skip 'Set RUN_INTEGRATION=1 to run integration specs' unless ENV['RUN_INTEGRATION'] == '1'

    root = File.expand_path('../..', __dir__)
    cmd = "cd #{root} && ./build_resume.bash --resume-user timothyfisher --resume-name resume_dev_refined"
    output = `#{cmd} 2>&1`
    status = $?.exitstatus

    expect(status).to eq(0), "Build failed:\n#{output}"
    expect(File.exist?(File.join(root, 'build', 'index.html'))).to be(true)
    expect(File.exist?(File.join(root, 'build', 'pdf.html'))).to be(true)
    expect(File.exist?(File.join(root, 'dist', 'timothyfisher', 'resume_dev_refined', 'index.html'))).to be(true)
  end
end
