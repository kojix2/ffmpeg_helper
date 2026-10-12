require "./job"
require "./localization"

module FFmpegGUI
  # Decode just one source frame. Coalesce scrubbing requests and discard stale
  # results so a slow decode can never replace a newer file or seek position.
  class Preview
    WIDTH  = 480
    HEIGHT = 270
    getter pixels : Bytes?
    getter time = 0.0
    getter revision = 0
    getter message = I18n.t!("preview.open_file")
    @requested : Tuple(String, Float64)?
    @active : Tuple(String, Float64)?
    @job : Job?
    @changed = Time.instant
    @started = Time.instant

    def request(path : String, seconds : Float64)
      request = {File.expand_path(path), seconds.round(3)}
      return if @requested == request
      @requested = request
      @changed = Time.instant
      @message = I18n.t!("preview.loading")
    end

    def clear(message = I18n.t!("preview.open_file"))
      cancel
      @pixels = nil
      @revision += 1
      @message = message
    end

    def cancel
      @requested = nil
      @active = nil
      @job.try &.cancel
    end

    def busy? : Bool
      !@job.nil?
    end

    def tick
      if job = @job
        job.tick
        job.cancel if @started.elapsed > 10.seconds
        return unless job.done
        if @active == @requested && @requested
          if job.success && (pixels = job.pixels)
            @pixels = pixels
            @time = @requested.not_nil![1]
            @message = I18n.t!("preview.source_frame")
          else
            @pixels = nil
            @message = I18n.t!("preview.failed")
          end
          @revision += 1
        end
        @job = nil
      end
      if request = @requested
        if @active != request && @changed.elapsed >= 180.milliseconds
          @active = request
          @started = Time.instant
          @job = Job.new("ffmpeg", self.class.args(*request), frame_bytes: WIDTH * HEIGHT * 4)
        end
      end
    rescue ex
      @message = I18n.t!("preview.launch_error", error: ex.message.to_s)
      @pixels = nil
      @revision += 1
    end

    def self.args(path : String, seconds : Float64) : Array(String)
      ["-v", "error", "-nostdin", "-ss", seconds.to_s, "-i", File.expand_path(path),
       "-map", "0:v:0", "-frames:v", "1", "-an", "-sn",
       "-vf", "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=decrease,pad=#{WIDTH}:#{HEIGHT}:(ow-iw)/2:(oh-ih)/2,setsar=1",
       "-pix_fmt", "rgba", "-f", "rawvideo", "pipe:1"]
    end
  end
end
