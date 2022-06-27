# Resume Builder

Resume Builder is an HTML and PDF resume builder made in Ruby with [Middleman](http://middlemanapp.com/). Allows you to keep your resume content in a text-based YAML file, that can be be rendered as an HTML view for the web, and as a PDF view for download and printing.

It has the following features:

 * Separation between content and style, all your resume content is a YAML
   file.
 * Uses your Gravatar picture. (OPTIONAL)
 * Markdown/HTML for formatting of the longer paragraphs.
 * You can preview your changes with Middleman's included server (with livereload).
 * Automatic PDF generation using [wkhtmltopdf](http://wkhtmltopdf.org).

## Installation

 If you forked to your own repo:

     git clone https://github.com/<yourusername>/resume-builder.git
     cd resume-builder

 Otherwise:

     git clone https://github.com/timothyf/resume-builder.git
     cd resume-builder

 Install all dependencies:

     sudo gem install bundler
     bundle install

## Preview

See the result: [sample resume](http://timothyf.github.com/resume-builder/).

## Usage

### Build yor resume

Build the static version of your resume, it'll also create the PDF version.

    bundle exec middleman build

### Deploy your resume

    bundle exec middleman deploy

Upload it to a Github page. Your resume will be available at `http://yourusername.github.com/resume`.



### Launch the previewing server:

    bundle exec middleman
You can preview your resume at `http://localhost:4567/`

## Resume instructions

To create/update your resume, you'll just need to edit the [`data/resume.yml`](https://github.com/reefab/ResumeMan/blob/master/data/resume.yml) file.
All keys with a `desc: |` header can be Markdown formatted.

Here is what it looks like:

```yaml
contact_info:
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

### Sections
Here is a description of each of the currently supported sections of a resume. A section is a content component that can be included in the resume yml data file.

The following section types are currently supported:

* PDF
* Headers
* Contact Info
* Links
* Summary
* Skills
* Jobs
* Education
* Certifications
* Projects
* Volunteering
* Languages
* Interests

#### PDF

The pdf section is used to describe details of the resume PDF that will be generated.
```yaml
pdf:
  filename: TimothyFisher-Resume
  useicons: true
  role: developer
```

#### Headers

The headers section allows you to specify the names of sections that will be used within the resume. For example,
given the headers section shown below, the profile section will be labeled as 'Summary' and the jobs sections
will be labled as "Experience".

```yaml
headers:
    profile: Summary
    jobs: Experience
    education: Education
    skills: Skills
    download: Download PDF
```

#### Contact Info

```yaml
contact_info:
    name: Timothy Fisher
    photo: false
    email: timothyf@gmail.com
    phone: (555) 555-1234
    address:
        street: 555 Springwells
        city: Detroit
        state: MI
        postal_code: 48134
```

#### Links

```yaml
links:
    github: https://github.com/timothyf
    linkedin: https://linkedin.com/in/timothyfisher/
    twitter: http://twitter.com/tfisher
```

#### Summary

```yaml
summary:
  developer:
    I am a passionate developer and leader with nearly 30 years of industry experience in roles that include
    both hands-on and leadership positions across organizations that range from small startups to large enterprises.
    ...

  leader:
    I am a passionate developer and leader with 29 years of software development experience in roles
    including Chief Technology Officer, VP of Engineering, Chief Architect, and Director of Mobile Development,
    along with many years of hands-on development experience.
    ...
```

#### Skills

```yaml
skills:
    - Team Leadership & Management
    - Microservices Architecture
    - Amazon Web Services (AWS), Heroku, EngineYard
    - Ruby, Rails, JavaScript, Node.js, React, ReactNative, Java, Swift, HTML, CSS
```

#### Jobs

```yaml
- title: Senior Java Architect
  company: LogicaCMG
  brief: false
  include: brief
  location:
    city: Southfield
    state: MI
  dates:
      start: 2003, February
      end: 2006, May
  desc: |
    Worked on a Web-based single login project for Ford Motor Company. Responsibilities include assisting with
    architecture, analysis, design, coding, and testing. Environment consisted of Websphere Application Server
    ...

- title: Development Team Lead
  company: MedCharge
  brief: false
  location:
    city: Ann Arbor
    state: MI
  dates:
      start: 2002, February
      end: 2003, January
  desc: |
    Led the J2EE development team at MedCharge, a startup whose product was a health care application
    used within the University of Michigan Medical Center. The product allows hospital staff to capture all
    ...
```

#### Education

```yaml
education:
    - name: University of Michigan
      degree: B.S. Electrical Engineering
      dates:
          start: Sept 1986
          end: May 1991

    - name: Capella University
      degree: M.S. Education
      dates:
          start: Sept 2001
          end: May 2003
```

#### Certifications

```yaml

```

#### Projects

```yaml

```

#### Volunteering

```yaml

```

#### Languages

```yaml

```

#### Interests

```yaml

```
