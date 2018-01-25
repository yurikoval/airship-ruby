require "faraday"
require "json"

=begin
AirshipClient.init("r9b72kqdh1wbzkpkf7gntwfapqoc26bl", "nxmqp35umrd3djth")
AirshipClient.set_env_key("c1087mh6a3hjxiaz")
client = AirshipClient.new
client = AirshipClient.new("nxmqp35umrd3djth")
client = AirshipClient.new("c1087mh6a3hjxiaz")

1. Error checking for the keys
2. identify and gate endpoint
client.get_value("<control_name>", <obj>)     -> [false, true]
client.get_variation("<control_name>", <obj>) -> [nil, "<variation1>", "<variation2">, ...]
client.identify([<obj>, ...])                 -> dictionary
client.gate(<obj>)                            -> dictionary
=end

API_BASE_ENDPOINT = "https://api.airshiphq.com"
V1_IDENTIFY_ENDPOINT = "/v1/identify"
V1_GATE_ENDPOINT = "/v1/gate"

DEFAULT_TIMEOUT = 2

SERVER_INFO_KEY = "server_info"
SERVER_STATE_MAINTENANCE = "maintenance"


class AirshipClient
  @@api_key = nil
  @@env_key = nil
  @@timeout = DEFAULT_TIMEOUT
  @@fail_gracefully = true

  @api_key = nil
  @env_key = nil
  @conn = nil

  class << self
    def init(api_key, env_key = nil, timeout = DEFAULT_TIMEOUT, fail_gracefully = true)
      if api_key.nil?
        raise ArgumentError.new("api_key cannot be nil")
      end

      if !api_key.nil?
        self._validate_api_key(api_key)
      end

      if !env_key.nil?
        self._validate_env_key(env_key)
      end

      self._validate_timeout(timeout)
      self._validate_fail_gracefully(fail_gracefully)

      @@api_key = api_key
      @@env_key = env_key
      @@timeout = timeout
      @@fail_gracefully = fail_gracefully
      nil
    end

    def set_env_key(env_key)
      if env_key.nil?
        raise ArgumentError.new("env_key cannot be nil")
      end
      self._validate_env_key(env_key)
      @@env_key = env_key
    end

    def _validate_api_key(api_key)
      if !api_key.instance_of?(String)
        raise ArgumentError.new("api_key must be a string")
      end
    end

    def _validate_env_key(env_key)
      if !env_key.instance_of?(String)
        raise ArgumentError.new("env_key must be a string")
      end
    end

    def _validate_timeout(timeout)
      if !timeout.is_a?(Integer)
        raise ArgumentError.new("timeout must be an integer")
      end
    end

    def _validate_fail_gracefully(fail_gracefully)
      if !(fail_gracefully == true || fail_gracefully == false)
        raise ArgumentError.new("fail_gracefully must be true or false")
      end
    end
  end

  def initialize(api_key = nil, env_key = nil)
    if !api_key.nil?
      self.class._validate_api_key(api_key)
    end

    if !env_key.nil?
      self.class._validate_env_key(env_key)
    end

    @api_key = api_key
    @env_key = env_key
    @conn = Faraday.new(:url => API_BASE_ENDPOINT)
    nil
  end

  def identify(objs)
    if !objs.instance_of?(Array)
      objs = [objs]
    end
    begin
      response = @conn.post do |req|
        req.url(V1_IDENTIFY_ENDPOINT)
        req.headers["Content-Type"] = "application/json"
        req.headers["api-key"] = @api_key || @@api_key
        req.options.timeout = @@timeout
        request_obj = {}
        request_obj["env_key"] = @env_key || @@env_key
        request_obj["objects"] = objs
        req.body = request_obj.to_json
      end
      result = JSON.parse(response.body)
      result
    rescue Faraday::TimeoutError => e
      raise
    end
  end

  def gate(control_name, obj)
    begin
      response = @conn.post do |req|
        req.url(V1_GATE_ENDPOINT)
        req.headers["Content-Type"] = "application/json"
        req.headers["api-key"] = @api_key || @@api_key
        req.options.timeout = @@timeout
        request_obj = {}
        request_obj["env_key"] = @env_key || @@env_key
        request_obj["control_short_name"] = control_name
        request_obj["object"] = obj
        req.body = request_obj.to_json
      end
      result = JSON.parse(response.body)
      if result[SERVER_INFO_KEY] == SERVER_STATE_MAINTENANCE
        if @@fail_gracefully
          return {
            "type" => obj["type"],
            "id" => obj["id"],
            "display_name" => obj["display_name"],
            "control" => {
              "control_short_name" => control_name,
              "value" => false,
              "variation" => nil,
              "from_server" => false,
              "from_cache" => false
            }
          }
        end
      end
      result
    rescue Faraday::TimeoutError => e
      if @@fail_gracefully
        return {
          "type" => obj["type"],
          "id" => obj["id"],
          "display_name" => obj["display_name"],
          "control" => {
            "control_short_name" => control_name,
            "value" => false,
            "variation" => nil,
            "from_server" => false,
            "from_cache" => false
          }
        }
      else
        raise
      end
    end
  end

  def get_value(control_name, obj)
    result = self.gate(control_name, obj)
    result["control"]["value"]
  end

  def get_variation(control_name, obj)
    result = self.gate(control_name, obj)
    result["control"]["variation"]
  end
end
