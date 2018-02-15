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

    @gateStatsUploaderTasks = []

    @gateStatsBatch = []

    @initLock = Concurrent::Semaphore.new(1)
    @gateStatsWatcherLock = Concurrent::Semaphore.new(1)
    @gateStatsUploaderTasksLock = Concurrent::Semaphore.new(1)
  end

  def init()
    @initLock.acquire

    if @gatingInfoDownloaderTask.nil?
      @gatingInfoDownloaderTask = Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
        puts "Pulling data from server\n"
      end
      @gatingInfoDownloaderTask.execute
    end

    if @gateStatsWatcher.nil?
      @gateStatsWatcher = Concurrent::TimerTask.new(execution_interval: 60, timeout_interval: 10, run_now: true) do |task|
        puts "Uploading data to server\n"
      end
      @gateStatsWatcher.execute
    end

    @initLock.release
  end
end
