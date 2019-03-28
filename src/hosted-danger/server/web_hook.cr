module HostedDanger
  class WebHook
    def initialize
      [
        "pull_request",
        "pull_request_review",
        "pull_request_review_comment",
        "issue_comment",
        "issues",
        "status",
      ].each do |event|
        Metrics.register("event_#{event}", "counter", "Number of requests for #{event} event")
      end
    end

    def new_request(event : String)
      Metrics.increment("event_#{event}")
    end

    def retriable(&block)
      retry_count = 3
      retry_count.times do |i|
        yield
        break
      rescue e : Exception
        raise e if !retry?(e) || i >= retry_count - 1
        sleep 0.1
      end
    end

    def retry?(e : Exception)
      m = e.message || ""
      b = (e.backtrace? || [] of String).join("") rescue ""

      (m + b).includes?("getaddrinfo")
    end

    def hook(context, params)
      payload_json = create_payload_json(context)
      executables? = create_executable(context, payload_json)

      spawn do
        if executables = executables?
          executables.each do |executable|
            retriable do
              executor = Executor.new(executable)
              executor.exec_danger
            end
          end
        end
      rescue e : Exception
        case e
        when Github::GithubException
          L.error e, e.res.inspect, false
        else
          L.error e, payload_json.to_json
        end
      end

      context.response.status_code = 200
      context.response.print "OK"
      context

    rescue e : Exception
      bad_request(context)
    end

    def bad_request(context)
      context.response.status_code = 400
      context.response.print "Bad Request"
      context
    end

    def create_payload_json(context) : JSON::Any
      payload : String = if body = context.request.body
        body.gets_to_end
      else
        raise "Empty body"
      end

      return JSON.parse(payload) if context.request.headers["content-type"] == "application/json"
      return JSON.parse(URI.unescape(payload.lchop("payload="))) if payload.starts_with?("payload=")

      raise "Unknown payload type"
    end

    def parse_query_params(context) : HTTP::Params
      HTTP::Params.parse(context.request.query || "")
    end

    def create_executable(context, payload_json) : Array(Executable)?
      event = context.request.headers["X-GitHub-Event"]

      query_params = parse_query_params(context)

      return e_pull_request(event, payload_json, query_params) if event == "pull_request"
      return e_pull_request_review(event, payload_json, query_params) if event == "pull_request_review"
      return e_pull_request_review_comment(event, payload_json, query_params) if event == "pull_request_review_comment"
      return e_issue_comment(event, payload_json, query_params) if event == "issue_comment"
      return e_issues(event, payload_json, query_params) if event == "issues"
      return e_status(event, payload_json, query_params) if event == "status"

      L.info "danger will not be triggered (#{event})"
    end

    def e_pull_request(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)

      new_request(event)

      action = payload_json["action"].as_s
      html_url = payload_json["repository"]["html_url"].as_s
      pr_number = payload_json["number"].as_i
      sha = payload_json["pull_request"]["head"]["sha"].as_s
      head_label = payload_json["pull_request"]["head"]["label"].as_s
      base_label = payload_json["pull_request"]["base"]["label"].as_s
      env = query_params.to_h

      [{
        action:      action,
        event:       event,
        html_url:    html_url,
        pr_number:   pr_number,
        sha:         sha,
        head_label:  head_label,
        base_label:  base_label,
        raw_payload: payload_json.to_json,
        env:         env,
      }]
    end

    def e_pull_request_review(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)
      return L.info "#{event} skip: dismissed" if payload_json["action"] == "dismissed"

      new_request(event)

      action = payload_json["action"].as_s
      html_url = payload_json["repository"]["html_url"].as_s
      pr_number = payload_json["pull_request"]["number"].as_i
      sha = payload_json["pull_request"]["head"]["sha"].as_s
      head_label = payload_json["pull_request"]["head"]["label"].as_s
      base_label = payload_json["pull_request"]["base"]["label"].as_s
      env = query_params.to_h

      [{
        action:      action,
        event:       event,
        html_url:    html_url,
        pr_number:   pr_number,
        sha:         sha,
        head_label:  head_label,
        base_label:  base_label,
        raw_payload: payload_json.to_json,
        env:         env,
      }]
    end

    def e_pull_request_review_comment(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)
      return L.info "#{event} skip: deleted" if payload_json["action"] == "deleted"

      new_request(event)

      action = payload_json["action"].as_s
      html_url = payload_json["repository"]["html_url"].as_s
      pr_number = payload_json["pull_request"]["number"].as_i
      sha = payload_json["pull_request"]["head"]["sha"].as_s
      head_label = payload_json["pull_request"]["head"]["label"].as_s
      base_label = payload_json["pull_request"]["base"]["label"].as_s
      env = query_params.to_h

      [{
        action:      action,
        event:       event,
        html_url:    html_url,
        pr_number:   pr_number,
        sha:         sha,
        head_label:  head_label,
        base_label:  base_label,
        raw_payload: payload_json.to_json,
        env:         env,
      }]
    end

    def e_issue_comment(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)
      return L.info "#{event} skip: deleted" if payload_json["action"] == "deleted"

      if payload_json["issue"]["html_url"].as_s =~ /(.*)\/pull\/(.*)/
        new_request(event)

        action = payload_json["action"].as_s
        html_url = $1.to_s
        pr_number = $2.to_i

        env = query_params.to_h
        env["DANGER_PR_COMMENT"] = payload_json["comment"]["body"].as_s

        git_host = git_host_from_html_url(html_url)
        access_token = access_token_from_git_host(git_host)
        org, repo = org_repo_from_html_url(html_url)

        pull_json = pull_request(git_host, org, repo, pr_number, access_token)

        return [{
          action:      action,
          event:       event,
          html_url:    html_url,
          pr_number:   pr_number,
          sha:         pull_json["head"]["sha"].as_s,
          head_label:  pull_json["head"]["label"].as_s,
          base_label:  pull_json["base"]["label"].as_s,
          raw_payload: payload_json.to_json,
          env:         env,
        }]
      end

      nil
    end

    def e_issues(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)
      return L.info "#{event} skip: closed" if payload_json["action"] == "closed"

      if payload_json["issue"]["html_url"].as_s =~ /(.*)\/pull\/(.*)/
        new_request(event)

        action = payload_json["action"].as_s
        html_url = $1.to_s
        pr_number = $2.to_i
        env = query_params.to_h

        git_host = git_host_from_html_url(html_url)
        access_token = access_token_from_git_host(git_host)
        org, repo = org_repo_from_html_url(html_url)

        pull_json = pull_request(git_host, org, repo, pr_number, access_token)

        return [{
          action:      action,
          event:       event,
          html_url:    html_url,
          pr_number:   pr_number,
          sha:         pull_json["head"]["sha"].as_s,
          head_label:  pull_json["head"]["label"].as_s,
          base_label:  pull_json["base"]["label"].as_s,
          raw_payload: payload_json.to_json,
          env:         env,
        }]
      end
    end

    def e_status(event, payload_json, query_params) : Array(Executable)?
      return nil if ignore?(payload_json["sender"]["login"].as_s, event)

      new_request(event)

      action = payload_json["state"].as_s
      html_url = payload_json["repository"]["html_url"].as_s
      git_host = git_host_from_html_url(html_url)
      access_token = access_token_from_git_host(git_host)
      env = query_params.to_h

      sha = payload_json["sha"].as_s
      org, repo = org_repo_from_html_url(html_url)

      pulls_json = pull_requests(git_host, org, repo, access_token)

      executables = [] of Executable

      pulls_json.each do |pull_json|
        executables << {
          action:      action,
          event:       event,
          html_url:    html_url,
          pr_number:   pull_json["number"].as_i,
          sha:         sha,
          head_label:  pull_json["head"]["label"].as_s,
          base_label:  pull_json["base"]["label"].as_s,
          raw_payload: payload_json.to_json,
          env:         env,
        } if pull_json["head"]["sha"].as_s == sha
      end

      executables
    end

    def ignore?(user : String, event : String) : Bool
      if ServerConfig.ignore?(user, event)
        L.info "#{event} skip: sernder is #{user}"
        return true
      end

      false
    end

    include Github
    include Parser
  end
end
