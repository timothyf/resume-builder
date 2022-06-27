# Resume Builder

Resume Builder is an HTML and PDF resume builder made in Ruby with [Middleman](http://middlemanapp.com/). Allows you to keep your resume content in a text-based YAML file, that can be be rendered as an HTML view for the web, and as a PDF view for download and printing.

It has the following features:

 * Separation between content and data, all your resume information is an YAML
   file.
 * Uses your Gravatar picture. (OPTIONAL)
 * Fork this project for maintaining multiple versions of your resume in sync.
 * Markdown/HTML for formatting of the longer paragraphs.
 * You can preview your changes with Middleman's included server (with livereload).
 * Automatic PDF generation using [wkhtmltopdf](http://wkhtmltopdf.org).
 * Turnkey deployment to a `http://yourusername.github.com/resume` page with no configuration necessary.

## Preview

See the result: [sample resume](http://timothyf.github.com/resume-builder/).

## In practice

Fork this project and name it `resume` for example.
Follow the installation instructions below.

To create/update your resume, you'll just need to edit the [`data/resume.yml`](https://github.com/reefab/ResumeMan/blob/master/data/resume.yml) file.
All keys with a `desc: |` header can be Markdown formatted.

Here is what it looks like:

```yaml
info:
    name: Jonathan Doe
    shortdesc: Web Designer, Director
    email: example@example.com
    phone: (313) - 867-5309
    address:
        - 123 Fake Street
        - City, Country
    desc: |
        You can put Markdown in here [like this](http://daringfireball.net/projects/markdown/).
```

You can preview your resume at `http://localhost:4567/`

    bundle exec middleman build

Build the static version of your resume, it'll also create the PDF version.

    bundle exec middleman deploy

Upload it to a Github page. Your resume will be available at `http://yourusername.github.com/resume`.

## Installation

If you forked to your own repo:

    git clone https://github.com/<yourusername>/resume.git
    cd resume

Otherwise:

    git clone https://github.com/timothyf/resume-builder.git
    cd ResumeMan

Install all dependencies:

    sudo gem install bundler
    bundle install

Launch the previewing server:

    bundle exec middleman

## Resume instructions

Sections
