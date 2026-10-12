require "fiber/execution_context"

module FFmpegGUI
  # Process I/O runs on isolated system threads. The UI thread only reads
  # snapshots and sends cancellation requests; it never waits for a child.
  class Job
    @mutex = Mutex.new
    @done = false
    @cancelled = false
    @success = false
    @output = ""
    @log = ""
    @seconds = 0.0
    @speed = "—"
    @exit_code : Int32?
    @pixels : Bytes?
    @process : Process?
    @cancel_at : Time::Instant?
    @worker : Fiber::ExecutionContext::Isolated

    def initialize(@command : String, @args : Array(String), @progress = false, @frame_bytes : Int32? = nil)
      @worker = Fiber::ExecutionContext::Isolated.new("ffmpeg-job") { run_process }
    end

    def done : Bool
      @mutex.synchronize { @done }
    end

    def cancelled : Bool
      @mutex.synchronize { @cancelled }
    end

    def success : Bool
      @mutex.synchronize { @success }
    end

    def output : String
      @mutex.synchronize { @output }
    end

    def log : String
      @mutex.synchronize { @log }
    end

    def seconds : Float64
      @mutex.synchronize { @seconds }
    end

    def speed : String
      @mutex.synchronize { @speed }
    end

    def exit_code : Int32?
      @mutex.synchronize { @exit_code }
    end

    def pixels : Bytes?
      @mutex.synchronize { @pixels }
    end

    def cancel
      process = @mutex.synchronize do
        next nil if @done || @cancelled
        @cancelled = true
        @cancel_at = Time.instant
        @process
      end
      process.try &.terminate(graceful: true)
    rescue IO::Error | RuntimeError
      # The child may have exited just before the cancellation request.
    end

    def tick
      process = @mutex.synchronize do
        if (at = @cancel_at) && !@done && at.elapsed > 3.seconds && @process
          @cancel_at = nil
          @process
        end
      end
      process.try &.terminate(graceful: false)
    rescue IO::Error | RuntimeError
    end

    private def run_process
      process = Process.new(@command, @args, input: Process::Redirect::Close,
        output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
      cancelled = @mutex.synchronize do
        @process = process
        @cancelled
      end
      process.terminate(graceful: true) if cancelled
      stderr_worker = Fiber::ExecutionContext::Isolated.new("ffmpeg-stderr") { read_stderr(process) }
      output_ok = read_stdout(process)
      stderr_worker.wait
      status = process.wait
      @mutex.synchronize do
        @exit_code = status.exit_code
        @success = output_ok && status.success? && !@cancelled
      end
    rescue ex
      append_log("\n#{ex.message}\n")
    ensure
      @mutex.synchronize do
        @process = nil
        @done = true
      end
    end

    private def read_stdout(process : Process) : Bool
      if frame_bytes = @frame_bytes
        pixels = Bytes.new(frame_bytes)
        process.output.read_fully(pixels)
        @mutex.synchronize { @pixels = pixels }
        process.output.skip_to_end
      else
        process.output.each_line do |line|
          if @progress
            key, _, value = line.partition('=')
            @mutex.synchronize do
              case key
              when "out_time_us" then @seconds = (value.to_f64? || 0.0) / 1_000_000
              when "speed"       then @speed = value.strip
              end
            end
          else
            @mutex.synchronize { @output = (@output + line + "\n").byte_slice(0, 1_048_576) }
          end
        end
      end
      true
    rescue ex
      append_log("\n#{ex.message}\n")
      process.output.skip_to_end rescue nil
      false
    end

    private def read_stderr(process : Process)
      process.error.each_line { |line| append_log(line.scrub + "\n") }
    rescue ex
      append_log("\n#{ex.message}\n")
    end

    private def append_log(text : String)
      @mutex.synchronize do
        @log += text
        @log = @log[-32_000..] if @log.size > 32_000
      end
    end
  end
end
