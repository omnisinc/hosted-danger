require "uri"

module HostedDanger
  module Github
    module State
      ERROR   = "error"
      FAILURE = "failure"
      PENDING = "pending"
      SUCCESS = "success"
    end

    class GithubException < Exception
      property res : HTTP::Client::Response?
    end

    def get_pagination(url : String, access_token : String) : Array(JSON::Any)
      res_array = [] of JSON::Any

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.get(url, headers)

      github_result(res, url, "GET")

      res_array.concat(JSON.parse(res.body).as_a)

      if res.headers.has_key?("Link")
        if n = res.headers["Link"] =~ /.*<(.+?)>;\srel="next".*/
          res_array.concat(get_pagination($1, access_token))
        end
      end

      res_array
    end

    def api_base(git_host : String) : String
      ServerConfig.api_base_of(git_host)
    end

    def usr_all_repos(git_host : String, org : String, access_token : String) : Array(JSON::Any)
      get_pagination("#{api_base(git_host)}/users/#{org}/repos", access_token)
    end

    def org_all_repos(git_host : String, org : String, access_token : String) : Array(JSON::Any)
      get_pagination("#{api_base(git_host)}/orgs/#{org}/repos", access_token)
    end

    def all_repos(git_host : String, org : String, access_token : String) : Array(JSON::Any)
      begin
        org_all_repos(git_host, org, access_token)
      rescue e : GithubException
        usr_all_repos(git_host, org, access_token)
      end
    rescue e : GithubException
      raise "Tried to fetch all repos but it's failed. \n- #{api_base(git_host)}/orgs/#{org}/repo\n- #{api_base(git_host)}/users/#{org}/repos"
    end

    def pull_request_open?(git_host : String, org : String, repo : String, pr_number : Int32, access_token : String) : Bool
      pull_json = pull_request(git_host, org, repo, pr_number, access_token)
      pull_json["state"].as_s == "open"
    rescue e : Exception
      L.error e, pull_json.to_s

      true
    end

    def pull_request(git_host : String, org : String, repo : String, pr_number : Int32, access_token : String) : JSON::Any
      url = "#{api_base(git_host)}/repos/#{org}/#{repo}/pulls/#{pr_number}"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.get(url, headers)

      github_result(res, url, "GET")

      JSON.parse(res.body)
    end

    def pull_requests(git_host : String, org : String, repo : String, access_token : String) : Array(JSON::Any)
      get_pagination("#{api_base(git_host)}/repos/#{org}/#{repo}/pulls?state=open", access_token)
    end

    def issue_comments(git_host : String, org : String, repo : String, pr_number : Int32, access_token : String) : Array(JSON::Any)
      get_pagination("#{api_base(git_host)}/repos/#{org}/#{repo}/issues/#{pr_number}/comments", access_token)
    end

    def delete_comment(git_host : String, org : String, repo : String, comment_id : Int32, access_token : String)
      url = "#{api_base(git_host)}/repos/#{org}/#{repo}/issues/comments/#{comment_id}"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.delete(url, headers)

      github_result(res, url, "DELETE")

      res
    end

    def build_state_of(
      git_host : String,
      org : String,
      repo : String,
      sha : String,
      access_token : String
    ) : JSON::Any
      url = "#{api_base(git_host)}/repos/#{org}/#{repo}/commits/#{sha}/statuses"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.get(url, headers)

      github_result(res, url, "GET")

      JSON.parse(res.body)
    end

    def build_state(
      git_host : String,
      org : String,
      repo : String,
      sha : String,
      description : String,
      access_token : String,
      state : String,
      log_url : String? = nil,
      context : String = "danger/#{DANGER_ID}"
    )
      url = "#{api_base(git_host)}/repos/#{org}/#{repo}/statuses/#{sha}"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      target_url = if _log_url = log_url
                     _log_url
                   else
                     "https://#{git_host}/#{org}/#{repo}/commit/#{sha}"
                   end

      body = {
        state:       state,
        target_url:  target_url,
        description: description,
        context:     context,
      }.to_json

      res = HTTP::Client.post(url, headers, body)

      github_result(res, url, "POST")

      JSON.parse(res.body)
    end

    def fetch_file(
      git_host : String,
      org : String,
      repo : String,
      sha : String,
      file : String,
      access_token : String,
      dir : String
    ) : String?
      url = "#{ServerConfig.raw_base_of(git_host)}/#{org}/#{repo}/#{sha}/#{file}?token=#{access_token}"

      L.info "fetching file on #{org}/#{repo}/#{file}"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.get(url, headers)

      return nil if res.status_code == 404

      L.info "---> fetched!"

      file_content = res.body.to_s

      File.write("#{dir}/#{file}", file_content)

      file_content
    end

    def compare(git_host : String, org : String, repo : String, access_token : String, base_label : String, head_label : String) : JSON::Any
      url = "#{api_base(git_host)}/repos/#{org}/#{repo}/compare/#{URI.escape(base_label)}...#{URI.escape(head_label)}"

      headers = HTTP::Headers.new
      headers["Authorization"] = "token #{access_token}"

      res = HTTP::Client.get(url, headers)

      github_result(res, url, "GET")

      JSON.parse(res.body)
    end

    def github_result(res : HTTP::Client::Response, url : String, method : String)
      #
      # repository without app user as collaborator or the app user doesn't have write role
      #
      if res.status_code == 404
        message = begin
          "Github API returns 404 ( #{git_url_from_api_url(url)} )\n"
        rescue
          "Github API returns 404 ( API: #{url} )\n"
        end

        if method == "GET"
          message += "Reason: **private repository without app user collaborator**\n"
        else
          message += "Reason: **public repository without app user collaborator**\n"
        end

        message += "```\n"
        message += "url    : #{url}\n"
        message += "method : #{method}\n"
        message += "```"

        github_exception = GithubException.new(message)
        github_exception.res = res

        raise github_exception
      end
    end

    include Parser
  end
end
