require 'faraday'
require 'json'
require 'concurrent'
require 'digest'
require 'rubygems'
require 'json-schema'
require 'time'
require 'date'


class Airship
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "type" => {
        "type" => "string",
        "pattern" => "^([A-Z][a-zA-Z]*)+$",
        "maxLength" => 50,
      },
      "is_group" => {
        "type" => "boolean",
      },
      "id" => {
        "type" => ["string", "integer"],
        "maxLength" => 250,
        "minLength" => 1,
      },
      "display_name" => {
        "type" => "string",
        "maxLength" => 250,
        "minLength" => 1,
      },
      "attributes" => {
        "type" => "object",
        "patternProperties" => {
          "^[a-zA-Z][a-zA-Z_]{0,48}[a-zA-Z]$" => {
            "oneOf" => [
              {
                "type" => "string",
                "maxLength" => 3000,
              },
              {
                "type" => "boolean"
              },
              {
                "type" => "number"
              },
            ],
          },
        },
        "maxProperties" => 100,
        "additionalProperties" => false,
      },
      "group" => {
        "type" => ["object", "null"],
        "properties" => {
          "type" => {
            "type" => "string",
            "pattern" => "^([A-Z][a-zA-Z]*)+$",
            "maxLength" => 50,
          },
          "is_group" => {
            "type" => "boolean",
            "enum" => [true],
          },
          "id" => {
            "type" => ["string", "integer"],
            "maxLength" => 250,
            "minLength" => 1,
          },
          "display_name" => {
            "type" => "string",
            "maxLength" => 250,
            "minLength" => 1,
          },
          "attributes" => {
            "type" => "object",
            "patternProperties" => {
              "^[a-zA-Z][a-zA-Z_]{0,48}[a-zA-Z]$" => {
                "oneOf" => [
                  {
                    "type" => "string",
                    "maxLength" => 3000,
                  },
                  {
                    "type" => "boolean"
                  },
                  {
                    "type" => "number"
                  },
                ],
              },
            },
            "maxProperties" => 100,
            "additionalProperties" => false,
          },
        },
        "required" => ["id", "display_name"],
        "additionalProperties" => false,
      },
    },
    "required" => ["id", "display_name"],
    "additionalProperties" => false,
  }

  SERVER_URL = 'https://api.airshiphq.com'
  IDENTIFY_ENDPOINT = "#{SERVER_URL}/v1/identify"
  GATING_INFO_ENDPOINT = "#{SERVER_URL}/v1/gating-info"
  PLATFORM = 'ruby'
  VERSION = Gem::Specification::load(
    File.join(
      File.dirname(
        File.dirname(
          File.expand_path(__FILE__)
        )
      ),
      'airship-ruby.gemspec'
    )
  ).version.to_s

  SDK_VERSION = "#{PLATFORM}:#{VERSION}"

  CONTROL_TYPE_BOOLEAN = 'boolean'
  CONTROL_TYPE_MULTIVARIATE = 'multivariate'

  DISTRIBUTION_TYPE_RULE_BASED = 'R'
  DISTRIBUTION_TYPE_PERCENTAGE_BASED = 'P'

  OBJECT_ATTRIBUTE_TYPE_STRING = 'STRING'
  OBJECT_ATTRIBUTE_TYPE_INT = 'INT'
  OBJECT_ATTRIBUTE_TYPE_FLOAT = 'FLOAT'
  OBJECT_ATTRIBUTE_TYPE_BOOLEAN = 'BOOLEAN'
  OBJECT_ATTRIBUTE_TYPE_DATE = 'DATE'
  OBJECT_ATTRIBUTE_TYPE_DATETIME = 'DATETIME'

  RULE_OPERATOR_TYPE_IS = 'IS'
  RULE_OPERATOR_TYPE_IS_NOT = 'IS_NOT'
  RULE_OPERATOR_TYPE_IN = 'IN'
  RULE_OPERATOR_TYPE_NOT_IN = 'NOT_IN'
  RULE_OPERATOR_TYPE_LT = 'LT'
  RULE_OPERATOR_TYPE_LTE = 'LTE'
  RULE_OPERATOR_TYPE_GT = 'GT'
  RULE_OPERATOR_TYPE_GTE = 'GTE'
  RULE_OPERATOR_TYPE_FROM = 'FROM'
  RULE_OPERATOR_TYPE_UNTIL = 'UNTIL'
  RULE_OPERATOR_TYPE_AFTER = 'AFTER'
  RULE_OPERATOR_TYPE_BEFORE = 'BEFORE'

  @@sdk_id = [('a'..'z'), ('A'..'Z'), (0..9)].map(&:to_a).flatten.sample(6).join('')

  class << self
    def get_hashed_value(s)
      Digest::MD5.hexdigest(s).to_i(base=16).fdiv(340282366920938463463374607431768211455)
    end
  end

  def initialize(options)

    @api_key = options[:api_key]
    @env_key = options[:env_key]

    if @api_key.nil?
      raise Exception.new('Missing api_key')
    end

    if @env_key.nil?
      raise Exception.new('Missing env_key')
    end

    @gating_info = nil
    @gating_info_downloader_task = nil
    @gating_info_polling_interval = 60

    @gating_info_map = nil

    @max_gate_stats_batch_size = 500
    @gate_stats_upload_batch_interval = 60

    @gate_stats_watcher = nil
    @gate_stats_last_task_scheduled_timestamp = 0

    @gate_stats_uploader_tasks = []

    @gate_stats_batch = []

    @initialization_lock = Concurrent::Semaphore.new(1)
    @gate_stats_batch_lock = Concurrent::Semaphore.new(1)

    @first_gate = true
  end

  def init
    @initialization_lock.acquire
    if @gating_info_downloader_task.nil?
      self._poll
      if @gating_info.nil?
        @initialization_lock.release
        raise Exception.new('Failed to connect to Airship server')
      end
      @gating_info_downloader_task = self._create_poller
      @gating_info_downloader_task.execute
    end

    if @gate_stats_watcher.nil?
      @gate_stats_watcher = self._create_watcher
      @gate_stats_watcher.execute
    end
    @initialization_lock.release
    self
  end

  def enabled?(control_short_name, object, default_value=false)
    validation_errors = JSON::Validator.fully_validate(SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return default_value
    end

    object = self._clone_object(object)

    if object['type'].nil?
      object['type'] = 'User'
    end

    error = self._validate_nesting(object) || self._maybe_transform_id(object)

    if !error.nil?
      puts error
      return default_value
    end

    if @gating_info_map.nil?
      return default_value
    end

    gate_timestamp = Time.now.iso8601

    start = Time.now

    gate_values = self._get_gate_values(control_short_name, object)
    is_enabled = gate_values['is_enabled']
    variation = gate_values['variation']
    is_eligible = gate_values['is_eligible']
    _should_send_stats = gate_values['_should_send_stats']

    finish = Time.now

    if _should_send_stats
      sdk_gate_timestamp = gate_timestamp
      sdk_gate_latency = "#{(finish - start) * 1000 * 1000}us"
      sdk_version = SDK_VERSION

      stats = {}
      stats['sdk_gate_control_short_name'] = control_short_name
      stats['sdk_gate_timestamp'] = sdk_gate_timestamp
      stats['sdk_gate_latency'] = sdk_gate_latency

      stats['sdk_gate_value'] = is_enabled
      stats['sdk_gate_variation'] = variation
      stats['sdk_gate_eligibility'] = is_eligible
      stats['sdk_gate_type'] = 'value'

      self._enrich_with_metadata(control_short_name, stats)

      stats['sdk_version'] = sdk_version
      stats['sdk_id'] = @@sdk_id

      object['stats'] = stats

      self._upload_stats_async(object)
    end

    return is_enabled
  end

  def variation(control_short_name, object, default_value=nil)
    validation_errors = JSON::Validator.fully_validate(SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return default_value
    end

    object = self._clone_object(object)

    if object['type'].nil?
      object['type'] = 'User'
    end

    error = self._validate_nesting(object) || self._maybe_transform_id(object)

    if !error.nil?
      puts error
      return default_value
    end

    if @gating_info_map.nil?
      return default_value
    end

    gate_timestamp = Time.now.iso8601

    start = Time.now

    gate_values = self._get_gate_values(control_short_name, object)
    is_enabled = gate_values['is_enabled']
    variation = gate_values['variation']
    is_eligible = gate_values['is_eligible']
    _should_send_stats = gate_values['_should_send_stats']

    finish = Time.now

    if _should_send_stats
      sdk_gate_timestamp = gate_timestamp
      sdk_gate_latency = "#{(finish - start) * 1000 * 1000}us"
      sdk_version = SDK_VERSION

      stats = {}
      stats['sdk_gate_control_short_name'] = control_short_name
      stats['sdk_gate_timestamp'] = sdk_gate_timestamp
      stats['sdk_gate_latency'] = sdk_gate_latency

      stats['sdk_gate_value'] = is_enabled
      stats['sdk_gate_variation'] = variation
      stats['sdk_gate_eligibility'] = is_eligible
      stats['sdk_gate_type'] = 'variation'

      self._enrich_with_metadata(control_short_name, stats)

      stats['sdk_version'] = sdk_version
      stats['sdk_id'] = @@sdk_id

      object['stats'] = stats

      self._upload_stats_async(object)
    end

    return variation
  end

  def eligible?(control_short_name, object, default_value=false)
    validation_errors = JSON::Validator.fully_validate(SCHEMA, object)
    if validation_errors.size > 0
      puts validation_errors[0]
      return default_value
    end

    object = self._clone_object(object)

    if object['type'].nil?
      object['type'] = 'User'
    end

    error = self._validate_nesting(object) || self._maybe_transform_id(object)

    if !error.nil?
      puts error
      return default_value
    end

    if @gating_info_map.nil?
      return default_value
    end

    gate_timestamp = Time.now.iso8601

    start = Time.now

    gate_values = self._get_gate_values(control_short_name, object)
    is_enabled = gate_values['is_enabled']
    variation = gate_values['variation']
    is_eligible = gate_values['is_eligible']
    _should_send_stats = gate_values['_should_send_stats']

    finish = Time.now

    if _should_send_stats
      sdk_gate_timestamp = gate_timestamp
      sdk_gate_latency = "#{(finish - start) * 1000 * 1000}us"
      sdk_version = SDK_VERSION

      stats = {}
      stats['sdk_gate_control_short_name'] = control_short_name
      stats['sdk_gate_timestamp'] = sdk_gate_timestamp
      stats['sdk_gate_latency'] = sdk_gate_latency

      stats['sdk_gate_value'] = is_enabled
      stats['sdk_gate_variation'] = variation
      stats['sdk_gate_eligibility'] = is_eligible
      stats['sdk_gate_type'] = 'eligibility'

      self._enrich_with_metadata(control_short_name, stats)

      stats['sdk_version'] = sdk_version
      stats['sdk_id'] = @@sdk_id

      object['stats'] = stats

      self._upload_stats_async(object)
    end

    return is_eligible
  end

  protected

  def _enrich_with_metadata(control_short_name, stats)
    control_info = @gating_info_map[control_short_name]

    if !control_info.nil?
      stats['sdk_gate_control_id'] = control_info['id']
    end

    stats['sdk_env_id'] = @gating_info['env']['id']
  end

  def _get_gating_info_map(gating_info)
    map = {}

    controls = gating_info['controls']

    controls.each do |control|
      control_info = {}

      control_info['id'] = control['id']
      control_info['is_on'] = control['is_on']
      control_info['rule_based_distribution_default_variation'] = control['rule_based_distribution_default_variation']
      control_info['rule_sets'] = control['rule_sets']
      control_info['distributions'] = control['distributions']
      control_info['type'] = control['type']
      control_info['default_variation'] = control['default_variation']

      enablements = control['enablements']
      enablements_info = {}

      enablements.each do |enablement|
        client_identities_map = enablements_info[enablement['client_object_type_name']]

        if client_identities_map.nil?
          enablements_info[enablement['client_object_type_name']] = {}
        end

        enablements_info[enablement['client_object_type_name']][enablement['client_object_identity']] = [enablement['is_enabled'], enablement['variation']]
      end

      control_info['enablements_info'] = enablements_info

      map[control['short_name']] = control_info
    end

    map
  end

  def _poll
    conn = Faraday.new(url: "#{GATING_INFO_ENDPOINT}/#{@env_key}")
    response = conn.get do |req|
      req.options.timeout = 10
      req.headers['api-key'] = @api_key
    end
    if response.status == 200
      gating_info = JSON.parse(response.body)

      if gating_info['server_info'] == 'maintenance'
        return
      end

      gating_info_map = self._get_gating_info_map(gating_info)
      @gating_info = gating_info
      @gating_info_map = gating_info_map
    end
  end

  def _create_poller
    Concurrent::TimerTask.new(execution_interval: @gating_info_polling_interval, timeout_interval: 10) do |task|
      self._poll
    end
  end

  def _create_watcher
    Concurrent::TimerTask.new(execution_interval: @gate_stats_upload_batch_interval, timeout_interval: 10) do |task|
      now = Time.now.utc.to_i
      if now - @gate_stats_last_task_scheduled_timestamp >= @gate_stats_upload_batch_interval
        processed = self._process_batch(0)
        if processed
          @gate_stats_last_task_scheduled_timestamp = now
        end
      end
    end
  end

  def _create_processor(batch)
    return Concurrent::ScheduledTask.execute(0) do |task|
      conn = Faraday.new(url: IDENTIFY_ENDPOINT)
      response = conn.post do |req|
        req.options.timeout = 10
        req.headers['Content-Type'] = 'application/json'
        req.headers['api-key'] = @api_key
        req.body = JSON.generate({
          'env_key' => @env_key,
          'objects' => batch,
        })
      end
    end
  end

  def _process_batch(limit, gate_stats=nil)
    # This is sort of a weird function.
    # We process the batch if the batch size
    # is more than limit. The second param
    # allows for an additional gate_states to
    # be inserted before the processing check
    # is performed.

    processed = false
    @gate_stats_batch_lock.acquire
    if !gate_stats.nil?
      @gate_stats_batch.push(gate_stats)
    end
    if @gate_stats_batch.size > limit || @first_gate
      @first_gate = false
      new_gate_stats_uploader_tasks = []
      @gate_stats_uploader_tasks.each do |task|
        if !task.fulfilled?
          new_gate_stats_uploader_tasks.push(task)
        end
      end
      old_batch = @gate_stats_batch
      @gate_stats_batch = []
      new_gate_stats_uploader_tasks.push(self._create_processor(old_batch))
      @gate_stats_uploader_tasks = new_gate_stats_uploader_tasks
      processed = true
    end
    @gate_stats_batch_lock.release
    processed
  end

  def _upload_stats_async(gate_stats)
    processed = self._process_batch(@max_gate_stats_batch_size - 1, gate_stats)
    if processed
      now = Time.now.utc.to_i
      @gate_stats_last_task_scheduled_timestamp = now
    end
  end

  def _satisfies_rule(rule, object)
    attribute_type = rule['attribute_type']
    operator = rule['operator']
    attribute_name = rule['attribute_name']
    value = rule['value']
    value_list = rule['value_list']

    if object['attributes'].nil? || object['attributes'][attribute_name].nil?
      return false
    end

    attribute_val = object['attributes'][attribute_name]

    if attribute_type == OBJECT_ATTRIBUTE_TYPE_STRING
      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      elsif operator == RULE_OPERATOR_TYPE_IN
        return !value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_NOT_IN
        return value_list.index(attribute_val).nil?
      else
        return false
      end
    elsif attribute_type == OBJECT_ATTRIBUTE_TYPE_INT
      value = value && value.to_i
      value_list = value_list && value_list.map { |v| v.to_i }

      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      elsif operator == RULE_OPERATOR_TYPE_IN
        return !value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_NOT_IN
        return value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_LT
        return attribute_val < value
      elsif operator == RULE_OPERATOR_TYPE_LTE
        return attribute_val <= value
      elsif operator == RULE_OPERATOR_TYPE_GT
        return attribute_val > value
      elsif operator == RULE_OPERATOR_TYPE_GTE
        return attribute_val >= value
      else
        return false
      end
    elsif attribute_type == OBJECT_ATTRIBUTE_TYPE_FLOAT
      value = value && value.to_f
      value_list = value_list && value_list.map { |v| v.to_f }

      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      elsif operator == RULE_OPERATOR_TYPE_IN
        return !value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_NOT_IN
        return value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_LT
        return attribute_val < value
      elsif operator == RULE_OPERATOR_TYPE_LTE
        return attribute_val <= value
      elsif operator == RULE_OPERATOR_TYPE_GT
        return attribute_val > value
      elsif operator == RULE_OPERATOR_TYPE_GTE
        return attribute_val >= value
      else
        return false
      end
    elsif attribute_type == OBJECT_ATTRIBUTE_TYPE_BOOLEAN
      value = (value == 'true') ? true : false
      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      else
        return false
      end
    elsif attribute_type == OBJECT_ATTRIBUTE_TYPE_DATE
      unix_timestamp = nil
      begin
        unix_timestamp = DateTime.parse(attribute_val).to_time.to_i
      rescue Exception => e
        return false
      end

      iso_format = DateTime.parse(attribute_val).iso8601

      if !iso_format.end_with?('T00:00:00+00:00')
        return false
      end

      value = value && DateTime.parse(value).to_time.to_i
      value_list = value_list && value_list.map { |v| DateTime.parse(v).to_time.to_i }

      attribute_val = unix_timestamp

      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      elsif operator == RULE_OPERATOR_TYPE_IN
        return !value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_NOT_IN
        return value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_FROM
        return attribute_val >= value
      elsif operator == RULE_OPERATOR_TYPE_UNTIL
        return attribute_val <= value
      elsif operator == RULE_OPERATOR_TYPE_AFTER
        return attribute_val > value
      elsif operator == RULE_OPERATOR_TYPE_BEFORE
        return attribute_val < value
      else
        return false
      end
    elsif attribute_type == OBJECT_ATTRIBUTE_TYPE_DATETIME
      # to_time.to_i respects timezones
      unix_timestamp = nil
      begin
        unix_timestamp = DateTime.parse(attribute_val).to_time.to_i
      rescue Exception => e
        return false
      end

      value = value && DateTime.parse(value).to_time.to_i
      value_list = value_list && value_list.map { |v| DateTime.parse(v).to_time.to_i }

      attribute_val = unix_timestamp

      if operator == RULE_OPERATOR_TYPE_IS
        return attribute_val == value
      elsif operator == RULE_OPERATOR_TYPE_IS_NOT
        return attribute_val != value
      elsif operator == RULE_OPERATOR_TYPE_IN
        return !value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_NOT_IN
        return value_list.index(attribute_val).nil?
      elsif operator == RULE_OPERATOR_TYPE_FROM
        return attribute_val >= value
      elsif operator == RULE_OPERATOR_TYPE_UNTIL
        return attribute_val <= value
      elsif operator == RULE_OPERATOR_TYPE_AFTER
        return attribute_val > value
      elsif operator == RULE_OPERATOR_TYPE_BEFORE
        return attribute_val < value
      else
        return false
      end
    else
      return false
    end
  end

  def _get_gate_values_for_object(control_info, object)
    if !control_info['enablements_info'][object['type']].nil?
      if !control_info['enablements_info'][object['type']][object['id']].nil?
        is_enabled, variation = control_info['enablements_info'][object['type']][object['id']]
        return {
          'is_enabled' => is_enabled,
          'variation' => variation,
          'is_eligible' => is_enabled,
          '_from_enablement' => true,
        }
      end
    end

    sampled_inside_base_population = false
    is_eligible = false
    control_info['rule_sets'].each do |rule_set|
      if sampled_inside_base_population
        break
      end

      rules = rule_set['rules']

      if rule_set['client_object_type_name'] != object['type']
        next
      end

      satisfies_all_rules = true
      rules.each do |rule|
        satisfies_all_rules = satisfies_all_rules && self._satisfies_rule(rule, object)
      end

      if satisfies_all_rules
        is_eligible = true
        hash_key = "SAMPLING:control_#{control_info['id']}:env_#{@gating_info['env']['id']}:rule_set_#{rule_set['id']}:client_object_#{object['type']}_#{object['id']}"
        if Airship.get_hashed_value(hash_key) <= rule_set['sampling_percentage']
          sampled_inside_base_population = true
        end
      end
    end

    if !sampled_inside_base_population
      return {
        'is_enabled' => false,
        'variation' => nil,
        'is_eligible' => is_eligible,
      }
    end

    if control_info['type'] == CONTROL_TYPE_BOOLEAN
      return {
        'is_enabled' => true,
        'variation' => nil,
        'is_eligible' => true,
      }
    elsif control_info['type'] == CONTROL_TYPE_MULTIVARIATE
      if control_info['distributions'].size == 0
        return {
          'is_enabled' => true,
          'variation' => control_info['default_variation'],
          'is_eligible' => true,
        }
      end

      percentage_based_distributions = control_info['distributions'].select { |d| d['type'] == DISTRIBUTION_TYPE_PERCENTAGE_BASED }
      rule_based_distributions = control_info['distributions'].select { |d| d['type'] == DISTRIBUTION_TYPE_RULE_BASED }

      if percentage_based_distributions.size != 0 && rule_based_distributions.size != 0
        puts 'Rule integrity error: please contact support@airshiphq.com'
        return {
          'is_enabled' => false,
          'variation' => nil,
          'is_eligible' => false,
        }
      end

      if percentage_based_distributions.size != 0
        delta = 0.0001
        sum_percentages = 0.0
        running_percentages = []
        percentage_based_distributions.each do |distribution|
          sum_percentages += distribution['percentage']
          if running_percentages.size == 0
            running_percentages.push(distribution['percentage'])
          else
            running_percentages.push(running_percentages[running_percentages.size - 1] + distribution['percentage'])
          end
        end

        if (1.0 - sum_percentages).abs > delta
          puts 'Rule integrity error: please contact support@airshiphq.com'
          return {
            'is_enabled' => false,
            'variation' => nil,
            'is_eligible' => false,
          }
        end

        hash_key = "DISTRIBUTION:control_#{control_info['id']}:env_#{@gating_info['env']['id']}:client_object_#{object['type']}_#{object['id']}"
        hashed_percentage = Airship.get_hashed_value(hash_key)

        running_percentages.each_with_index do |percentage, i|
          if hashed_percentage <= percentage
            return {
              'is_enabled' => true,
              'variation' => percentage_based_distributions[i]['variation'],
              'is_eligible' => true,
            }
          end
        end

        return {
          'is_enabled' => true,
          'variation' => percentage_based_distributions[percentage_based_distributions.size - 1]['variation'],
          'is_eligible' => true,
        }
      else
        rule_based_distributions.each do |distribution|

          rule_set = distribution['rule_set']
          rules = rule_set['rules']

          if rule_set['client_object_type_name'] != object['type']
            next
          end

          satisfies_all_rules = true
          rules.each do |rule|
            satisfies_all_rules = satisfies_all_rules && self._satisfies_rule(rule, object)
          end

          if satisfies_all_rules
            return {
              'is_enabled' => true,
              'variation' => distribution['variation'],
              'is_eligible' => true,
            }
          end
        end

        return {
          'is_enabled' => true,
          'variation' => control_info['rule_based_distribution_default_variation'] || control_info['default_variation'],
          'is_eligible' => true,
          '_rule_based_default_variation' => true,
        }
      end
    else
      return {
        'is_enabled' => false,
        'variation' => nil,
        'is_eligible' => false,
      }
    end
  end

  def _get_gate_values(control_short_name, object)
    if @gating_info_map[control_short_name].nil?
      return {
        'is_enabled' => false,
        'variation' => nil,
        'is_eligible' => false,
        '_should_send_stats' => false,
      }
    end

    control_info = @gating_info_map[control_short_name]

    if !control_info['is_on']
      return {
        'is_enabled' => false,
        'variation' => nil,
        'is_eligible' => false,
        '_should_send_stats' => true,
      }
    end

    group = nil
    if !object['group'].nil?
      group = object['group']
    end

    result = self._get_gate_values_for_object(control_info, object)

    if !group.nil?
      if group['type'].nil?
        group['type'] = "#{object['type']}Group"
        group['is_group'] = true
      end
      group_result = self._get_gate_values_for_object(control_info, group)

      if result['_from_enablement'] == true && !result['is_enabled']
        # Do nothing
      elsif result['_from_enablement'] != true && group_result['_from_enablement'] == true && !group_result['is_enabled']
        result['is_enabled'] = group_result['is_enabled']
        result['variation'] = group_result['variation']
        result['is_eligible'] = group_result['is_eligible']
      elsif result['is_enabled']
        if result['_rule_based_default_variation'] == true
          if group_result['is_enabled']
            result['is_enabled'] = group_result['is_enabled']
            result['variation'] = group_result['variation']
            result['is_eligible'] = group_result['is_eligible']
          else
            # Do nothing
          end
        else
          # Do nothing
        end
      elsif group_result['is_enabled']
        result['is_enabled'] = group_result['is_enabled']
        result['variation'] = group_result['variation']
        result['is_eligible'] = group_result['is_eligible']
      else
        # Do nothing
      end
    end

    result['_should_send_stats'] = true
    result
  end

  def _clone_object(object)
    copy = object.clone

    if !object['attributes'].nil?
      copy['attributes'] = object['attributes'].clone
    end

    if !object['group'].nil?
      copy['group'] = object['group'].clone

      if !object['group']['attributes'].nil?
        copy['group']['attributes'] = object['group']['attributes'].clone
      end
    end

    copy
  end

  def _validate_nesting(object)
    if object['is_group'] == true && !object['group'].nil?
      return 'A group cannot be nested inside another group'
    end
  end

  def _maybe_transform_id(object)
    if object['id'].is_a?(Integer)
      id_str = object['id'].to_s
      if id_str.length > 250
        return 'Integer id must have 250 digits or less'
      end
      object['id'] = id_str
    end

    group = nil
    if !object['group'].nil?
      group = object['group']
    end

    if !group.nil?
      if group['id'].is_a?(Integer)
        id_str = group['id'].to_s
        if id_str.length > 250
          return 'Integer id must have 250 digits or less'
        end
        group['id'] = id_str
      end
    end

    nil
  end
end
