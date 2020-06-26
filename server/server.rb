=begin

  Copyright 2013 Open Source Robotics Foundation
 
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
 
      http://www.apache.org/licenses/LICENSE-2.0
 
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

=end

require 'webrick'
require 'json'
require 'pp'
require 'yaml'
require 'open-uri'
require 'optparse'
require 'time'
require 'rubygems'
require 'jenkins_api_client'
 
include WEBrick

# TODO: decline a pull request define the pr_url in a different path:
# "repository" -> "links" -> "html"
# Refactor this class to handle different sources of json data
class PullRequestInfo

  def initialize json_pr, pr_status
    begin
      @BITBUCKET_URL = "https://bitbucket.org/"

      @metadata = { "short_src_repo_name"  => json_pr['source']['repository']['full_name'],
                    "short_dest_repo_name" => json_pr['destination']['repository']['full_name'],
                    "pr_title"               => json_pr['title'],
                    "pr_initial_description" => json_pr['description'],
                    "pr_url"                 => json_pr['links']['html']['href'] }

      # Params to be sent to jenkins
      # BRANCH only used for backward compatibility
      @params = { "BRANCH"         => json_pr['source']['branch']['name'],
                  "SRC_BRANCH"     => json_pr['source']['branch']['name'],
                  "SRC_REPO"       => @BITBUCKET_URL + @metadata["short_src_repo_name"],
                  "DEST_BRANCH"    => json_pr['destination']['branch']['name'],
                  "DEST_REPO"      => @BITBUCKET_URL + @metadata["short_dest_repo_name"],
                  "PR_LAST_COMMIT" => json_pr['source']['commit']['hash']}

      @params["JOB_DESCRIPTION"] = build_jenkins_job_description()

      @pr_status = pr_status
    end
  end

  def build_jenkins_job_description
     "<a href=\"" + @metadata['pr_url'] + "\">PR: " + @metadata['pr_title'] + "</a><br />" +
     "branch: " + @params['SRC_BRANCH'] + " -> " + @params['DEST_BRANCH'] + "<br />" +
     "repo: " + @metadata['short_src_repo_name'] + " -> " + @metadata['short_dest_repo_name']
  end

  def get_status_msg
    case @pr_status
      when :new
        str = "new pull request"
      when :update
        str = "pull request updated"
      else
        str = "unknown pull request status"
    end
  str
  end

  def print
    pp @params if $DEBUG

    begin
      p " ====== " + @metadata["pr_title"] + " ====== "
      p "   - PR status    : " + get_status_msg()
      p "   - project      : " + get_config_file_project_name()
      if is_valid_for_execution()
        p "   - repositories : " + @params["SRC_REPO"] + " -> " + @params["DEST_REPO"]
        p "   - branches     : " + @params["SRC_BRANCH"] + " -> " + @params["DEST_BRANCH"]
        p "   - pr_url       : " + @metadata["pr_url"]
        p "   - pr_commit    : " + @params["PR_LAST_COMMIT"]
        p "   - job_desc     : " + @params["JOB_DESCRIPTION"]
      else
        p " !!! build run is disabled by policy "
      end
    end
  end

  def get_params
    begin
      @params
    end
  end

  ##
  # return the project name as it appears in the config file (i.e.
  # osrf/sdformat)
  def get_config_file_project_name
    @metadata["short_dest_repo_name"]
  end

  # some builds are not going to be executed due to internal policy
  # Gazebo updates are disabled
  def is_valid_for_execution
    (@metadata["short_dest_repo_name"] == "osrf/gazebo" and @pr_status == :update) ? false : true
  end
end

class RestServlet < HTTPServlet::AbstractServlet
  
  def initialize server, config
    super server
    load_config(config)

    # create the jenkins api client
    @jenkins_client = JenkinsApi::Client.new(:server_url => @server_url,
                                             :username   => @jenkins_user,
                                             :password   => @jenkins_pass)
  end

  # Get the first key of the first element
  def get_json_bitbucket_action header
    header['x-event-key'][0]
  end

  def get_jenkins_jobs_from_project project
    @projects[project]
  end

  def load_config config
    pp config if $DEBUG

    @server_url       = config["jenkins_server"]["url"]
    @jenkins_user     = config["jenkins_server"]["user"]
    @jenkins_pass     = config["jenkins_server"]["pass"]
    
    @projects         = config["projects"]
  end

  def do_POST req, resp
    json_call = JSON.parse(req.body)
    pp json_call if $DEBUG
    bitbucket_action = get_json_bitbucket_action(req.header)

    t = Thread.new {
      print "Bitbucket action: " if $DEBUG
      pp  bitbucket_action if $DEBUG
      case bitbucket_action
        when 'pullrequest:created'
          process_pull_request(json_call['pullrequest'], :new)
        when 'pullrequest:updated'
          process_pull_request(json_call['pullrequest'], :update)
        when 'pullrequest:fulfilled'
          process_pull_request_close(json_call['pullrequest'])
        when 'pullrequest:rejected'
          process_pull_request_close(json_call['pullrequest'])
        else
          print " [!!] Received an unknown action type from bitbucket: "
          pp bitbucket_action
      end
    }
  end

  def build_pr_info json_call, status
    pr_info = PullRequestInfo.new(json_call, status)
    pr_info.print()
    pr_info
  end

  def process_pull_request json_call, status
    p "Data from new pull request"
    pr_info = build_pr_info(json_call, status)

    return if not pr_info.is_valid_for_execution()

    # get the jenkins calls corresponding to destination repository
    pp "Parameters: " if $DEBUG
    pp pr_info.get_params() if $DEBUG
    list_of_jenkins_calls = process_project_jobs(pr_info)

    p "List of jenkins_calls done: " if $DEBUG
    pp list_of_jenkins_calls if $DEBUG
  end

  def process_pull_request_close json_call
    p "Pull request closed!"
  end
  
  ##
  # will return a list of pairs: [job_name],[build_num] host the successful calls
  #
  def process_project_jobs pr_info
    osrf_project = pr_info.get_config_file_project_name()
    params       = pr_info.get_params()

    jobs = get_jenkins_jobs_from_project(osrf_project)
    if jobs.nil?
      p "No jobs found for project: " + osrf_project
      return []
    end
    pp jobs if $DEBUG
    
    # To host the jenkins job information of calls done
    call_list =[]

    # Process each of the defined jobs in the config file
    jobs.each { |j| 
      begin
        job_name = j['job']
        build_num = launch_jenkins_job(job_name, params)
        
        call_list << { "build_num" => build_num, "job_name" => job_name }
      rescue Exception => e  
        p " [!!] Bad response from jenkins when launching: #{j['job']}"
        p e.message
      end
    }

    return call_list
  end

  def launch_jenkins_job job_name, params
    p "Calling jenkins job: " + job_name    
    build_num = @jenkins_client.job.build(job_name, params, { 'build_start_timeout' => 30 })
    p "Jenkins job: #{job_name} launched. Build number: #{build_num}" if $DEBUG

    return build_num
  end
end

# Main program
#
# Parse options
options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: server.rb [options]"

  opts.on('-c','--configfile FILE', 
          'Configuration file for server') do |v| 
      options[:configfile] = v 
  end
end
opts.parse(ARGV)

pp options

# Read configuration and launch the server
begin
  config = YAML.load_file(options[:configfile])
rescue Psych::SyntaxError => e
  p "Error in YAML config file syntax"
  pp e
end

pp "Yaml config: " if $DEBUG
pp config if $DEBUG

server = WEBrick::HTTPServer.new(:Port => config['config']['server']['port'])
server.mount "/", RestServlet, config['config']
['INT', 'TERM'].each {|signal|
  trap(signal) {server.shutdown}
}
server.start
