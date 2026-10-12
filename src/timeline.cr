require "./command"

module FFmpegGUI
  class Timeline
    getter area : UIng::Area
    property duration = 0.0
    property from = 0.0
    property ending = 0.0
    property progress = 0.0
    property running = false
    property title = I18n.t!("ui.choose_source")
    property subtitle = ""
    property preview_message = I18n.t!("preview.open_file")
    property video_size : Tuple(Int32, Int32)?
    getter crop : Crop?
    getter cursor = 0.0
    @editable = true
    @drag : Symbol?
    @crop_editable = true
    @crop_anchor : Tuple(Float64, Float64)?
    @on_crop : Proc(Crop?, Nil)?
    @frame : UIng::Image?
    @frame_time = 0.0
    @handler : UIng::Area::Handler
    @font : UIng::FontDescriptor
    @heading : UIng::FontDescriptor

    def initialize(@on_seek : Proc(Float64, Nil), &@on_trim : Float64, Bool -> Nil)
      @font = UIng::FontDescriptor.new(size: 10)
      @heading = UIng::FontDescriptor.new(size: 13, weight: :bold)
      @handler = UIng::Area::Handler.new
      @area = UIng::Area.new(@handler)
      @handler.draw { |_, params| draw(params) }
      @handler.mouse_event do |_, event|
        next unless @editable && event.area_width > 64
        if event.down == 1 && @duration > 0 && event.y.in?((event.area_height - 44)..(event.area_height - 12))
          begin_drag(event.x, event.area_width)
        elsif event.down == 1 && @crop_editable
          begin_crop(event.x, event.y, event.area_width, event.area_height)
        elsif @drag == :crop && (event.held1_to64 & 1 != 0 || event.up == 1)
          drag_crop_to(event.x, event.y, event.area_width, event.area_height)
        elsif @drag && (event.held1_to64 & 1 != 0 || event.up == 1)
          drag_to(event.x, event.area_width)
        end
        @crop_anchor = nil if event.up == 1
        @drag = nil if event.up == 1
      end
      @handler.drag_broken do
        @crop_anchor = nil
        @drag = nil
      end
      @handler.key_event do |_, event|
        next false if event.up? || !@editable || @duration <= 0
        step = event.modifiers.shift? ? 10.0 : 1.0
        case event.ext_key
        when UIng::Area::ExtKey::Left  then seek(@cursor - step)
        when UIng::Area::ExtKey::Right then seek(@cursor + step)
        when UIng::Area::ExtKey::Home  then seek(0.0)
        when UIng::Area::ExtKey::End   then seek(@duration)
        else
          case event.key.try &.downcase
          when 'i' then trim_at_cursor(false)
          when 'o' then trim_at_cursor(true)
          else          next false
          end
        end
        true
      end
    end

    def editable=(value : Bool)
      @editable = value
      @drag = nil unless value
      @crop_anchor = nil unless value
    end

    def crop_editable=(value : Bool)
      @crop_editable = value
      @crop_anchor = nil unless value
      @drag = nil if !value && @drag == :crop
      @area.queue_redraw_all
    end

    def on_crop(&block : Crop? -> Nil)
      @on_crop = block
    end

    def reset_crop
      return unless @crop
      @crop = nil
      @on_crop.try &.call(nil)
      @area.queue_redraw_all
    end

    def begin_crop(x : Float64, y : Float64, width : Float64, height : Float64)
      return unless @editable && @crop_editable && @frame
      if point = source_point(x, y, width, height)
        @drag = :crop
        @crop_anchor = point
      end
    end

    def drag_crop_to(x : Float64, y : Float64, width : Float64, height : Float64)
      return unless @editable && @drag == :crop
      return unless anchor = @crop_anchor
      return unless point = source_point(x, y, width, height, clamp: true)
      source_width, source_height = @video_size.not_nil!
      return if (anchor[0] - point[0]).abs < 2 || (anchor[1] - point[1]).abs < 2
      left = Math.min(anchor[0], point[0]).round.to_i.clamp(0, source_width - 2)
      top = Math.min(anchor[1], point[1]).round.to_i.clamp(0, source_height - 2)
      right = Math.max(anchor[0], point[0]).round.to_i.clamp(left + 2, source_width)
      bottom = Math.max(anchor[1], point[1]).round.to_i.clamp(top + 2, source_height)
      selected = Crop.new(left, top, right - left, bottom - top)
      return if selected == @crop
      @crop = selected
      @on_crop.try &.call(@crop)
      @area.queue_redraw_all
    end

    def seek(seconds : Float64)
      return unless @editable
      @cursor = seconds.clamp(0.0, @duration)
      @on_seek.call(@cursor)
      @area.queue_redraw_all
    end

    def trim_at_cursor(finish : Bool)
      return unless @editable && @duration > 0
      update_trim(@cursor, finish)
    end

    def begin_drag(x : Float64, width : Float64)
      return unless @editable && @duration > 0 && width > 48
      left = 24 + (@from / @duration) * (width - 48)
      right = 24 + (@ending / @duration) * (width - 48)
      @drag = if (x - left).abs <= 12 && (x - left).abs <= (x - right).abs
                :from
              elsif (x - right).abs <= 12
                :ending
              else
                :cursor
              end
      drag_to(x, width)
    end

    def drag_to(x : Float64, width : Float64)
      return unless @editable && @duration > 0 && width > 48
      seconds = ((x - 24) / (width - 48)).clamp(0.0, 1.0) * @duration
      case @drag
      when :from   then update_trim(seconds, false)
      when :ending then update_trim(seconds, true)
      when :cursor then seek(seconds)
      end
    end

    private def update_trim(seconds, finish)
      gap = Math.min(0.001, @duration)
      lower = @from.clamp(0.0, @duration - gap)
      upper = @ending.clamp(gap, @duration)
      value = finish ? seconds.clamp(lower + gap, @duration) : seconds.clamp(0.0, upper - gap)
      @on_trim.call(value, finish)
      seek(value)
    end

    def frame=(frame : Tuple(Bytes, Float64)?)
      @frame.try &.free
      @frame = nil
      if frame
        image = UIng::Image.new(Preview::WIDTH, Preview::HEIGHT)
        image.append(frame[0], Preview::WIDTH, Preview::HEIGHT, Preview::WIDTH * 4)
        @frame = image
        @frame_time = frame[1]
      end
      @area.queue_redraw_all
    end

    def reset
      @cursor = 0.0
      @drag = nil
      @crop_anchor = nil
      @crop = nil
      @video_size = nil
      self.frame = nil
    end

    def free
      @frame.try &.free
      @frame = nil
      @font.free
      @heading.free
    end

    def self.time(seconds : Float64) : String
      value = seconds.clamp(0.0, 359_999.0)
      "%02d:%02d:%05.2f" % [value.to_i // 3600, value.to_i // 60 % 60, value % 60]
    end

    private def rect(ctx, x, y, w, h, color)
      return if w <= 0 || h <= 0
      ctx.fill_path(UIng::Area::Draw::Brush.new(:solid, *color)) { |path| path.add_rectangle(x, y, w, h) }
    end

    private def text(ctx, value, x, y, width, font, color)
      return if width <= 0
      UIng::Area::AttributedString.open(value) do |str|
        str.set_attribute(UIng::Area::Attribute.new_color(*color), 0, str.len)
        UIng::Area::Draw::TextLayout.open(string: str, default_font: font, width: width) do |layout|
          ctx.draw_text_layout(layout, x, y)
        end
      end
    end

    private def picture_rect(area_width : Float64, area_height : Float64) : Tuple(Float64, Float64, Float64, Float64)?
      return unless size = @video_size
      source_width, source_height = size
      return if source_width < 2 || source_height < 2
      preview_width = (area_width - 64) * 0.62
      preview_height = area_height - 104
      return if preview_width <= 0 || preview_height <= 0
      display_scale = Math.min(preview_width / Preview::WIDTH, preview_height / Preview::HEIGHT)
      frame_x = 24 + (preview_width - Preview::WIDTH * display_scale) / 2
      frame_y = 40 + (preview_height - Preview::HEIGHT * display_scale) / 2
      source_scale = Math.min(Preview::WIDTH / source_width, Preview::HEIGHT / source_height)
      picture_width = source_width * source_scale * display_scale
      picture_height = source_height * source_scale * display_scale
      {frame_x + (Preview::WIDTH - source_width * source_scale) * display_scale / 2,
       frame_y + (Preview::HEIGHT - source_height * source_scale) * display_scale / 2,
       picture_width, picture_height}
    end

    private def source_point(x : Float64, y : Float64, area_width : Float64, area_height : Float64, clamp = false) : Tuple(Float64, Float64)?
      return unless picture = picture_rect(area_width, area_height)
      px, py, pw, ph = picture
      return if !clamp && (x < px || x > px + pw || y < py || y > py + ph)
      source_width, source_height = @video_size.not_nil!
      {((x - px) / pw * source_width).clamp(0.0, source_width.to_f),
       ((y - py) / ph * source_height).clamp(0.0, source_height.to_f)}
    end

    private def draw_crop(ctx, area_width : Float64, area_height : Float64)
      return unless selected = @crop
      return unless picture = picture_rect(area_width, area_height)
      px, py, pw, ph = picture
      source_width, source_height = @video_size.not_nil!
      left = px + selected.x / source_width * pw
      top = py + selected.y / source_height * ph
      right = left + selected.width / source_width * pw
      bottom = top + selected.height / source_height * ph
      shade = {0.0, 0.0, 0.0, @crop_editable ? 0.55 : 0.35}
      rect(ctx, px, py, pw, top - py, shade)
      rect(ctx, px, bottom, pw, py + ph - bottom, shade)
      rect(ctx, px, top, left - px, bottom - top, shade)
      rect(ctx, right, top, px + pw - right, bottom - top, shade)
      border = @crop_editable ? {0.24, 0.83, 0.70, 1.0} : {0.52, 0.62, 0.72, 1.0}
      rect(ctx, left, top, right - left, 2, border)
      rect(ctx, left, bottom - 2, right - left, 2, border)
      rect(ctx, left, top, 2, bottom - top, border)
      rect(ctx, right - 2, top, 2, bottom - top, border)
    end

    private def draw(params)
      ctx = params.context
      w, h = params.area_width, params.area_height
      return if w < 160 || h < 100
      ink = {0.88, 0.93, 0.98, 1.0}
      muted = {0.52, 0.62, 0.72, 1.0}
      accent = {0.24, 0.83, 0.70, 1.0}
      rect(ctx, 0, 0, w, h, {0.055, 0.085, 0.13, 1.0})
      text(ctx, @title, 24, 10, w - 48, @heading, ink)
      preview_h = h - 104
      if preview_h >= 40
        preview_w = (w - 64) * 0.62
        rect(ctx, 24, 40, preview_w, preview_h, {0.025, 0.035, 0.055, 1.0})
        if frame = @frame
          scale = Math.min(preview_w / Preview::WIDTH, preview_h / Preview::HEIGHT)
          iw, ih = Preview::WIDTH * scale, Preview::HEIGHT * scale
          ctx.draw_image(frame, 24 + (preview_w - iw) / 2, 40 + (preview_h - ih) / 2, iw, ih)
          draw_crop(ctx, w, h)
        else
          text(ctx, @preview_message, 36, 48, preview_w - 24, @font, muted)
        end
        x = preview_w + 44
        text(ctx, I18n.t!("timeline.displayed_frame", time: Timeline.time(@frame_time)), x, 42, w - x - 24, @font, ink) if @frame
        text(ctx, @preview_message, x, 65, w - x - 24, @font, muted)
        if preview_h >= 105
          text(ctx, I18n.t!("timeline.selection", time: Timeline.time(Math.max(0.0, @ending - @from))), x, 100, w - x - 24, @heading, accent)
          text(ctx, @subtitle, x, 128, w - x - 24, @font, muted) if preview_h >= 135
          if @video_size && preview_h >= 170
            crop_status = if @crop_editable
                            if selected = @crop
                              I18n.t!("timeline.crop_selected", width: selected.width, height: selected.height, x: selected.x, y: selected.y)
                            else
                              I18n.t!("timeline.crop_hint")
                            end
                          else
                            I18n.t!("timeline.crop_unavailable")
                          end
            text(ctx, crop_status, x, 155, w - x - 24, @font, @crop_editable ? accent : muted)
          end
        end
      end
      y = h - 36
      bar_width = w - 48
      rect(ctx, 24, y, bar_width, 16, {0.13, 0.20, 0.27, 1.0})
      if @duration > 0
        left = (@from / @duration).clamp(0.0, 1.0)
        right = (@ending / @duration).clamp(left, 1.0)
        rect(ctx, 24 + left * bar_width, y, (right - left) * bar_width, 16, {0.12, 0.40, 0.40, 1.0})
        rect(ctx, 20 + left * bar_width, y - 4, 8, 24, accent)
        rect(ctx, 20 + right * bar_width, y - 4, 8, 24, accent)
        position = @running ? left + (right - left) * @progress.clamp(0.0, 1.0) : (@cursor / @duration).clamp(0.0, 1.0)
        rect(ctx, 24 + position * bar_width - 1, y - 6, 2, 28, {1.0, 0.78, 0.30, 1.0})
      end
      column_width = bar_width / 4
      text(ctx, I18n.t!("timeline.position", time: Timeline.time(@cursor)), 24, h - 59, column_width, @font, ink)
      text(ctx, "IN #{Timeline.time(@from)}", 24 + column_width, h - 59, column_width, @font, accent)
      text(ctx, "OUT #{Timeline.time(@ending)}", 24 + column_width * 2, h - 59, column_width, @font, accent)
      text(ctx, I18n.t!("timeline.total", time: Timeline.time(@duration)), 24 + column_width * 3, h - 59, column_width, @font, muted)
    end
  end
end
