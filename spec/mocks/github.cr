module HostedDangerMocks
  module Github
    def pull_request_open?(git_host : String, org : String, repo : String, pr_number : Int32, access_token : String) : Bool
      true
    end

    def pull_request(git_host : String, org : String, repo : String, pr_number : Int32, access_token : String) : JSON::Any
      JSON.parse(File.read(File.expand_path("../../api/pull.json", __FILE__)))
    end

    def pull_requests(git_host : String, org : String, repo : String, access_token : String) : Array(JSON::Any)
      JSON.parse(File.read(File.expand_path("../../api/pulls.json", __FILE__))).as_a
    end

    def build_state_of(
      git_host : String,
      org : String,
      repo : String,
      sha : String,
      access_token : String
    ) : JSON::Any
      JSON.parse(%({"test": "ok"}))
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
    ) : JSON::Any
      JSON.parse(%({"test": "ok"}))
    end
  end
end
