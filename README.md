# Bitbucket <-> Jenkins integration

Project to integrate bitbucket events into the continuos integration server Jenkins.

## Running the server

To launch the server:
> ruby server.rb -c <config_file>

Testing could be done:
> bash send_json_file.bash bitbucket_new_pr.json

## Installation

> sudo apt-get install -y ruby1.9.1-dev libxslt1-dev libsqlite3-ruby
> sudo gem install jenkins_api_client 

## Features

### Auto pull-request testing

The goal is to provide automatic continuos integration of bitbucket pull request into jenkins. 
Something like travis for github.

#### Using an external daemon to handle comunication

1. [done] Create a daemon to listen updates from bitbucket
1. [done] Make the daemon to launch jenkins job using remote calling
1. [done] Use jenkins API to call from the daemon
1. [    ] Make the daemon to know the state of the buildings
1. [    ] Comment in a bitbucket pull request as feedback from jenkins

#### Using a jenkins plugin

Fully integration of both systems
[issue 1](https://bitbucket.org/osrf/bitbucket-jenkins/issue/1)

### References

1. [Bitbucket REST API](https://confluence.atlassian.com/display/BITBUCKET/Use+the+Bitbucket+REST+APIs)
1. [Github <-> Jenkins integration](http://buddylindsey.com/jenkins-and-github-pull-requests/). [integration code](https://github.com/janinko/ghprb)
1. [Bibucket mercurial pull request post hook](https://confluence.atlassian.com/display/BITBUCKET/Pull+Request+POST+hook+management)
1. [Jenkins API for ruby](https://rubygems.org/gems/jenkins_api_client)
