require 'faraday'
require 'json'
require 'concurrent'

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

  def uploadStatsAsync(stats)
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
