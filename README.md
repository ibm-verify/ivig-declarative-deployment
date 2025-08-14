# {project_title}

Describe your project in one sentence.

## Goals and Scope

Describe the project in more detail, covering the motivation and value
proposition, stated goals and scope definition. It is preferred, but not
mandatory to include a simple schematic diagram to show the main functionality,
components involved and the connections between the components. The diagram
should represent the main concept only and not be overloaded with details.

**Note:** Document well defined goals for each phase. Goals should be specific,
measurable, result oriented and time-bound. Information on timeline or schedule
do not need to be documented here, but it is assumed that goals of any phase are
attainable within four weeks.

### Scenarios

Enumerate the scenarios to provide a more detailed explanation of the
functionality provided by the project.

## Components and Dependencies

Provide a listing of both internal and third party components along with the
exact versions used. The version listing is preferred to be provided in tabular
form, covering initial versions, and further versions are known to work or have
been tested during the lifecycle of the project.

**Important:** This section should be reviewed and updated at least annually
even if there is no active development on the project. This is to ensure that
deprecation of certain components will not go by unnoticed and the compatibility
with newer versions is regularly evaluated and documented.

### Third Party Components and Dependencies

Any third party component (including libraries) should be documented, including
licensing information, location of install media or method of installation and
special instruction as necessary.

Further, any framework, toolchain or programming language used to build custom
components should be listed along with the required versions. This listing may
optionally be moved to a separate document within the `docs` folder.

### System Requirements

Recommended hardware resources and infrastructure requirements for a
non-production setup should be documented. 

## Setup guide

Detailed installation documentation is best provided in a separate markdown file
under the `docs` folder, in which case this section should merely link to that
file.

The installation guide should be a detailed, step-by-step document on how to
build an deploy the project. It is encouraged to include command listings and
sample config files which may typically reflect the parameters used to build a
lab or demo environment. The guide should draw attention to the differences
between a lab and a production setup in the form of bullet points within the
installation guide, or alternatively, a separate hardening guide may be
provided.

### Install Verification Test

Document scripted or manual smoke tests.

Smoke tests are a subset of test cases that cover the most important
functionality of a component or system, used to aid assessment of whether main
functions of the software appear to work correctly.

### Troubleshooting guide

Document typical symptoms and their potential root causes.

Provide guidance on debugging, e.g. location of log files, ways to adjust log
levels, procedures to perform root cause analysis, and point the user to further
resources that aid in debugging different components.

## Future plans

This optional section may contain near and mid term plans, uncommitted feature
candidates and general information about the future of the project.

## Further Documentation

This section should point the reader to further documentation within the
repository (resources in the `docs` folder) or outside of the repository (SKE).

- [Guidelines for Contributors](docs/CONTRIBUTING.md)
- [Changelog for Developers](CHANGES.md) 
- Installation Guide, How-To guides
- Marketing flyers, Offering and Asset Information
- Demos, videos, training material

## Contacts

Project team or at least a focal point should be provided. A disclaimer on
support policy is also preferred to be included, e.g.:

*This project is supported on a best effort basis by the contributors in spare
time. Issues should be reported via GitHub. Maintenance and development of
enhancements may be provided on a commercial basis, depending on the
availability of the project team.*

