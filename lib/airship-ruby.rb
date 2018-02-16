require 'faraday'
require 'json'
require 'concurrent'

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
      "type" => "string",
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
          "type" => "string",
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
      "required" => ["id", "displayName"],
      "additionalProperties" => false,
    },
  },
  "required" => ["type", "id", "displayName"],
  "additionalProperties" => false,
}

class Airship
  def initialize(options)
    @gatingInfo = nil
    @gatingInfoDownloaderTask = nil

    @gatingInfoMap = nil

    @maxGateStatsBatchSize = 500
    @gateStatsUploadBatchInterval = 60

    @gateStatsWatcher = nil
    @gateStatsLastTaskScheduledTimestamp = Concurrent::AtomicFixnum.new(0)

    @gateStatsUploaderTasks = []

    @gateStatsBatch = []

    @gateStatsBatchLock = Concurrent::Semaphore.new(1)
  end

  def init
    # Not thread safe yet
    if @gatingInfoDownloaderTask.nil?
      @gatingInfoDownloaderTask = self._createPoller
      @gatingInfoDownloaderTask.execute
    end

    if @gateStatsWatcher.nil?
      @gateStatsWatcher = self._createWatcher
      @gateStatsWatcher.execute
    end
    # Thread safe after this point
  end

  def _createPoller
    Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
      # TODO: use Faraday to pull info
    end
  end

  def _createWatcher
    Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
      now = Time.now.utc.to_i
      if now - @gateStatsLastTaskScheduledTimestamp.value >= 60
        processed = self._processBatch(0)
        if processed
          @gateStatsLastTaskScheduledTimestamp.value = now
        end
      end
    end
  end

  def _createProcessor(batch)
    return Concurrent::ScheduledTask.execute(0) do |task|
      # TODO: use Faraday to upload
    end
  end

  def _processBatch(limit)
    processed = false
    @gateStatsBatchLock.acquire
    if @gateStatsBatch.size > limit
      newGateStatsUploaderTasks = []
      @gateStatsUploaderTasks.each do |task|
        if !task.fulfilled?
          newGateStatsUploaderTasks.push(task)
        end
      end
      oldBatch = @gateStatsBatch
      @gateStatsBatch = []
      newGateStatsUploaderTasks.push(self._createProcessor(oldBatch))
      @gateStatsUploaderTasks = newGateStatsUploaderTasks
      processed = true
    end
    @gateStatsBatchLock.release
    processed
  end

  def _checkBatchSizeAndMaybeProcess
    processed = self._processBatch(@maxGateStatsBatchSize - 1)
    if processed
      now = Time.now.utc.to_i
      @gateStatsLastTaskScheduledTimestamp.value = now
    end
  end

  def _uploadStatsAsync(stats)
    @gateStatsBatchLock.acquire
    @gateStatsBatch.push(stats)
    @gateStatsBatchLock.release

    self._checkBatchSizeAndMaybeProcess
  end

  def enabled?(controlShortName, object)
    false
  end

  def variation(controlShortName, object)
    nil
  end

  def eligible?(controlShortName, object)
    false
  end
end
